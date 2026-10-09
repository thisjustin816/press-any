import EmulatorApplication
import EmulatorDomain
import EmulationCore
import Foundation

public enum PersistentSaveServiceError: Error, Equatable, LocalizedError {
    case profileNotFound(UUID)
    case assetNotFound(UUID)
    case hashMismatch(assetID: UUID, expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .hashMismatch:
            return "This Save Profile's save file is damaged, so the game didn't start. The file was kept."
        default:
            return nil
        }
    }
}

public struct PersistentSaveService: Sendable {
    private let profiles: any SaveProfileRepository
    private let assets: any ManagedAssetRepository
    private let assetStore: any AssetStore
    private let now: @Sendable () -> Date

    public init(
        profiles: any SaveProfileRepository,
        assets: any ManagedAssetRepository,
        assetStore: any AssetStore,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.profiles = profiles
        self.assets = assets
        self.assetStore = assetStore
        self.now = now
    }

    @discardableResult
    public func flush(worker: SessionWorker, profileID: UUID, buildID: UUID) throws -> SaveProfile {
        guard let profile = try profiles.fetchSaveProfile(id: profileID) else {
            throw PersistentSaveServiceError.profileNotFound(profileID)
        }

        let battery = try worker.perform { try $0.persistentSaveData() }
        guard !battery.isEmpty else { return profile }
        return try replacePersistentSaveData(battery, profileID: profileID, writtenByBuildID: buildID)
    }

    /// Writes `battery` as the profile's save. `writtenByBuildID` is the Build whose game wrote it,
    /// or nil when that isn't known.
    @discardableResult
    public func replacePersistentSaveData(_ battery: Data, profileID: UUID, writtenByBuildID: UUID?) throws -> SaveProfile {
        guard !battery.isEmpty else {
            guard let profile = try profiles.fetchSaveProfile(id: profileID) else {
                throw PersistentSaveServiceError.profileNotFound(profileID)
            }
            return profile
        }
        guard var profile = try profiles.fetchSaveProfile(id: profileID) else {
            throw PersistentSaveServiceError.profileNotFound(profileID)
        }

        let destination = assetStore.persistentSaveURL(profileID: profileID)
        let previousData = assetStore.fileExists(at: destination) ? try? assetStore.readData(at: destination) : nil
        let oldAssetID = profile.persistentSaveAssetID
        let oldAsset = try oldAssetID.flatMap { try assets.fetchAsset(id: $0) }

        try assetStore.beginPendingSaveWrite(
            PendingSaveWrite(sha256: assetStore.hashData(battery), writtenByBuildID: writtenByBuildID),
            for: destination
        )
        do {
            try assetStore.writeDataAtomically(battery, to: destination)
        } catch {
            assetStore.endPendingSaveWrite(for: destination)
            throw error
        }

        var insertedAssetID: UUID?
        do {
            let hash = try assetStore.hashFile(at: destination)
            let relativePath = try assetStore.managedRelativePath(for: destination)
            let timestamp = now()
            let asset = ManagedAsset(
                id: oldAssetID ?? UUID(),
                kind: .persistentSave,
                storageClass: .userData,
                contentSHA256: hash,
                byteLength: Int64(battery.count),
                relativePath: relativePath,
                originalFilename: oldAsset?.originalFilename,
                provenanceJSON: oldAsset?.provenanceJSON,
                integrityStatus: .verified,
                createdAt: oldAsset?.createdAt ?? timestamp
            )

            if oldAssetID == nil {
                try assets.insertAsset(asset)
                insertedAssetID = asset.id
            } else {
                try assets.updateMutableAsset(asset)
            }

            profile.persistentSaveAssetID = asset.id
            profile.saveWrittenByBuildID = writtenByBuildID
            profile.modifiedAt = timestamp
            try profiles.updateSaveProfile(profile)
            assetStore.endPendingSaveWrite(for: destination)
            return profile
        } catch {
            if let previousData {
                try? assetStore.writeDataAtomically(previousData, to: destination)
            } else {
                try? assetStore.removeIfExists(destination)
            }
            if let insertedAssetID {
                try? assets.deleteAsset(id: insertedAssetID)
            } else if let oldAsset {
                try? assets.updateMutableAsset(oldAsset)
            }
            assetStore.endPendingSaveWrite(for: destination)
            throw error
        }
    }

    public func loadPersistentSave(for profile: SaveProfile) throws -> Data? {
        guard let assetID = profile.persistentSaveAssetID else {
            return try finishInterruptedFirstWrite(for: profile)
        }
        guard var asset = try assets.fetchAsset(id: assetID) else {
            throw PersistentSaveServiceError.assetNotFound(assetID)
        }
        let url = try assetStore.managedURL(relativePath: asset.relativePath)
        let data = try assetStore.readData(at: url)
        let actual = assetStore.hashData(data)
        if actual != asset.contentSHA256, let write = assetStore.pendingSaveWrite(for: url, matching: actual) {
            // The app stopped after writing the file and before recording it. The file is the save
            // it meant to write, so recording it now finishes that write.
            try assets.updateMutableAsset(ManagedAsset(
                id: asset.id,
                kind: asset.kind,
                storageClass: asset.storageClass,
                contentSHA256: actual,
                byteLength: Int64(data.count),
                relativePath: asset.relativePath,
                originalFilename: asset.originalFilename,
                provenanceJSON: asset.provenanceJSON,
                integrityStatus: .verified,
                createdAt: asset.createdAt
            ))
            try recordFinishedWrite(write, profile: profile, assetID: asset.id)
            assetStore.endPendingSaveWrite(for: url)
            return data
        }
        guard actual == asset.contentSHA256 else {
            if asset.integrityStatus != .corrupt {
                asset.integrityStatus = .corrupt
                try? assets.updateMutableAsset(asset)
            }
            throw PersistentSaveServiceError.hashMismatch(assetID: asset.id, expected: asset.contentSHA256, actual: actual)
        }
        return data
    }

    /// A profile's first save: the app stopped after writing the file and before the database
    /// learned about it, so the profile still has no save. The file is adopted only when it's the
    /// one that write meant to leave; otherwise the profile keeps having no save, as before.
    private func finishInterruptedFirstWrite(for profile: SaveProfile) throws -> Data? {
        let url = assetStore.persistentSaveURL(profileID: profile.id)
        guard assetStore.fileExists(at: url) else { return nil }
        let data = try assetStore.readData(at: url)
        let hash = assetStore.hashData(data)
        guard let write = assetStore.pendingSaveWrite(for: url, matching: hash) else { return nil }
        let relativePath = try assetStore.managedRelativePath(for: url)
        // The app may also have stopped after recording the file and before giving it to the
        // profile. Paths are unique, so that record is the one to keep.
        let existing = try assets.fetchAsset(relativePath: relativePath)
        let asset = ManagedAsset(
            id: existing?.id ?? UUID(),
            kind: .persistentSave,
            storageClass: .userData,
            contentSHA256: hash,
            byteLength: Int64(data.count),
            relativePath: relativePath,
            originalFilename: existing?.originalFilename,
            provenanceJSON: existing?.provenanceJSON,
            integrityStatus: .verified,
            createdAt: existing?.createdAt ?? now()
        )
        if existing == nil {
            try assets.insertAsset(asset)
        } else {
            try assets.updateMutableAsset(asset)
        }
        do {
            try recordFinishedWrite(write, profile: profile, assetID: asset.id)
        } catch {
            if existing == nil { try? assets.deleteAsset(id: asset.id) }
            throw error
        }
        assetStore.endPendingSaveWrite(for: url)
        return data
    }

    /// What `replacePersistentSaveData` records on the profile once its file is written.
    private func recordFinishedWrite(_ write: PendingSaveWrite, profile: SaveProfile, assetID: UUID) throws {
        guard var current = try profiles.fetchSaveProfile(id: profile.id) else {
            throw PersistentSaveServiceError.profileNotFound(profile.id)
        }
        current.persistentSaveAssetID = assetID
        current.saveWrittenByBuildID = write.writtenByBuildID
        current.modifiedAt = now()
        try profiles.updateSaveProfile(current)
    }
}

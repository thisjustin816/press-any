import EmulatorApplication
import EmulatorDomain
import EmulationCore
import Foundation

public enum PersistentSaveServiceError: Error, Equatable {
    case profileNotFound(UUID)
    case assetNotFound(UUID)
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
    public func flush(worker: SessionWorker, profileID: UUID) throws -> SaveProfile {
        guard let profile = try profiles.fetchSaveProfile(id: profileID) else {
            throw PersistentSaveServiceError.profileNotFound(profileID)
        }

        let battery = try worker.perform { try $0.persistentSaveData() }
        guard !battery.isEmpty else { return profile }
        return try replacePersistentSaveData(battery, profileID: profileID)
    }

    @discardableResult
    public func replacePersistentSaveData(_ battery: Data, profileID: UUID) throws -> SaveProfile {
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

        try assetStore.writeDataAtomically(battery, to: destination)

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
            profile.modifiedAt = timestamp
            try profiles.updateSaveProfile(profile)
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
            throw error
        }
    }

    public func loadPersistentSave(for profile: SaveProfile) throws -> Data? {
        guard let assetID = profile.persistentSaveAssetID else { return nil }
        guard let asset = try assets.fetchAsset(id: assetID) else {
            throw PersistentSaveServiceError.assetNotFound(assetID)
        }
        let url = try assetStore.managedURL(relativePath: asset.relativePath)
        return try assetStore.readData(at: url)
    }
}

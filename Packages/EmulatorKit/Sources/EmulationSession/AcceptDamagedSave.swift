import EmulatorApplication
import EmulatorDomain
import Foundation

public enum AcceptDamagedSaveError: Error, Equatable {
    case profileNotFound(UUID)
    case noSave(UUID)
    case assetNotFound(UUID)
}

/// Plays a Save Profile whose save file no longer matches what was recorded when it was written.
/// That happens when the file is damaged, or when the app closed between writing the file and
/// recording it. The file is first copied to "<name> before playing", so the bytes found stay
/// available, then recorded as the profile's save as they are.
public struct AcceptDamagedSave: Sendable {
    private let profiles: any SaveProfileRepository
    private let assets: any ManagedAssetRepository
    private let assetStore: any AssetStore
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID

    public init(
        profiles: any SaveProfileRepository,
        assets: any ManagedAssetRepository,
        assetStore: any AssetStore,
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.profiles = profiles
        self.assets = assets
        self.assetStore = assetStore
        self.now = now
        self.makeID = makeID
    }

    /// Returns the copy kept of the file as found.
    @discardableResult
    public func execute(profileID: UUID) throws -> SaveProfile {
        guard let profile = try profiles.fetchSaveProfile(id: profileID) else {
            throw AcceptDamagedSaveError.profileNotFound(profileID)
        }
        guard let assetID = profile.persistentSaveAssetID else { throw AcceptDamagedSaveError.noSave(profileID) }
        guard let asset = try assets.fetchAsset(id: assetID) else { throw AcceptDamagedSaveError.assetNotFound(assetID) }

        let copy = try DuplicateSaveProfile(
            profiles: profiles,
            assets: assets,
            assetStore: assetStore,
            now: now,
            makeID: makeID
        ).execute(sourceProfileID: profileID, name: "\(profile.displayName) before playing")
        do {
            let data = try assetStore.readData(at: try assetStore.managedURL(relativePath: asset.relativePath))
            try assets.updateMutableAsset(ManagedAsset(
                id: asset.id,
                kind: asset.kind,
                storageClass: asset.storageClass,
                contentSHA256: assetStore.hashData(data),
                byteLength: Int64(data.count),
                relativePath: asset.relativePath,
                originalFilename: asset.originalFilename,
                provenanceJSON: asset.provenanceJSON,
                integrityStatus: .verified,
                createdAt: asset.createdAt
            ))
        } catch {
            // The profile still refuses to load, so the copy isn't needed.
            profiles.discardNewProfile(copy, assets: assets, files: assetStore)
            throw error
        }
        return copy
    }
}

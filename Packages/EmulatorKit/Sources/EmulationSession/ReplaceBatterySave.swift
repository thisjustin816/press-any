import EmulatorApplication
import EmulatorDomain
import Foundation

public enum ReplaceBatterySaveError: Error, Equatable {
    case profileNotFound(UUID)
    case emptyFile
}

public struct BatterySaveReplacement: Equatable, Sendable {
    public let profile: SaveProfile
    /// The profile's previous save, kept as its own profile. Nil when there was none to lose.
    public let safetyCopy: SaveProfile?
}

/// Imports a `.sav` file into an existing Save Profile. A save already there is first copied to
/// "<name> before import", so the replacement can be undone by playing the copy.
public struct ReplaceBatterySave: Sendable {
    private let profiles: any SaveProfileRepository
    private let assets: any ManagedAssetRepository
    private let assetStore: any AssetStore
    private let persistentSaves: PersistentSaveService
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
        self.persistentSaves = PersistentSaveService(profiles: profiles, assets: assets, assetStore: assetStore, now: now)
        self.now = now
        self.makeID = makeID
    }

    public func execute(profileID: UUID, sourceURL: URL) throws -> BatterySaveReplacement {
        guard let profile = try profiles.fetchSaveProfile(id: profileID) else {
            throw ReplaceBatterySaveError.profileNotFound(profileID)
        }
        try ImportSizeLimit.batterySave.check(fileAt: sourceURL)
        let battery = try assetStore.readData(at: sourceURL)
        guard !battery.isEmpty else { throw ReplaceBatterySaveError.emptyFile }

        var safetyCopy: SaveProfile?
        if profile.persistentSaveAssetID != nil {
            safetyCopy = try DuplicateSaveProfile(
                profiles: profiles,
                assets: assets,
                assetStore: assetStore,
                now: now,
                makeID: makeID
            ).execute(sourceProfileID: profileID, name: "\(profile.displayName) before import")
        }
        do {
            // An imported file's writer isn't known, so no Build is recorded as having written it.
            let replaced = try persistentSaves.replacePersistentSaveData(battery, profileID: profileID, writtenByBuildID: nil)
            return BatterySaveReplacement(profile: replaced, safetyCopy: safetyCopy)
        } catch {
            // The profile still has its old save, so the copy isn't needed.
            if let safetyCopy { profiles.discardNewProfile(safetyCopy, assets: assets, files: assetStore) }
            throw error
        }
    }
}

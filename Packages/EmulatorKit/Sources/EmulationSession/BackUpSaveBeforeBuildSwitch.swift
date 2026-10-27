import EmulatorApplication
import EmulatorDomain
import Foundation

/// Before a Build plays a save another Build wrote, keeps that save as "<name> before switching
/// Builds", so the switch can be undone by playing the copy. Each profile keeps one such copy,
/// refreshed on later switches.
public struct BackUpSaveBeforeBuildSwitch: Sendable {
    public static let suffix = " before switching Builds"
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

    /// `battery` is the profile's save as just loaded and verified. Returns the copy, or nil when
    /// the Build that wrote the save is the one about to play, or the save is already kept as it is.
    @discardableResult
    public func execute(profile: SaveProfile, battery: Data, playingBuildID: UUID) throws -> SaveProfile? {
        guard !battery.isEmpty, let writerID = profile.saveWrittenByBuildID, writerID != playingBuildID,
              let assetID = profile.persistentSaveAssetID, let hash = try assets.fetchAsset(id: assetID)?.contentSHA256,
              !isBackup(profile), try !isKept(hash, in: profile.copiedFromProfileID) else { return nil }
        let name = profile.displayName + Self.suffix
        let existing = try profiles.fetchSaveProfiles(gameID: profile.gameID)
            .first { $0.copiedFromProfileID == profile.id && $0.displayName == name }
        guard var existing else {
            return try DuplicateSaveProfile(profiles: profiles, assets: assets, assetStore: assetStore, now: now, makeID: makeID)
                .execute(sourceProfileID: profile.id, name: name)
        }
        guard try !isKept(hash, in: existing.id) else { return existing }
        existing = try persistentSaves.replacePersistentSaveData(battery, profileID: existing.id, writtenByBuildID: writerID)
        existing.rtcContextJSON = profile.rtcContextJSON
        try profiles.updateSaveProfile(existing)
        return existing
    }

    /// A copy this made is played as it is; copying it again would only nest the names.
    private func isBackup(_ profile: SaveProfile) -> Bool {
        profile.copiedFromProfileID != nil && profile.displayName.hasSuffix(Self.suffix)
    }

    /// Whether another profile holds a save with this content, as the source of a fresh Play
    /// with a Copy does.
    private func isKept(_ hash: String, in profileID: UUID?) throws -> Bool {
        guard let profileID, let other = try profiles.fetchSaveProfile(id: profileID),
              let assetID = other.persistentSaveAssetID else { return false }
        return try assets.fetchAsset(id: assetID)?.contentSHA256 == hash
    }
}

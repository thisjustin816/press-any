import EmulatorDomain
import Foundation

public enum SaveProfileOperationError: Error, Equatable {
    case gameNotFound(UUID)
    case buildNotFound(UUID)
    case sourceProfileNotFound(UUID)
    case persistentSaveAssetNotFound(UUID)
    case profileDoesNotBelongToGame(profileID: UUID, gameID: UUID)
    case profileNotFound(UUID)
    /// A badge is one emoji, or none.
    case invalidBadge(String)
}

public struct CreateBlankSaveProfile: Sendable {
    private let games: any GameRepository
    private let profiles: any SaveProfileRepository
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID

    public init(
        games: any GameRepository,
        profiles: any SaveProfileRepository,
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.games = games
        self.profiles = profiles
        self.now = now
        self.makeID = makeID
    }

    public func execute(gameID: UUID, name: String) throws -> SaveProfile {
        guard var game = try games.fetchGame(id: gameID) else {
            throw SaveProfileOperationError.gameNotFound(gameID)
        }
        let timestamp = now()
        let profile = SaveProfile(
            id: makeID(),
            gameID: gameID,
            displayName: name,
            createdAt: timestamp,
            modifiedAt: timestamp
        )
        try profiles.insertSaveProfile(profile)
        do {
            if game.preferredSaveProfileID == nil {
                game.preferredSaveProfileID = profile.id
                game.modifiedAt = timestamp
                try games.updateGame(game)
            }
            return profile
        } catch {
            try? profiles.deleteSaveProfile(id: profile.id)
            throw error
        }
    }
}

public struct DuplicateSaveProfile: Sendable {
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

    /// Copies the profile and its save. `gameID` puts the copy in another Game; by default it
    /// stays in the source's.
    public func execute(sourceProfileID: UUID, name: String, gameID: UUID? = nil) throws -> SaveProfile {
        guard let source = try profiles.fetchSaveProfile(id: sourceProfileID) else {
            throw SaveProfileOperationError.sourceProfileNotFound(sourceProfileID)
        }

        let timestamp = now()
        let profileID = makeID()
        var persistentSaveAssetID: UUID?
        var copiedBatteryURL: URL?
        var insertedAssetID: UUID?

        if let sourceAssetID = source.persistentSaveAssetID {
            guard let sourceAsset = try assets.fetchAsset(id: sourceAssetID) else {
                throw SaveProfileOperationError.persistentSaveAssetNotFound(sourceAssetID)
            }
            let sourceURL = try assetStore.managedURL(relativePath: sourceAsset.relativePath)
            let destination = assetStore.persistentSaveURL(profileID: profileID)
            try assetStore.copyFileAtomically(from: sourceURL, to: destination)
            copiedBatteryURL = destination

            let asset = ManagedAsset(
                id: makeID(),
                kind: .persistentSave,
                storageClass: .userData,
                contentSHA256: try assetStore.hashFile(at: destination),
                byteLength: try assetStore.fileByteLength(at: destination),
                relativePath: try assetStore.managedRelativePath(for: destination),
                originalFilename: "battery.sav",
                provenanceJSON: sourceAsset.provenanceJSON,
                integrityStatus: .verified,
                createdAt: timestamp
            )
            do {
                try assets.insertAsset(asset)
                insertedAssetID = asset.id
                persistentSaveAssetID = asset.id
            } catch {
                try? assetStore.removeIfExists(destination)
                throw error
            }
        }

        let duplicate = SaveProfile(
            id: profileID,
            gameID: gameID ?? source.gameID,
            displayName: name,
            badge: source.badge,
            persistentSaveAssetID: persistentSaveAssetID,
            saveWrittenByBuildID: source.saveWrittenByBuildID,
            copiedFromProfileID: source.id,
            rtcContextJSON: source.rtcContextJSON,
            createdAt: timestamp,
            modifiedAt: timestamp
        )
        do {
            try profiles.insertSaveProfile(duplicate)
            return duplicate
        } catch {
            if let insertedAssetID { try? assets.deleteAsset(id: insertedAssetID) }
            if let copiedBatteryURL { try? assetStore.removeIfExists(copiedBatteryURL) }
            throw error
        }
    }
}

public struct ImportBatterySave: Sendable {
    private let games: any GameRepository
    private let profiles: any SaveProfileRepository
    private let assets: any ManagedAssetRepository
    private let assetStore: any AssetStore
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID

    public init(
        games: any GameRepository,
        profiles: any SaveProfileRepository,
        assets: any ManagedAssetRepository,
        assetStore: any AssetStore,
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.games = games
        self.profiles = profiles
        self.assets = assets
        self.assetStore = assetStore
        self.now = now
        self.makeID = makeID
    }

    public func execute(gameID: UUID, sourceURL: URL, name: String) throws -> SaveProfile {
        guard var game = try games.fetchGame(id: gameID) else {
            throw SaveProfileOperationError.gameNotFound(gameID)
        }
        try ImportSizeLimit.batterySave.check(fileAt: sourceURL)
        let timestamp = now()
        let profileID = makeID()
        let destination = assetStore.persistentSaveURL(profileID: profileID)
        try assetStore.copyFileAtomically(from: sourceURL, to: destination)

        let data = try assetStore.readData(at: destination)
        let asset = ManagedAsset(
            id: makeID(),
            kind: .persistentSave,
            storageClass: .userData,
            contentSHA256: try assetStore.hashFile(at: destination),
            byteLength: Int64(data.count),
            relativePath: try assetStore.managedRelativePath(for: destination),
            originalFilename: sourceURL.lastPathComponent,
            integrityStatus: .verified,
            createdAt: timestamp
        )

        var insertedProfileID: UUID?
        do {
            try assets.insertAsset(asset)
            let profile = SaveProfile(
                id: profileID,
                gameID: gameID,
                displayName: name,
                persistentSaveAssetID: asset.id,
                createdAt: timestamp,
                modifiedAt: timestamp
            )
            try profiles.insertSaveProfile(profile)
            insertedProfileID = profile.id
            if game.preferredSaveProfileID == nil {
                game.preferredSaveProfileID = profile.id
                game.modifiedAt = timestamp
                try games.updateGame(game)
            }
            return profile
        } catch {
            if let insertedProfileID { try? profiles.deleteSaveProfile(id: insertedProfileID) }
            try? assets.deleteAsset(id: asset.id)
            try? assetStore.removeIfExists(destination)
            throw error
        }
    }
}

/// Sets or clears a profile's badge, one emoji shown beside its name. The profile's modifiedAt is
/// left alone: it marks battery writes, which decide whether an Auto State is still safe to restore.
public struct SetSaveProfileBadge: Sendable {
    private let profiles: any SaveProfileRepository

    public init(profiles: any SaveProfileRepository) {
        self.profiles = profiles
    }

    @discardableResult
    public func execute(profileID: UUID, badge: String?) throws -> SaveProfile {
        guard var profile = try profiles.fetchSaveProfile(id: profileID) else {
            throw SaveProfileOperationError.profileNotFound(profileID)
        }
        let trimmed = badge?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty, !(trimmed.count == 1 && Self.isEmoji(trimmed.first!)) {
            throw SaveProfileOperationError.invalidBadge(trimmed)
        }
        profile.badge = trimmed.isEmpty ? nil : trimmed
        try profiles.updateSaveProfile(profile)
        return profile
    }

    /// Digits, `#` and `*` are emoji only as keycaps, so a lone scalar counts only when it's
    /// drawn as emoji by default; a sequence (keycap, flag, skin tone, ZWJ) counts by its start.
    static func isEmoji(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        guard let first = scalars.first, first.properties.isEmoji else { return false }
        return first.properties.isEmojiPresentation || scalars.count > 1
    }
}

/// Deletes a Save Profile with its battery save and save states. A Game or Build that played it
/// plays the Game's default instead, which a launch picks again when there's none.
public struct DeleteSaveProfile: Sendable {
    private let games: any GameRepository
    private let builds: any BuildRepository
    private let profiles: any SaveProfileRepository
    private let states: any SaveStateRepository
    private let assets: any ManagedAssetRepository
    private let assetStore: any AssetStore
    private let transactions: any LibraryTransactionRunner
    private let now: @Sendable () -> Date

    public init(
        games: any GameRepository,
        builds: any BuildRepository,
        profiles: any SaveProfileRepository,
        states: any SaveStateRepository,
        assets: any ManagedAssetRepository,
        assetStore: any AssetStore,
        transactions: any LibraryTransactionRunner,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.games = games
        self.builds = builds
        self.profiles = profiles
        self.states = states
        self.assets = assets
        self.assetStore = assetStore
        self.transactions = transactions
        self.now = now
    }

    public func execute(profileID: UUID) throws {
        guard let profile = try profiles.fetchSaveProfile(id: profileID) else {
            throw SaveProfileOperationError.profileNotFound(profileID)
        }
        let profileStates = try states.fetchSaveStates(saveProfileID: profileID)
        let timestamp = now()
        try transactions.run { [games, builds, profiles, states] in
            if var game = try games.fetchGame(id: profile.gameID), game.preferredSaveProfileID == profileID {
                game.preferredSaveProfileID = nil
                game.modifiedAt = timestamp
                try games.updateGame(game)
            }
            for var build in try builds.fetchBuilds(gameID: profile.gameID) where build.preferredSaveProfileID == profileID {
                build.preferredSaveProfileID = nil
                build.modifiedAt = timestamp
                try builds.updateBuildMetadata(build)
            }
            for state in profileStates { try states.deleteSaveState(id: state.id) }
            try profiles.deleteSaveProfile(id: profileID)
        }
        // Nothing refers to these files now, so a failure leaves only orphans for the library check.
        assets.discard(assetID: profile.persistentSaveAssetID, files: assetStore)
        for state in profileStates {
            assets.discard(assetID: state.stateAssetID, files: assetStore)
            assets.discard(assetID: state.screenshotAssetID, files: assetStore)
        }
    }
}

public struct ResolvePreferredSaveProfile: Sendable {
    private let games: any GameRepository
    private let builds: any BuildRepository
    private let profiles: any SaveProfileRepository
    private let createBlank: CreateBlankSaveProfile

    public init(
        games: any GameRepository,
        builds: any BuildRepository,
        profiles: any SaveProfileRepository,
        createBlank: CreateBlankSaveProfile
    ) {
        self.games = games
        self.builds = builds
        self.profiles = profiles
        self.createBlank = createBlank
    }

    public func execute(gameID: UUID, buildID: UUID) throws -> SaveProfile {
        guard let game = try games.fetchGame(id: gameID) else {
            throw SaveProfileOperationError.gameNotFound(gameID)
        }
        guard let build = try builds.fetchBuild(id: buildID), build.gameID == gameID else {
            throw SaveProfileOperationError.buildNotFound(buildID)
        }

        if let profileID = build.preferredSaveProfileID,
           let profile = try profiles.fetchSaveProfile(id: profileID), profile.gameID == gameID {
            return profile
        }
        if let profileID = game.preferredSaveProfileID,
           let profile = try profiles.fetchSaveProfile(id: profileID), profile.gameID == gameID {
            return profile
        }
        if let first = try profiles.fetchSaveProfiles(gameID: gameID).sorted(by: { $0.createdAt < $1.createdAt }).first {
            return first
        }
        return try createBlank.execute(gameID: gameID, name: "Main")
    }
}

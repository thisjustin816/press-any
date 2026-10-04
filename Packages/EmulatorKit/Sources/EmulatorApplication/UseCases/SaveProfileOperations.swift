import EmulatorDomain
import Foundation

public enum SaveProfileOperationError: Error, Equatable {
    case gameNotFound(UUID)
    case buildNotFound(UUID)
    case sourceProfileNotFound(UUID)
    case persistentSaveAssetNotFound(UUID)
    case profileDoesNotBelongToGame(profileID: UUID, gameID: UUID)
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

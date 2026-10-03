import EmulatorDomain
import Foundation

public enum ReorganizationMode: Equatable, Sendable {
    case move
    case copy
}

public enum BuildOperationError: Error, Equatable {
    case buildNotFound(UUID)
    case gameNotFound(UUID)
    case buildBelongsToDifferentGame(buildID: UUID, gameID: UUID)
    case profileNotFound(UUID)
    case profileBelongsToDifferentGame(profileID: UUID, gameID: UUID)
    /// A Game holds one Build per image, so these source Builds can't move in beside the
    /// target's Builds of the same image.
    case duplicateImagesInTarget(buildIDs: [UUID])
}

public struct BuildOperations: Sendable {
    private let games: any GameRepository
    private let builds: any BuildRepository
    private let profiles: any SaveProfileRepository
    private let recipes: any PatchRecipeRepository
    private let assets: any ManagedAssetRepository
    private let assetStore: any AssetStore
    private let transactions: any LibraryTransactionRunner
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID

    public init(
        games: any GameRepository,
        builds: any BuildRepository,
        profiles: any SaveProfileRepository,
        recipes: any PatchRecipeRepository,
        assets: any ManagedAssetRepository,
        assetStore: any AssetStore,
        transactions: any LibraryTransactionRunner = PassthroughTransactionRunner(),
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.games = games
        self.builds = builds
        self.profiles = profiles
        self.recipes = recipes
        self.assets = assets
        self.assetStore = assetStore
        self.transactions = transactions
        self.now = now
        self.makeID = makeID
    }

    public func setPreferredBuild(gameID: UUID, buildID: UUID) throws {
        guard var game = try games.fetchGame(id: gameID) else { throw BuildOperationError.gameNotFound(gameID) }
        guard let build = try builds.fetchBuild(id: buildID) else { throw BuildOperationError.buildNotFound(buildID) }
        guard build.gameID == gameID else {
            throw BuildOperationError.buildBelongsToDifferentGame(buildID: buildID, gameID: gameID)
        }
        game.preferredBuildID = buildID
        game.modifiedAt = now()
        try games.updateGame(game)
    }

    public func setPreferredSaveProfile(buildID: UUID, profileID: UUID?) throws {
        guard var build = try builds.fetchBuild(id: buildID) else { throw BuildOperationError.buildNotFound(buildID) }
        if let profileID {
            guard let profile = try profiles.fetchSaveProfile(id: profileID) else {
                throw BuildOperationError.profileNotFound(profileID)
            }
            guard profile.gameID == build.gameID else {
                throw BuildOperationError.profileBelongsToDifferentGame(profileID: profileID, gameID: build.gameID)
            }
        }
        build.preferredSaveProfileID = profileID
        build.modifiedAt = now()
        try builds.updateBuildMetadata(build)
    }

    public func promoteBuild(
        buildID: UUID,
        title: String,
        mode: ReorganizationMode
    ) throws -> Game {
        guard let sourceBuild = try builds.fetchBuild(id: buildID) else {
            throw BuildOperationError.buildNotFound(buildID)
        }
        let timestamp = now()
        return try transactions.run { [games, builds, profiles, sourceBuild, makeID] in
            let newGame = Game(
                id: makeID(),
                primaryTitle: title,
                systemFamily: "gameboy",
                createdAt: timestamp,
                modifiedAt: timestamp
            )
            try games.insertGame(newGame)

            let promoted: Build
            switch mode {
            case .move:
                try builds.moveBuild(id: sourceBuild.id, toGameID: newGame.id)
                guard let moved = try builds.fetchBuild(id: sourceBuild.id) else {
                    throw BuildOperationError.buildNotFound(sourceBuild.id)
                }
                promoted = moved
            case .copy:
                promoted = try copy(sourceBuild, to: newGame.id, timestamp: timestamp)
            }

            var updatedNewGame = newGame
            updatedNewGame.preferredBuildID = promoted.id
            try games.updateGame(updatedNewGame)

            if mode == .move, var oldGame = try games.fetchGame(id: sourceBuild.gameID) {
                let remaining = try builds.fetchBuilds(gameID: oldGame.id).sorted(by: Self.preferredBuildSort)
                if remaining.isEmpty {
                    // The emptied Game is deleted, which would cascade to its Save Profiles, so
                    // they follow the Build. As in a merge, modifiedAt stays put.
                    for profile in try profiles.fetchSaveProfiles(gameID: oldGame.id) {
                        var moved = profile
                        moved.gameID = updatedNewGame.id
                        try profiles.updateSaveProfile(moved)
                    }
                    // The Build carries the Game's identity on, so its artwork goes too.
                    updatedNewGame.preferredSaveProfileID = oldGame.preferredSaveProfileID
                    updatedNewGame.artworkAssetID = oldGame.artworkAssetID
                    try games.updateGame(updatedNewGame)
                    try games.deleteGame(id: oldGame.id)
                } else if oldGame.preferredBuildID == sourceBuild.id {
                    oldGame.preferredBuildID = remaining.first?.id
                    oldGame.modifiedAt = timestamp
                    try games.updateGame(oldGame)
                }
            }
            return updatedNewGame
        }
    }

    public func mergeGame(sourceGameID: UUID, into targetGameID: UUID, mode: ReorganizationMode) throws {
        guard sourceGameID != targetGameID else { return }
        guard let sourceGame = try games.fetchGame(id: sourceGameID) else { throw BuildOperationError.gameNotFound(sourceGameID) }
        guard let targetGame = try games.fetchGame(id: targetGameID) else { throw BuildOperationError.gameNotFound(targetGameID) }
        let targetBuildsByImage = Dictionary(
            try builds.fetchBuilds(gameID: targetGameID).map { ($0.imageSHA256, $0.id) },
            uniquingKeysWith: { first, _ in first }
        )
        let targetImages = Set(targetBuildsByImage.keys)
        let candidates = try builds.fetchBuilds(gameID: sourceGame.id).sorted(by: Self.preferredBuildSort)
        let duplicates = candidates.filter { targetImages.contains($0.imageSHA256) }
        // Moving a duplicate would mean dropping the source Build and the save states made with
        // it. A copy can skip it: the target has the image and the source keeps its Build.
        if mode == .move, !duplicates.isEmpty {
            throw BuildOperationError.duplicateImagesInTarget(buildIDs: duplicates.map(\.id))
        }
        let sourceBuilds = candidates.filter { !targetImages.contains($0.imageSHA256) }
        // A copy's parent and recipe base point at the Build standing in for the original in the
        // target: its copy, or the target's own Build of a skipped duplicate image.
        var replacements: [UUID: UUID] = [:]
        if mode == .copy {
            for duplicate in duplicates { replacements[duplicate.id] = targetBuildsByImage[duplicate.imageSHA256] }
            for source in sourceBuilds { replacements[source.id] = makeID() }
        }
        // Deleting the source Game cascades to its Save Profiles and their states, so a move
        // takes the profiles along. modifiedAt stays put: the battery saves are unchanged, and
        // it decides whether an Auto State is still safe to restore.
        let sourceProfiles = mode == .move ? try profiles.fetchSaveProfiles(gameID: sourceGame.id) : []
        let timestamp = now()

        try transactions.run { [games, builds, profiles, targetGame, replacements] in
            var updatedTargetGame = targetGame
            var firstMergedBuildID: UUID?
            for source in sourceBuilds {
                switch mode {
                case .move:
                    try builds.moveBuild(id: source.id, toGameID: targetGameID)
                    if firstMergedBuildID == nil { firstMergedBuildID = source.id }
                case .copy:
                    let copied = try copy(source, to: targetGameID, timestamp: timestamp, replacing: replacements)
                    if firstMergedBuildID == nil { firstMergedBuildID = copied.id }
                }
            }
            for profile in sourceProfiles {
                var moved = profile
                moved.gameID = targetGameID
                try profiles.updateSaveProfile(moved)
            }
            var targetChanged = false
            if updatedTargetGame.preferredBuildID == nil {
                updatedTargetGame.preferredBuildID = firstMergedBuildID
                targetChanged = true
            }
            if mode == .move, updatedTargetGame.preferredSaveProfileID == nil,
               let preferredProfile = sourceGame.preferredSaveProfileID {
                updatedTargetGame.preferredSaveProfileID = preferredProfile
                targetChanged = true
            }
            // The source Game's row goes away, so its artwork follows unless the target has its own.
            if mode == .move, updatedTargetGame.artworkAssetID == nil, let artwork = sourceGame.artworkAssetID {
                updatedTargetGame.artworkAssetID = artwork
                targetChanged = true
            }
            if targetChanged {
                updatedTargetGame.modifiedAt = timestamp
                try games.updateGame(updatedTargetGame)
            }
            if mode == .move {
                try games.deleteGame(id: sourceGameID)
            }
        }

        // The target kept its own artwork, so the deleted source Game's image has no owner left.
        if mode == .move, let orphan = sourceGame.artworkAssetID, targetGame.artworkAssetID != nil,
           let asset = try? assets.fetchAsset(id: orphan) {
            try? assets.deleteAsset(id: asset.id)
            if let url = try? assetStore.managedURL(relativePath: asset.relativePath) {
                try? assetStore.removeIfExists(url)
            }
        }
    }

    /// Inserts a copy of `source` in `gameID`. A patch-derived copy gets its own recipe, so
    /// evicting the shared cached image can't strand it. `replacing` maps Build IDs to the Builds
    /// that stand in for them in the target, including `source`'s own copy ID; a base that isn't
    /// mapped stays in its original Game, which then can't be deleted while the copy needs it.
    private func copy(
        _ source: Build,
        to gameID: UUID,
        timestamp: Date,
        replacing replacements: [UUID: UUID] = [:]
    ) throws -> Build {
        let copied = Self.copyBuild(
            source,
            id: replacements[source.id] ?? makeID(),
            gameID: gameID,
            parentBuildID: source.parentBuildID.map { replacements[$0] ?? $0 },
            timestamp: timestamp
        )
        try builds.insertBuild(copied)
        if source.sourceKind == .patchRecipe, let recipe = try recipes.fetchPatchRecipe(resultBuildID: source.id) {
            try recipes.insertPatchRecipe(PatchRecipe(
                id: makeID(),
                resultBuildID: copied.id,
                baseBuildID: replacements[recipe.baseBuildID] ?? recipe.baseBuildID,
                expectedResultSHA256: recipe.expectedResultSHA256,
                items: recipe.items,
                createdAt: timestamp
            ))
        }
        return copied
    }

    private static func copyBuild(
        _ source: Build,
        id: UUID,
        gameID: UUID,
        parentBuildID: UUID?,
        timestamp: Date
    ) -> Build {
        Build(
            id: id,
            gameID: gameID,
            system: source.system,
            displayName: source.displayName,
            imageAssetID: source.imageAssetID,
            imageSHA256: source.imageSHA256,
            sourceKind: source.sourceKind,
            parentBuildID: parentBuildID,
            isBase: source.isBase,
            region: source.region,
            language: source.language,
            revision: source.revision,
            versionString: source.versionString,
            versionSortKey: source.versionSortKey,
            preferredSaveProfileID: nil,
            corePin: source.corePin,
            createdAt: timestamp,
            modifiedAt: timestamp
        )
    }

    private static func preferredBuildSort(_ lhs: Build, _ rhs: Build) -> Bool {
        if lhs.isBase != rhs.isBase { return lhs.isBase && !rhs.isBase }
        return lhs.createdAt < rhs.createdAt
    }
}

import EmulatorDomain
import Foundation

public enum ReorganizationMode: Equatable, Sendable {
    case move
    case copy
}

/// The Game-level things a promote or merge brings along, chosen in its review step. Build-scoped
/// data (save states, recipes, toolchain reports, variable maps, settings) always follows its
/// Build.
public struct GameCarryOver: Equatable, Sendable {
    /// Bring the source Game's artwork. A merge that moves everything brings it anyway when the
    /// target has none.
    public var artwork: Bool
    /// Save Profiles copied into the new or target Game. A merge that moves everything moves
    /// every profile instead.
    public var saveProfileIDs: Set<UUID>

    public init(artwork: Bool, saveProfileIDs: Set<UUID>) {
        self.artwork = artwork
        self.saveProfileIDs = saveProfileIDs
    }

    public static let nothing = GameCarryOver(artwork: false, saveProfileIDs: [])
}

public enum BuildOperationError: Error, Equatable {
    case buildNotFound(UUID)
    case invalidBuildName
    case gameNotFound(UUID)
    case buildBelongsToDifferentGame(buildID: UUID, gameID: UUID)
    case profileNotFound(UUID)
    case profileBelongsToDifferentGame(profileID: UUID, gameID: UUID)
    /// A Game holds one Build per image, so these source Builds can't move in beside the
    /// target's Builds of the same image.
    case duplicateImagesInTarget(buildIDs: [UUID])
    /// Only an imported image can be a Base Build; a patched Build is made from one.
    case patchedBuildCannotBeBase(UUID)
}

public struct BuildOperations: Sendable {
    private let games: any GameRepository
    private let builds: any BuildRepository
    private let profiles: any SaveProfileRepository
    private let states: any SaveStateRepository
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
        states: any SaveStateRepository,
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
        self.states = states
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

    public func renameBuild(buildID: UUID, displayName: String) throws {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw BuildOperationError.invalidBuildName }
        guard var build = try builds.fetchBuild(id: buildID) else {
            throw BuildOperationError.buildNotFound(buildID)
        }
        guard build.displayName != name else { return }
        build.displayName = name
        build.modifiedAt = now()
        try builds.updateBuildMetadata(build)
    }

    /// Marks or unmarks an imported Build as the clean original that patches start from. Marking
    /// one automatically replaces the Game's previous Base Build.
    public func setBase(buildID: UUID, isBase: Bool) throws {
        guard let build = try builds.fetchBuild(id: buildID) else { throw BuildOperationError.buildNotFound(buildID) }
        if isBase, build.sourceKind == .patchRecipe { throw BuildOperationError.patchedBuildCannotBeBase(buildID) }
        let timestamp = now()
        try transactions.run { [builds] in
            var updatedBuild = build
            if isBase {
                try builds.demoteOtherBaseBuilds(
                    gameID: updatedBuild.gameID,
                    keeping: updatedBuild.id,
                    modifiedAt: timestamp
                )
            }
            guard updatedBuild.isBase != isBase else { return }
            updatedBuild.isBase = isBase
            updatedBuild.modifiedAt = timestamp
            try builds.updateBuildMetadata(updatedBuild)
        }
    }

    /// What a promotion's review step selects at first: the Game's artwork, and the Save Profiles
    /// the Build plays or last wrote.
    public func suggestedCarryOver(promoting buildID: UUID) throws -> GameCarryOver {
        guard let build = try builds.fetchBuild(id: buildID) else { throw BuildOperationError.buildNotFound(buildID) }
        let game = try games.fetchGame(id: build.gameID)
        let profileIDs = try profiles.fetchSaveProfiles(gameID: build.gameID)
            .filter { $0.id == build.preferredSaveProfileID || $0.saveWrittenByBuildID == build.id }
            .map(\.id)
        return GameCarryOver(artwork: game?.artworkAssetID != nil, saveProfileIDs: Set(profileIDs))
    }

    /// What a merge's review step selects at first. A move takes every profile, and the source's
    /// artwork when the target has none. A copy selects the same artwork, and the profiles the
    /// source Builds play or last wrote, plus the source Game's default.
    public func suggestedCarryOver(merging sourceGameID: UUID, into targetGameID: UUID) throws -> GameCarryOver {
        guard let source = try games.fetchGame(id: sourceGameID) else { throw BuildOperationError.gameNotFound(sourceGameID) }
        guard let target = try games.fetchGame(id: targetGameID) else { throw BuildOperationError.gameNotFound(targetGameID) }
        let sourceBuilds = try builds.fetchBuilds(gameID: sourceGameID)
        let played = Set(sourceBuilds.compactMap(\.preferredSaveProfileID))
        let written = Set(sourceBuilds.map(\.id))
        let profileIDs = try profiles.fetchSaveProfiles(gameID: sourceGameID)
            .filter { played.contains($0.id) || $0.id == source.preferredSaveProfileID || $0.saveWrittenByBuildID.map(written.contains) == true }
            .map(\.id)
        return GameCarryOver(
            artwork: source.artworkAssetID != nil && target.artworkAssetID == nil,
            saveProfileIDs: Set(profileIDs)
        )
    }

    public func promoteBuild(
        buildID: UUID,
        title: String,
        mode: ReorganizationMode,
        carryOver: GameCarryOver = .nothing
    ) throws -> Game {
        guard let sourceBuild = try builds.fetchBuild(id: buildID) else {
            throw BuildOperationError.buildNotFound(buildID)
        }
        let sourceGame = try games.fetchGame(id: sourceBuild.gameID)
        let timestamp = now()
        let promotedGame = try transactions.run { [games, builds, profiles, states, sourceBuild, makeID] in
            let newGame = Game(
                id: makeID(),
                primaryTitle: title,
                systemFamily: "gameboy",
                lineage: sourceGame.map { GameLineage(sourceGameID: $0.id, sourceTitle: $0.primaryTitle) },
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

            // The source's Builds after a move, best first; a copy leaves the source as it was.
            let remaining = try mode == .move
                ? builds.fetchBuilds(gameID: sourceBuild.gameID).sorted(by: Self.preferredBuildSort)
                : nil
            if remaining?.isEmpty != true {
                let copies = try copyProfiles(
                    carryOver.saveProfileIDs,
                    from: sourceBuild.gameID,
                    to: &updatedNewGame,
                    playedBy: [promoted.id: sourceBuild.preferredSaveProfileID]
                )
                // The moved Build plays the copies, so its states go with them. Left on the
                // originals, Load State wouldn't list them and deleting an original would delete
                // them. A copy holds the original's save unchanged, so it keeps the original's
                // modifiedAt, which decides whether an Auto State is still safe to restore.
                if mode == .move {
                    for (originalID, copyID) in copies {
                        try states.reassignSaveStates(buildID: promoted.id, fromSaveProfileID: originalID, toSaveProfileID: copyID)
                        if let original = try profiles.fetchSaveProfile(id: originalID),
                           var copy = try profiles.fetchSaveProfile(id: copyID) {
                            copy.modifiedAt = original.modifiedAt
                            try profiles.updateSaveProfile(copy)
                        }
                    }
                }
            }

            if let remaining, var oldGame = try games.fetchGame(id: sourceBuild.gameID) {
                if remaining.isEmpty {
                    // Promoting a Game's only Build renames it rather than splitting it.
                    updatedNewGame.lineage = nil
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
        if carryOver.artwork, promotedGame.artworkAssetID == nil, let artwork = sourceGame?.artworkAssetID {
            return try copyArtwork(artwork, to: promotedGame.id) ?? promotedGame
        }
        return promotedGame
    }

    public func mergeGame(
        sourceGameID: UUID,
        into targetGameID: UUID,
        mode: ReorganizationMode,
        carryOver: GameCarryOver = .nothing
    ) throws {
        guard sourceGameID != targetGameID else { return }
        guard let sourceGame = try games.fetchGame(id: sourceGameID) else { throw BuildOperationError.gameNotFound(sourceGameID) }
        guard let targetGame = try games.fetchGame(id: targetGameID) else { throw BuildOperationError.gameNotFound(targetGameID) }
        let targetBuilds = try builds.fetchBuilds(gameID: targetGameID)
        let targetBuildsByImage = Dictionary(
            targetBuilds.map { ($0.imageSHA256, $0.id) },
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

        // A move's source artwork replaces the target's only when the review asked for it.
        let replacesArtwork = mode == .move && carryOver.artwork && sourceGame.artworkAssetID != nil
        try transactions.run { [games, builds, profiles, targetGame, replacements] in
            var updatedTargetGame = targetGame
            var firstMergedBuildID: UUID?
            var played: [UUID: UUID?] = [:]
            var targetHasBase = targetBuilds.contains { $0.isBase }
            for source in sourceBuilds {
                var merged = source
                if merged.isBase {
                    merged.isBase = !targetHasBase
                    targetHasBase = true
                }
                switch mode {
                case .move:
                    if merged.isBase != source.isBase {
                        merged.modifiedAt = timestamp
                        try builds.updateBuildMetadata(merged)
                    }
                    try builds.moveBuild(id: source.id, toGameID: targetGameID)
                    if firstMergedBuildID == nil { firstMergedBuildID = source.id }
                case .copy:
                    let copied = try copy(merged, to: targetGameID, timestamp: timestamp, replacing: replacements)
                    played[copied.id] = source.preferredSaveProfileID
                    if firstMergedBuildID == nil { firstMergedBuildID = copied.id }
                }
            }
            for profile in sourceProfiles {
                var moved = profile
                moved.gameID = targetGameID
                try profiles.updateSaveProfile(moved)
            }
            var targetChanged = false
            if mode == .copy {
                // copyProfiles saves the target's new default itself.
                try copyProfiles(carryOver.saveProfileIDs, from: sourceGameID, to: &updatedTargetGame, playedBy: played)
            }
            if updatedTargetGame.preferredBuildID == nil {
                updatedTargetGame.preferredBuildID = firstMergedBuildID
                targetChanged = true
            }
            if mode == .move, updatedTargetGame.preferredSaveProfileID == nil,
               let preferredProfile = sourceGame.preferredSaveProfileID {
                updatedTargetGame.preferredSaveProfileID = preferredProfile
                targetChanged = true
            }
            // The source Game's row goes away, so its artwork follows unless the target keeps its own.
            if mode == .move, updatedTargetGame.artworkAssetID == nil || replacesArtwork,
               let artwork = sourceGame.artworkAssetID {
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

        // Whichever artwork lost has no owner left.
        if mode == .move, sourceGame.artworkAssetID != nil, let kept = targetGame.artworkAssetID {
            assets.discard(assetID: replacesArtwork ? kept : sourceGame.artworkAssetID, files: assetStore)
        }
        if mode == .copy, carryOver.artwork, targetGame.artworkAssetID == nil, let artwork = sourceGame.artworkAssetID {
            _ = try copyArtwork(artwork, to: targetGameID)
        }
    }

    /// Copies the chosen profiles of `sourceGameID` into `target` under their own names.
    /// `playedBy` maps each Build now in the target to the profile its original played, so it
    /// plays that profile's copy, or no profile when that one stayed behind. The target's default
    /// becomes the copy of the source's default, or the first copy, when it has none. Returns
    /// each copied profile's ID mapped to its copy's.
    @discardableResult
    private func copyProfiles(
        _ profileIDs: Set<UUID>,
        from sourceGameID: UUID,
        to target: inout Game,
        playedBy: [UUID: UUID?]
    ) throws -> [UUID: UUID] {
        let duplicate = DuplicateSaveProfile(profiles: profiles, assets: assets, assetStore: assetStore, now: now, makeID: makeID)
        var copies: [UUID: UUID] = [:]
        var firstCopy: UUID?
        for profile in try profiles.fetchSaveProfiles(gameID: sourceGameID).sorted(by: { $0.createdAt < $1.createdAt })
        where profileIDs.contains(profile.id) {
            let copy = try duplicate.execute(sourceProfileID: profile.id, name: profile.displayName, gameID: target.id)
            copies[profile.id] = copy.id
            if firstCopy == nil { firstCopy = copy.id }
        }
        for (buildID, original) in playedBy {
            guard var build = try builds.fetchBuild(id: buildID) else { continue }
            let preferred = original.flatMap { copies[$0] }
            guard build.preferredSaveProfileID != preferred else { continue }
            build.preferredSaveProfileID = preferred
            try builds.updateBuildMetadata(build)
        }
        let sourceDefault = try games.fetchGame(id: sourceGameID)?.preferredSaveProfileID
        if target.preferredSaveProfileID == nil, let copy = sourceDefault.flatMap({ copies[$0] }) ?? firstCopy {
            target.preferredSaveProfileID = copy
            try games.updateGame(target)
        }
        return copies
    }

    /// Copies an artwork image into another Game as that Game's own asset, so replacing or
    /// removing either Game's artwork leaves the other's alone.
    private func copyArtwork(_ assetID: UUID, to gameID: UUID) throws -> Game? {
        guard let asset = try assets.fetchAsset(id: assetID) else { return nil }
        let data = try assetStore.readData(at: try assetStore.managedURL(relativePath: asset.relativePath))
        return try GameArtwork(games: games, assets: assets, assetStore: assetStore, now: now, makeID: makeID).store(
            gameID: gameID,
            imageData: data,
            fileExtension: URL(fileURLWithPath: asset.relativePath).pathExtension,
            originalFilename: asset.originalFilename
        )
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
            baseTitle: source.baseTitle,
            hackTitle: source.hackTitle,
            author: source.author,
            translation: source.translation,
            status: source.status,
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

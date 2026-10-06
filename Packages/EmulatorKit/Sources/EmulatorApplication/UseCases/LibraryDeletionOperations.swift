import EmulatorDomain
import Foundation

public enum LibraryDeletionError: Error, Equatable {
    case gameNotFound(UUID)
    case buildNotFound(UUID)
    case saveProfileNotFound(UUID)
    case deletionNotFound(UUID)
    /// Patched Builds in other Games are rebuilt from Builds in this Game. They name the Builds.
    case dependentBuildsInOtherGames([UUID])
    /// The deletion's Game is itself in Recently Deleted; restore that first.
    case gameIsDeleted(UUID)
    /// A patched Build can't come back while the Build it's rebuilt from is deleted.
    case baseBuildIsDeleted(UUID)
    /// The same ROM was imported into the Game again since this Build was deleted. Names the
    /// deleted Build.
    case romAlreadyInGame(UUID)
}

/// What a deletion would take, shown before it happens so nothing goes unannounced (`dec 30`).
public struct DeletionPlan: Equatable, Sendable {
    public let kind: LibraryDeletion.Kind
    public let title: String
    public let gameID: UUID
    public let records: LibraryRecordSet
    /// Patched Builds deleted with a Build because they're rebuilt from it.
    public let dependentBuilds: [Build]
    /// Games left with no Builds, which go too.
    public let emptiedGames: [Game]
}

/// Deletes Games, Builds and Save Profiles into Recently Deleted, restores them, and purges them
/// after `LibraryDeletion.retention`.
public struct LibraryDeletionOperations: Sendable {
    private let games: any GameRepository
    private let builds: any BuildRepository
    private let profiles: any SaveProfileRepository
    private let states: any SaveStateRepository
    private let recipes: any PatchRecipeRepository
    private let deletions: any LibraryDeletionRepository
    private let assetStore: any AssetStore
    private let transactions: any LibraryTransactionRunner
    private let makeID: @Sendable () -> UUID
    private let now: @Sendable () -> Date

    public init(
        games: any GameRepository,
        builds: any BuildRepository,
        profiles: any SaveProfileRepository,
        states: any SaveStateRepository,
        recipes: any PatchRecipeRepository,
        deletions: any LibraryDeletionRepository,
        assetStore: any AssetStore,
        transactions: any LibraryTransactionRunner,
        makeID: @escaping @Sendable () -> UUID = UUID.init,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.games = games
        self.builds = builds
        self.profiles = profiles
        self.states = states
        self.recipes = recipes
        self.deletions = deletions
        self.assetStore = assetStore
        self.transactions = transactions
        self.makeID = makeID
        self.now = now
    }

    /// The Game with all its Builds, Save Profiles and states. Refused while a patched Build in
    /// another Game is rebuilt from one of its Builds.
    public func planGameDeletion(gameID: UUID) throws -> DeletionPlan {
        guard let game = try games.fetchGame(id: gameID) else { throw LibraryDeletionError.gameNotFound(gameID) }
        let gameBuilds = try builds.fetchBuilds(gameID: gameID)
        var outside: [UUID] = []
        for build in gameBuilds {
            for recipe in try recipes.fetchPatchRecipes(baseBuildID: build.id) {
                if let result = try builds.fetchBuild(id: recipe.resultBuildID), result.gameID != gameID {
                    outside.append(result.id)
                }
            }
        }
        guard outside.isEmpty else { throw LibraryDeletionError.dependentBuildsInOtherGames(outside) }
        var records = LibraryRecordSet(gameIDs: [gameID], buildIDs: gameBuilds.map(\.id))
        try addProfilesAndStates(ofGame: gameID, to: &records)
        return DeletionPlan(kind: .game, title: game.primaryTitle, gameID: gameID, records: records, dependentBuilds: [], emptiedGames: [])
    }

    /// The Build with its states, every patched Build rebuilt from it, in any Game, and any Game
    /// those leave without Builds.
    public func planBuildDeletion(buildID: UUID) throws -> DeletionPlan {
        guard let build = try builds.fetchBuild(id: buildID) else { throw LibraryDeletionError.buildNotFound(buildID) }
        var deleted = [build]
        var queue = [build.id]
        while let next = queue.popLast() {
            for recipe in try recipes.fetchPatchRecipes(baseBuildID: next) {
                guard let dependent = try builds.fetchBuild(id: recipe.resultBuildID),
                      !deleted.contains(where: { $0.id == dependent.id }) else { continue }
                deleted.append(dependent)
                queue.append(dependent.id)
            }
        }
        let deletedIDs = Set(deleted.map(\.id))
        var records = LibraryRecordSet(buildIDs: deleted.map(\.id))
        var emptied: [Game] = []
        for gameID in Self.unique(deleted.map(\.gameID)) {
            if try builds.fetchBuilds(gameID: gameID).allSatisfy({ deletedIDs.contains($0.id) }),
               let game = try games.fetchGame(id: gameID) {
                emptied.append(game)
                records.gameIDs.append(gameID)
                try addProfilesAndStates(ofGame: gameID, to: &records)
            } else {
                for profile in try profiles.fetchSaveProfiles(gameID: gameID) {
                    records.saveStateIDs += try states.fetchSaveStates(saveProfileID: profile.id)
                        .filter { deletedIDs.contains($0.buildID) }.map(\.id)
                }
            }
        }
        return DeletionPlan(
            kind: .build,
            title: build.displayName,
            gameID: build.gameID,
            records: records,
            dependentBuilds: Array(deleted.dropFirst()),
            emptiedGames: emptied
        )
    }

    /// The Save Profile with its battery save and states.
    public func planProfileDeletion(profileID: UUID) throws -> DeletionPlan {
        guard let profile = try profiles.fetchSaveProfile(id: profileID) else {
            throw LibraryDeletionError.saveProfileNotFound(profileID)
        }
        let records = LibraryRecordSet(
            saveProfileIDs: [profileID],
            saveStateIDs: try states.fetchSaveStates(saveProfileID: profileID).map(\.id)
        )
        return DeletionPlan(kind: .saveProfile, title: profile.displayName, gameID: profile.gameID, records: records, dependentBuilds: [], emptiedGames: [])
    }

    /// Moves the plan's records into Recently Deleted. A Game or Build that preferred a deleted
    /// Build or Save Profile falls back to its default, as when a profile is deleted outright.
    @discardableResult
    public func delete(_ plan: DeletionPlan) throws -> LibraryDeletion {
        let deletion = LibraryDeletion(
            id: makeID(),
            kind: plan.kind,
            title: plan.title,
            gameID: plan.gameID,
            deletedAt: now(),
            records: plan.records
        )
        let deletedBuilds = Set(plan.records.buildIDs)
        let deletedProfiles = Set(plan.records.saveProfileIDs)
        let deletedGames = Set(plan.records.gameIDs)
        let affectedGames = Self.unique([plan.gameID] + plan.dependentBuilds.map(\.gameID)).filter { !deletedGames.contains($0) }
        try transactions.run { [games, builds, deletions] in
            for gameID in affectedGames {
                guard var game = try games.fetchGame(id: gameID) else { continue }
                var changed = false
                if let preferred = game.preferredBuildID, deletedBuilds.contains(preferred) {
                    game.preferredBuildID = nil
                    changed = true
                }
                if let preferred = game.preferredSaveProfileID, deletedProfiles.contains(preferred) {
                    game.preferredSaveProfileID = nil
                    changed = true
                }
                if changed {
                    game.modifiedAt = deletion.deletedAt
                    try games.updateGame(game)
                }
                for var build in try builds.fetchBuilds(gameID: gameID) {
                    guard let preferred = build.preferredSaveProfileID, deletedProfiles.contains(preferred) else { continue }
                    build.preferredSaveProfileID = nil
                    build.modifiedAt = deletion.deletedAt
                    try builds.updateBuildMetadata(build)
                }
            }
            try deletions.insertDeletion(deletion)
        }
        return deletion
    }

    /// Recently Deleted, newest first.
    public func recentlyDeleted() throws -> [LibraryDeletion] {
        try deletions.fetchDeletions()
    }

    /// Brings a deletion back, unless what it belongs to is still deleted.
    public func restore(deletionID: UUID) throws {
        guard let deletion = try deletions.fetchDeletions().first(where: { $0.id == deletionID }) else {
            throw LibraryDeletionError.deletionNotFound(deletionID)
        }
        let restoredGames = Set(deletion.records.gameIDs)
        if !restoredGames.contains(deletion.gameID), try games.fetchGame(id: deletion.gameID) == nil {
            throw LibraryDeletionError.gameIsDeleted(deletion.gameID)
        }
        let restoredBuilds = Set(deletion.records.buildIDs)
        for buildID in deletion.records.buildIDs {
            guard let recipe = try recipes.fetchPatchRecipe(resultBuildID: buildID),
                  !restoredBuilds.contains(recipe.baseBuildID) else { continue }
            if try builds.fetchBuild(id: recipe.baseBuildID) == nil {
                throw LibraryDeletionError.baseBuildIsDeleted(recipe.baseBuildID)
            }
        }
        try deletions.restoreDeletion(id: deletionID)
    }

    /// Delete Now: purges one deletion before its 30 days are up.
    public func purge(deletionID: UUID) throws {
        let released = try deletions.purgeDeletion(id: deletionID, at: now())
        removeFiles(of: released)
    }

    /// Purges every deletion older than the retention period. Returns how many it purged.
    @discardableResult
    public func purgeExpired() throws -> Int {
        let timestamp = now()
        var purged = 0
        for deletion in try deletions.fetchDeletions() where deletion.purgeDate <= timestamp {
            // An earlier purge in this pass may already have taken it as a dependent.
            guard try deletions.fetchDeletions().contains(where: { $0.id == deletion.id }) else { continue }
            removeFiles(of: try deletions.purgeDeletion(id: deletion.id, at: timestamp))
            purged += 1
        }
        return purged
    }

    private func addProfilesAndStates(ofGame gameID: UUID, to records: inout LibraryRecordSet) throws {
        for profile in try profiles.fetchSaveProfiles(gameID: gameID) {
            records.saveProfileIDs.append(profile.id)
            records.saveStateIDs += try states.fetchSaveStates(saveProfileID: profile.id).map(\.id)
        }
    }

    /// The rows are gone, so a file left behind is only an orphan for the library check.
    private func removeFiles(of assets: [ManagedAsset]) {
        for asset in assets {
            guard let url = try? assetStore.managedURL(relativePath: asset.relativePath) else { continue }
            try? assetStore.removeIfExists(url)
        }
    }

    private static func unique(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }
}

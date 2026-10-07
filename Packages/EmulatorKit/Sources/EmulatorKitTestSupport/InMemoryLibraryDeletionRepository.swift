import EmulatorApplication
import EmulatorDomain
import Foundation

/// Recently Deleted for tests. Where the database marks rows hidden, this moves them out of the
/// other in-memory repositories into a stash, so their reads leave them out the same way.
public final class InMemoryLibraryDeletionRepository: LibraryDeletionRepository, @unchecked Sendable {
    private struct Stash {
        var games: [Game] = []
        var builds: [Build] = []
        var profiles: [SaveProfile] = []
        var states: [SaveState] = []
    }

    private let games: InMemoryGameRepository
    private let builds: InMemoryBuildRepository
    private let profiles: InMemorySaveProfileRepository
    private let states: InMemorySaveStateRepository
    private let recipes: InMemoryPatchRecipeRepository
    private let variableMaps: InMemoryBuildVariableMapRepository
    private let assets: InMemoryAssetRepository
    private let lock = NSLock()
    private var deletions: [UUID: LibraryDeletion] = [:]
    private var stashes: [UUID: Stash] = [:]
    private var tombstones: [Tombstone] = []

    public init(
        games: InMemoryGameRepository,
        builds: InMemoryBuildRepository,
        profiles: InMemorySaveProfileRepository,
        states: InMemorySaveStateRepository,
        recipes: InMemoryPatchRecipeRepository,
        variableMaps: InMemoryBuildVariableMapRepository = InMemoryBuildVariableMapRepository(),
        assets: InMemoryAssetRepository
    ) {
        self.games = games
        self.builds = builds
        self.profiles = profiles
        self.states = states
        self.recipes = recipes
        self.variableMaps = variableMaps
        self.assets = assets
    }

    public func insertDeletion(_ deletion: LibraryDeletion) throws {
        let records = deletion.records
        var stash = Stash()
        for id in records.gameIDs {
            if let game = try games.fetchGame(id: id) { stash.games.append(game); games.hideGame(id: id) }
        }
        for id in records.buildIDs {
            if let build = try builds.fetchBuild(id: id) { stash.builds.append(build); builds.removeBuild(id: id) }
        }
        for id in records.saveProfileIDs {
            if let profile = try profiles.fetchSaveProfile(id: id) {
                stash.profiles.append(profile)
                try profiles.deleteSaveProfile(id: id)
            }
        }
        let stateIDs = Set(records.saveStateIDs)
        for state in states.all where stateIDs.contains(state.id) {
            stash.states.append(state)
            try states.deleteSaveState(id: state.id)
        }
        lock.withLock {
            deletions[deletion.id] = deletion
            stashes[deletion.id] = stash
        }
    }

    public func fetchDeletions() throws -> [LibraryDeletion] {
        lock.withLock { deletions.values.sorted { $0.deletedAt > $1.deletedAt } }
    }

    public func restoreDeletion(id: UUID) throws {
        guard let stash = lock.withLock({ stashes[id] }) else { return }
        for build in stash.builds where try builds.fetchBuild(gameID: build.gameID, imageSHA256: build.imageSHA256) != nil {
            throw LibraryDeletionError.romAlreadyInGame(build.id)
        }
        if lock.withLock({ deletions[id]?.kind }) == .saveState {
            for state in stash.states {
                if try profiles.fetchSaveProfile(id: state.saveProfileID) == nil {
                    throw LibraryDeletionError.saveProfileIsDeleted(state.saveProfileID)
                }
                if try builds.fetchBuild(id: state.buildID) == nil {
                    throw LibraryDeletionError.buildIsDeleted(state.buildID)
                }
            }
        }
        lock.withLock { _ = stashes.removeValue(forKey: id) }
        lock.withLock { _ = deletions.removeValue(forKey: id) }
        for game in stash.games { try games.insertGame(game) }
        for var build in stash.builds {
            if build.isBase, try builds.fetchBuilds(gameID: build.gameID).contains(where: \.isBase) {
                build.isBase = false
            }
            try builds.insertBuild(build)
        }
        for profile in stash.profiles { try profiles.insertSaveProfile(profile) }
        for state in stash.states { try states.insertSaveState(state) }
    }

    public func purgeDeletion(id: UUID, at date: Date) throws -> [ManagedAsset] {
        guard let deletion = lock.withLock({ deletions[id] }) else { return [] }
        var purgedDeletions = [deletion]
        // A deleted patched Build elsewhere can't be rebuilt once its base goes, and a save state
        // deleted on its own can't come back once its Save Profile or Build goes, so they go too.
        var purgedBuildIDs = Set(deletion.records.buildIDs)
        var purgedProfileIDs = Set(deletion.records.saveProfileIDs)
        var changed = true
        while changed {
            changed = false
            for other in lock.withLock({ Array(deletions.values) }) where !purgedDeletions.contains(where: { $0.id == other.id }) {
                let dependsOnPurged = try other.records.buildIDs.contains { buildID in
                    guard let recipe = recipes.all.first(where: { $0.resultBuildID == buildID }) else { return false }
                    return purgedBuildIDs.contains(recipe.baseBuildID)
                }
                let orphanedStates = other.kind == .saveState && lock.withLock { stashes[other.id]?.states ?? [] }.contains {
                    purgedProfileIDs.contains($0.saveProfileID) || purgedBuildIDs.contains($0.buildID)
                }
                if dependsOnPurged || orphanedStates {
                    purgedDeletions.append(other)
                    purgedBuildIDs.formUnion(other.records.buildIDs)
                    purgedProfileIDs.formUnion(other.records.saveProfileIDs)
                    changed = true
                }
            }
        }

        var candidates = Set<UUID>()
        for purged in purgedDeletions {
            guard let stash = lock.withLock({ stashes.removeValue(forKey: purged.id) }) else { continue }
            lock.withLock { _ = deletions.removeValue(forKey: purged.id) }
            for game in stash.games {
                games.purgeMetadata(gameID: game.id)
                if let artwork = game.artworkAssetID { candidates.insert(artwork) }
            }
            for build in stash.builds {
                builds.purgeSaveDeclarations(buildID: build.id)
                builds.purgeMetadata(buildID: build.id)
                candidates.insert(build.imageAssetID)
                if let recipe = recipes.all.first(where: { $0.resultBuildID == build.id }) {
                    candidates.formUnion(recipe.items.map(\.patchAssetID))
                    recipes.removeRecipe(resultBuildID: build.id)
                }
                candidates.formUnion(variableMaps.all.filter { $0.buildID == build.id }.map(\.assetID))
                variableMaps.removeMaps(buildID: build.id)
            }
            for profile in stash.profiles { if let save = profile.persistentSaveAssetID { candidates.insert(save) } }
            for state in stash.states {
                candidates.insert(state.stateAssetID)
                if let screenshot = state.screenshotAssetID { candidates.insert(screenshot) }
            }
            lock.withLock {
                tombstones += purged.records.all.map {
                    Tombstone(recordID: $0.id, kind: $0.kind, deletedAt: purged.deletedAt, purgedAt: date)
                }
            }
        }

        // A state of a purged Save Profile or Build can sit in another deletion, deleted with a
        // Build or profile that's still restorable. It goes with what it belongs to, and that
        // deletion keeps the rest.
        for other in lock.withLock({ Array(deletions.values) }) {
            let carried = lock.withLock { stashes[other.id]?.states ?? [] }.filter {
                purgedProfileIDs.contains($0.saveProfileID) || purgedBuildIDs.contains($0.buildID)
            }
            guard !carried.isEmpty else { continue }
            let carriedIDs = Set(carried.map(\.id))
            for state in carried {
                candidates.insert(state.stateAssetID)
                if let screenshot = state.screenshotAssetID { candidates.insert(screenshot) }
            }
            var records = other.records
            records.saveStateIDs.removeAll { carriedIDs.contains($0) }
            lock.withLock {
                stashes[other.id]?.states.removeAll { carriedIDs.contains($0.id) }
                deletions[other.id] = LibraryDeletion(
                    id: other.id, kind: other.kind, title: other.title, gameID: other.gameID,
                    deletedAt: other.deletedAt, records: records
                )
                tombstones += carried.map {
                    Tombstone(recordID: $0.id, kind: .saveState, deletedAt: other.deletedAt, purgedAt: date)
                }
            }
        }

        let referenced = referencedAssetIDs()
        var released: [ManagedAsset] = []
        for assetID in candidates.subtracting(referenced) {
            guard let asset = try assets.fetchAsset(id: assetID) else { continue }
            try assets.deleteAsset(id: assetID)
            released.append(asset)
        }
        return released
    }

    public func fetchTombstones() throws -> [Tombstone] {
        lock.withLock { tombstones }
    }

    /// Assets still used by a live record or by one waiting in Recently Deleted.
    private func referencedAssetIDs() -> Set<UUID> {
        let stashed = lock.withLock { Array(stashes.values) }
        var ids = Set<UUID>()
        for game in games.all + stashed.flatMap(\.games) { if let artwork = game.artworkAssetID { ids.insert(artwork) } }
        for build in builds.all + stashed.flatMap(\.builds) { ids.insert(build.imageAssetID) }
        for profile in profiles.all + stashed.flatMap(\.profiles) {
            if let save = profile.persistentSaveAssetID { ids.insert(save) }
        }
        for state in states.all + stashed.flatMap(\.states) {
            ids.insert(state.stateAssetID)
            if let screenshot = state.screenshotAssetID { ids.insert(screenshot) }
        }
        for recipe in recipes.all { ids.formUnion(recipe.items.map(\.patchAssetID)) }
        for map in variableMaps.all { ids.insert(map.assetID) }
        return ids
    }
}

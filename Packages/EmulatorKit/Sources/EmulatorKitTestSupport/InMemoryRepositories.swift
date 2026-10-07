import EmulatorApplication
import EmulatorDomain
import Foundation

// In-memory implementations of the library ports for tests. Fetches return the order the GRDB
// repositories use, so tests see the same order the app does.

public final class InMemoryGameRepository: GameRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID: Game]

    public init(_ games: [Game] = []) {
        values = Dictionary(uniqueKeysWithValues: games.map { ($0.id, $0) })
    }

    public func fetchGame(id: UUID) throws -> Game? { lock.withLock { values[id] } }

    public func fetchGames() throws -> [Game] {
        lock.withLock {
            values.values.sorted {
                let order = $0.primaryTitle.localizedCaseInsensitiveCompare($1.primaryTitle)
                return order == .orderedSame ? $0.createdAt < $1.createdAt : order == .orderedAscending
            }
        }
    }

    public func insertGame(_ game: Game) throws { lock.withLock { values[game.id] = game } }
    public func updateGame(_ game: Game) throws { lock.withLock { values[game.id] = game } }
    public func deleteGame(id: UUID) throws { _ = lock.withLock { values.removeValue(forKey: id) } }

    var all: [Game] { lock.withLock { Array(values.values) } }
}

public final class InMemoryBuildRepository: BuildRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID: Build]

    public init(_ builds: [Build] = []) {
        values = Dictionary(uniqueKeysWithValues: builds.map { ($0.id, $0) })
    }

    public func fetchBuild(id: UUID) throws -> Build? { lock.withLock { values[id] } }

    public func fetchBuilds(gameID: UUID) throws -> [Build] {
        lock.withLock {
            values.values.filter { $0.gameID == gameID }.sorted {
                if $0.isBase != $1.isBase { return $0.isBase }
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        }
    }

    public func fetchBuild(gameID: UUID, imageSHA256: String) throws -> Build? {
        lock.withLock {
            values.values.filter { $0.gameID == gameID && $0.imageSHA256 == imageSHA256 }
                .min { $0.createdAt < $1.createdAt }
        }
    }

    public func fetchBuild(imageSHA256: String) throws -> Build? {
        lock.withLock { values.values.filter { $0.imageSHA256 == imageSHA256 }.min { $0.createdAt < $1.createdAt } }
    }

    public func fetchBuilds(imageSHA1s: [String]) throws -> [Build] {
        let wanted = Set(imageSHA1s.map { $0.lowercased() })
        return lock.withLock { values.values.filter { $0.imageSHA1.map(wanted.contains) == true }.sorted { $0.createdAt < $1.createdAt } }
    }

    public func fetchImportedBuildsMissingImageSHA1() throws -> [Build] {
        lock.withLock { values.values.filter { $0.imageSHA1 == nil && $0.sourceKind == .importedImage }.sorted { $0.createdAt < $1.createdAt } }
    }

    public func setImageSHA1(buildID: UUID, sha1: String) throws {
        lock.withLock { values[buildID]?.imageSHA1 = sha1.lowercased() }
    }

    public func insertBuild(_ build: Build) throws { lock.withLock { values[build.id] = build } }
    public func updateBuildMetadata(_ build: Build) throws { lock.withLock { values[build.id] = build } }

    public func moveBuild(id: UUID, toGameID: UUID) throws {
        lock.withLock { values[id]?.gameID = toGameID }
    }

    var all: [Build] { lock.withLock { Array(values.values) } }
    func removeBuild(id: UUID) { _ = lock.withLock { values.removeValue(forKey: id) } }
}

public final class InMemorySaveProfileRepository: SaveProfileRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID: SaveProfile]

    public init(_ profiles: [SaveProfile] = []) {
        values = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
    }

    public func fetchSaveProfile(id: UUID) throws -> SaveProfile? { lock.withLock { values[id] } }

    public func fetchSaveProfiles(gameID: UUID) throws -> [SaveProfile] {
        lock.withLock {
            values.values.filter { $0.gameID == gameID }.sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        }
    }

    public func insertSaveProfile(_ profile: SaveProfile) throws { lock.withLock { values[profile.id] = profile } }
    public func updateSaveProfile(_ profile: SaveProfile) throws { lock.withLock { values[profile.id] = profile } }
    public func deleteSaveProfile(id: UUID) throws { _ = lock.withLock { values.removeValue(forKey: id) } }

    var all: [SaveProfile] { lock.withLock { Array(values.values) } }
}

public final class InMemorySaveStateRepository: SaveStateRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID: SaveState] = [:]

    public init() {}

    public func insertSaveState(_ state: SaveState) throws { lock.withLock { values[state.id] = state } }

    /// Newest first.
    public func fetchSaveStates(buildID: UUID, saveProfileID: UUID) throws -> [SaveState] {
        lock.withLock {
            values.values.filter { $0.buildID == buildID && $0.saveProfileID == saveProfileID }.sorted {
                $0.createdAt != $1.createdAt ? $0.createdAt > $1.createdAt : $0.id.uuidString < $1.id.uuidString
            }
        }
    }

    public func fetchSaveStates(saveProfileID: UUID) throws -> [SaveState] {
        lock.withLock { values.values.filter { $0.saveProfileID == saveProfileID }.sorted { $0.createdAt > $1.createdAt } }
    }

    public func fetchSaveState(id: UUID) throws -> SaveState? { lock.withLock { values[id] } }

    public func renameSaveState(id: UUID, label: String?) throws { lock.withLock { values[id]?.label = label } }

    public func reassignSaveStates(buildID: UUID, fromSaveProfileID: UUID, toSaveProfileID: UUID) throws {
        lock.withLock {
            for state in values.values where state.buildID == buildID && state.saveProfileID == fromSaveProfileID {
                values[state.id] = SaveState(
                    id: state.id,
                    buildID: state.buildID,
                    saveProfileID: toSaveProfileID,
                    core: state.core,
                    stateSerializationVersion: state.stateSerializationVersion,
                    stateAssetID: state.stateAssetID,
                    screenshotAssetID: state.screenshotAssetID,
                    kind: state.kind,
                    autoSequence: state.autoSequence,
                    label: state.label,
                    playtimeSeconds: state.playtimeSeconds,
                    createdAt: state.createdAt
                )
            }
        }
    }

    public func deleteSaveState(id: UUID) throws { _ = lock.withLock { values.removeValue(forKey: id) } }

    var all: [SaveState] { lock.withLock { Array(values.values) } }
}

public final class InMemoryToolchainReportRepository: ToolchainReportRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID: [String: ToolchainDetectionReport]] = [:]

    public init() {}

    public func saveReport(_ report: ToolchainDetectionReport, buildID: UUID, detectedAt: Date) throws {
        lock.withLock { values[buildID, default: [:]][report.detector] = report }
    }

    public func fetchReports(buildID: UUID) throws -> [ToolchainDetectionReport] {
        lock.withLock { (values[buildID] ?? [:]).values.sorted { $0.detector < $1.detector } }
    }
}

public final class InMemoryBuildVariableMapRepository: BuildVariableMapRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID: BuildVariableMap] = [:]

    public init() {}

    public func insertVariableMap(_ map: BuildVariableMap) throws { lock.withLock { values[map.id] = map } }

    public func fetchVariableMaps(buildID: UUID) throws -> [BuildVariableMap] {
        lock.withLock { values.values.filter { $0.buildID == buildID }.sorted { $0.attachedAt < $1.attachedAt } }
    }

    var all: [BuildVariableMap] { lock.withLock { Array(values.values) } }
    func removeMaps(buildID: UUID) { lock.withLock { values = values.filter { $0.value.buildID != buildID } } }
}

public final class InMemoryPatchRecipeRepository: PatchRecipeRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID: PatchRecipe] = [:]

    public init() {}

    public func insertPatchRecipe(_ recipe: PatchRecipe) throws { lock.withLock { values[recipe.id] = recipe } }

    public func fetchPatchRecipe(resultBuildID: UUID) throws -> PatchRecipe? {
        lock.withLock { values.values.first { $0.resultBuildID == resultBuildID } }
    }

    public func fetchPatchRecipes(baseBuildID: UUID) throws -> [PatchRecipe] {
        lock.withLock { values.values.filter { $0.baseBuildID == baseBuildID }.sorted { $0.createdAt < $1.createdAt } }
    }

    var all: [PatchRecipe] { lock.withLock { Array(values.values) } }
    func removeRecipe(resultBuildID: UUID) { lock.withLock { values = values.filter { $0.value.resultBuildID != resultBuildID } } }
}

public final class InMemoryAssetRepository: ManagedAssetInventoryRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID: ManagedAsset] = [:]

    public init() {}

    public func fetchAsset(id: UUID) throws -> ManagedAsset? { lock.withLock { values[id] } }

    public func fetchAssets() throws -> [ManagedAsset] {
        lock.withLock {
            values.values.sorted {
                $0.createdAt != $1.createdAt ? $0.createdAt < $1.createdAt : $0.id.uuidString < $1.id.uuidString
            }
        }
    }

    public func fetchSourceAsset(kind: ManagedAssetKind, sha256: String) throws -> ManagedAsset? {
        lock.withLock { values.values.first { $0.kind == kind && $0.contentSHA256 == sha256 } }
    }

    public func fetchAsset(relativePath: String) throws -> ManagedAsset? {
        lock.withLock { values.values.first { $0.relativePath == relativePath } }
    }

    /// Enforces the database's unique relative_path, so tests catch a second record for one file.
    public func insertAsset(_ asset: ManagedAsset) throws {
        try lock.withLock {
            if values.values.contains(where: { $0.relativePath == asset.relativePath && $0.id != asset.id }) {
                throw InMemoryRepositoryError.duplicateRelativePath(asset.relativePath)
            }
            values[asset.id] = asset
        }
    }
    public func updateMutableAsset(_ asset: ManagedAsset) throws { lock.withLock { values[asset.id] = asset } }
    public func deleteAsset(id: UUID) throws { _ = lock.withLock { values.removeValue(forKey: id) } }
}

public final class InMemorySettingsStore: SettingsStore, @unchecked Sendable {
    private struct Key: Hashable {
        let key: String
        let scope: SettingsScope
    }

    private let lock = NSLock()
    private var values: [Key: String] = [:]

    public init() {}

    public func valueJSON(key: String, scope: SettingsScope) throws -> String? {
        lock.withLock { values[Key(key: key, scope: scope)] }
    }

    public func setValueJSON(_ valueJSON: String, key: String, scope: SettingsScope) throws {
        lock.withLock { values[Key(key: key, scope: scope)] = valueJSON }
    }

    public func removeValue(key: String, scope: SettingsScope) throws {
        _ = lock.withLock { values.removeValue(forKey: Key(key: key, scope: scope)) }
    }
}

public enum InMemoryRepositoryError: Error, Equatable {
    case duplicateRelativePath(String)
}

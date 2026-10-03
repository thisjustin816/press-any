import EmulatorApplication
import EmulatorDomain
import Foundation
import GRDB

private protocol GRDBRepositoryBacking: AnyObject {
    var writer: any DatabaseWriter { get }
}

private extension GRDBRepositoryBacking {
    func read<T>(_ operation: (Database) throws -> T) throws -> T {
        if let database = GRDBTransactionContext.current {
            return try operation(database)
        }
        return try writer.read(operation)
    }

    func write<T>(_ operation: (Database) throws -> T) throws -> T {
        if let database = GRDBTransactionContext.current {
            return try operation(database)
        }
        return try writer.write(operation)
    }
}

public final class GRDBGameRepository: GameRepository, GRDBRepositoryBacking, @unchecked Sendable {
    let writer: any DatabaseWriter

    init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    public func fetchGame(id: UUID) throws -> Game? {
        try read { db in
            try GameRecord.fetchOne(
                db,
                sql: "SELECT * FROM games WHERE id = ?",
                arguments: [PersistenceCodec.uuid(id)]
            )?.domain()
        }
    }

    public func fetchGames() throws -> [Game] {
        try read { db in
            try GameRecord.fetchAll(db, sql: "SELECT * FROM games ORDER BY primary_title COLLATE NOCASE, created_at")
                .map { try $0.domain() }
        }
    }

    public func insertGame(_ game: Game) throws {
        try write { db in try GameRecord(game).insert(db) }
    }

    public func updateGame(_ game: Game) throws {
        try write { db in try GameRecord(game).update(db) }
    }

    public func deleteGame(id: UUID) throws {
        try write { db in
            let gameID = PersistenceCodec.uuid(id)

            // A patch-derived Build in another Game may still depend on a base Build
            // owned by this Game. Do not silently orphan that external dependency.
            let externalDependents = try Int.fetchOne(
                db,
                sql: """
                SELECT COUNT(*)
                FROM patch_recipes recipe
                JOIN builds base ON base.id = recipe.base_build_id
                JOIN builds result ON result.id = recipe.result_build_id
                WHERE base.game_id = ? AND result.game_id <> ?
                """,
                arguments: [gameID, gameID]
            ) ?? 0
            guard externalDependents == 0 else {
                throw PersistenceError.gameHasExternalPatchDependents(externalDependents)
            }

            // RESTRICT on patch_recipes.base_build_id deliberately protects base
            // Builds during ordinary deletion. Remove recipes whose result Build is
            // owned by the Game first so the subsequent Game cascade is safe.
            try db.execute(
                sql: """
                DELETE FROM patch_recipes
                WHERE result_build_id IN (SELECT id FROM builds WHERE game_id = ?)
                """,
                arguments: [gameID]
            )

            // settings_overrides intentionally has no foreign keys because its
            // scope can also be app/system. Clean Game/Build scoped rows explicitly.
            try db.execute(
                sql: "DELETE FROM settings_overrides WHERE scope_type = 'build' AND scope_id IN (SELECT id FROM builds WHERE game_id = ?)",
                arguments: [gameID]
            )
            try db.execute(
                sql: "DELETE FROM settings_overrides WHERE scope_type = 'game' AND scope_id = ?",
                arguments: [gameID]
            )

            try db.execute(sql: "DELETE FROM games WHERE id = ?", arguments: [gameID])
        }
    }
}

public final class GRDBBuildRepository: BuildRepository, GRDBRepositoryBacking, @unchecked Sendable {
    let writer: any DatabaseWriter

    init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    public func fetchBuild(id: UUID) throws -> Build? {
        try read { db in
            try BuildRecord.fetchOne(
                db,
                sql: "SELECT * FROM builds WHERE id = ?",
                arguments: [PersistenceCodec.uuid(id)]
            )?.domain()
        }
    }

    public func fetchBuilds(gameID: UUID) throws -> [Build] {
        try read { db in
            try BuildRecord.fetchAll(
                db,
                sql: "SELECT * FROM builds WHERE game_id = ? ORDER BY is_base DESC, created_at, display_name COLLATE NOCASE",
                arguments: [PersistenceCodec.uuid(gameID)]
            ).map { try $0.domain() }
        }
    }

    public func fetchBuild(gameID: UUID, imageSHA256: String) throws -> Build? {
        try read { db in
            try BuildRecord.fetchOne(
                db,
                sql: "SELECT * FROM builds WHERE game_id = ? AND rom_sha256 = ? LIMIT 1",
                arguments: [PersistenceCodec.uuid(gameID), imageSHA256.lowercased()]
            )?.domain()
        }
    }

    public func fetchBuild(imageSHA256: String) throws -> Build? {
        try read { db in
            try BuildRecord.fetchOne(
                db,
                sql: "SELECT * FROM builds WHERE rom_sha256 = ? ORDER BY created_at LIMIT 1",
                arguments: [imageSHA256.lowercased()]
            )?.domain()
        }
    }

    public func insertBuild(_ build: Build) throws {
        try write { db in try BuildRecord(build).insert(db) }
    }

    public func updateBuildMetadata(_ build: Build) throws {
        try write { db in try BuildRecord(build).update(db) }
    }

    public func moveBuild(id: UUID, toGameID: UUID) throws {
        try write { db in
            try db.execute(
                sql: "UPDATE builds SET game_id = ? WHERE id = ?",
                arguments: [PersistenceCodec.uuid(toGameID), PersistenceCodec.uuid(id)]
            )
        }
    }
}

public final class GRDBSaveProfileRepository: SaveProfileRepository, GRDBRepositoryBacking, @unchecked Sendable {
    let writer: any DatabaseWriter

    init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    public func fetchSaveProfile(id: UUID) throws -> SaveProfile? {
        try read { db in
            try SaveProfileRecord.fetchOne(
                db,
                sql: "SELECT * FROM save_profiles WHERE id = ?",
                arguments: [PersistenceCodec.uuid(id)]
            )?.domain()
        }
    }

    public func fetchSaveProfiles(gameID: UUID) throws -> [SaveProfile] {
        try read { db in
            try SaveProfileRecord.fetchAll(
                db,
                sql: "SELECT * FROM save_profiles WHERE game_id = ? ORDER BY created_at, display_name COLLATE NOCASE",
                arguments: [PersistenceCodec.uuid(gameID)]
            ).map { try $0.domain() }
        }
    }

    public func insertSaveProfile(_ profile: SaveProfile) throws {
        try write { db in try SaveProfileRecord(profile).insert(db) }
    }

    public func updateSaveProfile(_ profile: SaveProfile) throws {
        try write { db in try SaveProfileRecord(profile).update(db) }
    }

    public func deleteSaveProfile(id: UUID) throws {
        try write { db in
            try db.execute(sql: "DELETE FROM save_profiles WHERE id = ?", arguments: [PersistenceCodec.uuid(id)])
        }
    }
}

public final class GRDBSaveStateRepository: SaveStateRepository, GRDBRepositoryBacking, @unchecked Sendable {
    let writer: any DatabaseWriter

    init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    public func insertSaveState(_ state: SaveState) throws {
        try write { db in try SaveStateRecord(state).insert(db) }
    }

    public func fetchSaveStates(buildID: UUID, saveProfileID: UUID) throws -> [SaveState] {
        try read { db in
            try SaveStateRecord.fetchAll(
                db,
                sql: """
                SELECT * FROM save_states
                WHERE build_id = ? AND save_profile_id = ?
                ORDER BY created_at DESC, id
                """,
                arguments: [PersistenceCodec.uuid(buildID), PersistenceCodec.uuid(saveProfileID)]
            ).map { try $0.domain() }
        }
    }

    public func deleteSaveState(id: UUID) throws {
        try write { db in
            try db.execute(sql: "DELETE FROM save_states WHERE id = ?", arguments: [PersistenceCodec.uuid(id)])
        }
    }
}

public final class GRDBPatchRecipeRepository: PatchRecipeRepository, GRDBRepositoryBacking, @unchecked Sendable {
    let writer: any DatabaseWriter

    init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    public func insertPatchRecipe(_ recipe: PatchRecipe) throws {
        try write { db in
            try PatchRecipeRecord(recipe).insert(db)
            for item in recipe.items.sorted(by: { $0.position < $1.position }) {
                try PatchRecipeItemRecord(recipeID: recipe.id, value: item).insert(db)
            }
        }
    }

    public func fetchPatchRecipe(resultBuildID: UUID) throws -> PatchRecipe? {
        try read { db in
            guard let record = try PatchRecipeRecord.fetchOne(
                db,
                sql: "SELECT * FROM patch_recipes WHERE result_build_id = ?",
                arguments: [PersistenceCodec.uuid(resultBuildID)]
            ) else {
                return nil
            }
            let items = try PatchRecipeItemRecord.fetchAll(
                db,
                sql: "SELECT * FROM patch_recipe_items WHERE recipe_id = ? ORDER BY position",
                arguments: [record.id]
            ).map { try $0.domain() }
            return PatchRecipe(
                id: try PersistenceCodec.uuid(record.id),
                resultBuildID: try PersistenceCodec.uuid(record.resultBuildID),
                baseBuildID: try PersistenceCodec.uuid(record.baseBuildID),
                expectedResultSHA256: record.expectedResultSHA256,
                items: items,
                createdAt: try PersistenceCodec.date(record.createdAt)
            )
        }
    }
}

public final class GRDBManagedAssetRepository: ManagedAssetInventoryRepository, GRDBRepositoryBacking, @unchecked Sendable {
    let writer: any DatabaseWriter

    init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    public func fetchAsset(id: UUID) throws -> ManagedAsset? {
        try read { db in
            try ManagedAssetRecord.fetchOne(
                db,
                sql: "SELECT * FROM managed_assets WHERE id = ?",
                arguments: [PersistenceCodec.uuid(id)]
            )?.domain()
        }
    }

    public func fetchAssets() throws -> [ManagedAsset] {
        try read { db in
            try ManagedAssetRecord.fetchAll(db, sql: "SELECT * FROM managed_assets ORDER BY created_at, id")
                .map { try $0.domain() }
        }
    }

    public func fetchAsset(relativePath: String) throws -> ManagedAsset? {
        try read { db in
            try ManagedAssetRecord.fetchOne(
                db,
                sql: "SELECT * FROM managed_assets WHERE relative_path = ?",
                arguments: [relativePath]
            )?.domain()
        }
    }

    public func fetchSourceAsset(kind: ManagedAssetKind, sha256: String) throws -> ManagedAsset? {
        try read { db in
            try ManagedAssetRecord.fetchOne(
                db,
                sql: """
                SELECT * FROM managed_assets
                WHERE kind = ? AND content_sha256 = ? AND storage_class = 'source'
                LIMIT 1
                """,
                arguments: [kind.rawValue, sha256.lowercased()]
            )?.domain()
        }
    }

    public func insertAsset(_ asset: ManagedAsset) throws {
        try write { db in try ManagedAssetRecord(asset).insert(db) }
    }

    public func updateMutableAsset(_ asset: ManagedAsset) throws {
        try write { db in try ManagedAssetRecord(asset).update(db) }
    }

    public func deleteAsset(id: UUID) throws {
        try write { db in
            try db.execute(sql: "DELETE FROM managed_assets WHERE id = ?", arguments: [PersistenceCodec.uuid(id)])
        }
    }
}

public final class GRDBSettingsStore: SettingsStore, GRDBRepositoryBacking, @unchecked Sendable {
    let writer: any DatabaseWriter

    init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    public func valueJSON(key: String, scope: SettingsScope) throws -> String? {
        try read { db in
            try String.fetchOne(
                db,
                sql: """
                SELECT value_json FROM settings_overrides
                WHERE scope_type = ? AND scope_id = ? AND key = ?
                """,
                arguments: [scope.databaseType, scope.databaseID, key]
            )
        }
    }

    public func setValueJSON(_ valueJSON: String, key: String, scope: SettingsScope) throws {
        try write { db in
            try db.execute(
                sql: """
                INSERT INTO settings_overrides(scope_type, scope_id, key, value_json)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(scope_type, scope_id, key)
                DO UPDATE SET value_json = excluded.value_json
                """,
                arguments: [scope.databaseType, scope.databaseID, key, valueJSON]
            )
        }
    }

    public func removeValue(key: String, scope: SettingsScope) throws {
        try write { db in
            try db.execute(
                sql: "DELETE FROM settings_overrides WHERE scope_type = ? AND scope_id = ? AND key = ?",
                arguments: [scope.databaseType, scope.databaseID, key]
            )
        }
    }
}

public final class GRDBLibraryTransactionRunner: LibraryTransactionRunner, @unchecked Sendable {
    private let writer: any DatabaseWriter

    init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    public func run<T: Sendable>(_ operation: @Sendable () throws -> T) throws -> T {
        if GRDBTransactionContext.current != nil {
            return try operation()
        }
        return try writer.write { db in
            try GRDBTransactionContext.withDatabase(db, operation: operation)
        }
    }
}

public struct GRDBRepositorySet: Sendable {
    public let games: GRDBGameRepository
    public let builds: GRDBBuildRepository
    public let saveProfiles: GRDBSaveProfileRepository
    public let saveStates: GRDBSaveStateRepository
    public let patchRecipes: GRDBPatchRecipeRepository
    public let assets: GRDBManagedAssetRepository
    public let settings: GRDBSettingsStore
    public let transactions: GRDBLibraryTransactionRunner

    init(writer: any DatabaseWriter) {
        games = GRDBGameRepository(writer: writer)
        builds = GRDBBuildRepository(writer: writer)
        saveProfiles = GRDBSaveProfileRepository(writer: writer)
        saveStates = GRDBSaveStateRepository(writer: writer)
        patchRecipes = GRDBPatchRecipeRepository(writer: writer)
        assets = GRDBManagedAssetRepository(writer: writer)
        settings = GRDBSettingsStore(writer: writer)
        transactions = GRDBLibraryTransactionRunner(writer: writer)
    }
}

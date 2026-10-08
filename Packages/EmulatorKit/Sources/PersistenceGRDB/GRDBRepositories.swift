import EmulatorApplication
import EmulatorDomain
import Foundation
import GRDB

protocol GRDBRepositoryBacking: AnyObject {
    var writer: any DatabaseWriter { get }
}

extension GRDBRepositoryBacking {
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
                sql: "SELECT * FROM games WHERE id = ? AND deletion_id IS NULL",
                arguments: [PersistenceCodec.uuid(id)]
            ).map { try $0.domain(aliases: Self.aliases(gameID: $0.id, db: db)) }
        }
    }

    public func fetchGames() throws -> [Game] {
        try read { db in
            try GameRecord.fetchAll(db, sql: "SELECT * FROM games WHERE deletion_id IS NULL ORDER BY primary_title COLLATE NOCASE, created_at")
                .map { try $0.domain(aliases: Self.aliases(gameID: $0.id, db: db)) }
        }
    }

    public func insertGame(_ game: Game) throws {
        try write { db in
            try GameRecord(game).insert(db)
            try Self.saveAliases(game, db: db)
        }
    }

    public func updateGame(_ game: Game) throws {
        try write { db in
            let previous = try GameRecord.fetchOne(db, key: PersistenceCodec.uuid(game.id))
            var updated = game
            if previous?.primaryTitle != game.primaryTitle {
                try MetadataProvenanceSQL.recordPlayerOverride(field: .title, value: game.primaryTitle,
                    ownerID: game.id, ownerTable: "games", at: game.modifiedAt, db: db)
                updated.hasPlayerTitle = true
            } else if let title = try MetadataProvenanceSQL.fetch(ownerID: game.id, ownerTable: "games", db: db).first {
                updated.hasPlayerTitle = title.source == .player
            }
            try GameRecord(updated).update(db)
            try Self.saveAliases(updated, db: db)
        }
    }

    private static func aliases(gameID: String, db: Database) throws -> [String] {
        try String.fetchAll(db, sql: "SELECT title FROM game_aliases WHERE game_id = ? ORDER BY title COLLATE NOCASE", arguments: [gameID])
    }

    private static func saveAliases(_ game: Game, db: Database) throws {
        let id = PersistenceCodec.uuid(game.id)
        try db.execute(sql: "DELETE FROM game_aliases WHERE game_id = ?", arguments: [id])
        for title in game.aliases {
            try db.execute(sql: "INSERT OR IGNORE INTO game_aliases (game_id, title) VALUES (?, ?)", arguments: [id, title])
        }
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
                sql: "SELECT * FROM builds WHERE id = ? AND deletion_id IS NULL",
                arguments: [PersistenceCodec.uuid(id)]
            )?.domain()
        }
    }

    public func fetchBuilds(gameID: UUID) throws -> [Build] {
        try read { db in
            try BuildRecord.fetchAll(
                db,
                sql: "SELECT * FROM builds WHERE game_id = ? AND deletion_id IS NULL ORDER BY is_base DESC, created_at, display_name COLLATE NOCASE",
                arguments: [PersistenceCodec.uuid(gameID)]
            ).map { try $0.domain() }
        }
    }

    public func fetchBuild(gameID: UUID, imageSHA256: String) throws -> Build? {
        try read { db in
            try BuildRecord.fetchOne(
                db,
                sql: "SELECT * FROM builds WHERE game_id = ? AND rom_sha256 = ? AND deletion_id IS NULL LIMIT 1",
                arguments: [PersistenceCodec.uuid(gameID), imageSHA256.lowercased()]
            )?.domain()
        }
    }

    public func fetchBuild(imageSHA256: String) throws -> Build? {
        try read { db in
            try BuildRecord.fetchOne(
                db,
                sql: "SELECT * FROM builds WHERE rom_sha256 = ? AND deletion_id IS NULL ORDER BY created_at LIMIT 1",
                arguments: [imageSHA256.lowercased()]
            )?.domain()
        }
    }

    public func fetchBuilds(imageSHA1s: [String]) throws -> [Build] {
        guard !imageSHA1s.isEmpty else { return [] }
        let list = "(" + Array(repeating: "?", count: imageSHA1s.count).joined(separator: ", ") + ")"
        return try read { db in
            try BuildRecord.fetchAll(
                db,
                sql: "SELECT * FROM builds WHERE rom_sha1 IN \(list) AND deletion_id IS NULL ORDER BY created_at",
                arguments: StatementArguments(imageSHA1s.map { $0.lowercased() })
            ).map { try $0.domain() }
        }
    }

    public func fetchImportedBuildsMissingImageSHA1() throws -> [Build] {
        try read { db in
            try BuildRecord.fetchAll(
                db,
                sql: "SELECT * FROM builds WHERE rom_sha1 IS NULL AND source_kind = ? AND deletion_id IS NULL ORDER BY created_at",
                arguments: [BuildSourceKind.importedImage.rawValue]
            ).map { try $0.domain() }
        }
    }

    public func fetchImportedBuilds() throws -> [Build] {
        try read { db in
            try BuildRecord.fetchAll(
                db,
                sql: "SELECT * FROM builds WHERE source_kind = ? AND deletion_id IS NULL ORDER BY created_at",
                arguments: [BuildSourceKind.importedImage.rawValue]
            ).map { try $0.domain() }
        }
    }

    public func setImageSHA1(buildID: UUID, sha1: String) throws {
        try write { db in
            try db.execute(
                sql: "UPDATE builds SET rom_sha1 = ? WHERE id = ?",
                arguments: [sha1.lowercased(), PersistenceCodec.uuid(buildID)]
            )
        }
    }

    public func insertBuild(_ build: Build) throws {
        try write { db in try BuildRecord(build).insert(db) }
    }

    public func updateBuildMetadata(_ build: Build) throws {
        try write { db in
            if let previous = try BuildRecord.fetchOne(db, key: PersistenceCodec.uuid(build.id))?.domain() {
                for field in MetadataField.allCases where field != .title && field.value(in: previous) != field.value(in: build) {
                    try MetadataProvenanceSQL.recordPlayerOverride(field: field, value: field.value(in: build),
                        ownerID: build.id, ownerTable: "builds", at: build.modifiedAt, db: db)
                }
            }
            let columns = try db.columns(in: BuildRecord.databaseTableName).map(\.name)
                .filter {
                    $0 != "total_playtime_seconds" && $0 != "deletion_id"
                        && ($0 != "rom_sha1" || build.imageSHA1 != nil)
                }
            try BuildRecord(build).update(db, columns: columns)
        }
    }

    public func addPlaytime(buildID: UUID, seconds: Double) throws {
        try write { db in
            try db.execute(
                sql: "UPDATE builds SET total_playtime_seconds = total_playtime_seconds + ? WHERE id = ? AND deletion_id IS NULL",
                arguments: [seconds, PersistenceCodec.uuid(buildID)]
            )
            guard db.changesCount == 1 else { throw BuildOperationError.buildNotFound(buildID) }
        }
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
                sql: "SELECT * FROM save_profiles WHERE id = ? AND deletion_id IS NULL",
                arguments: [PersistenceCodec.uuid(id)]
            )?.domain()
        }
    }

    public func fetchSaveProfiles(gameID: UUID) throws -> [SaveProfile] {
        try read { db in
            try SaveProfileRecord.fetchAll(
                db,
                sql: "SELECT * FROM save_profiles WHERE game_id = ? AND deletion_id IS NULL ORDER BY created_at, display_name COLLATE NOCASE",
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

    public func updateSaveState(_ state: SaveState) throws {
        try write { db in try SaveStateRecord(state).update(db) }
    }

    public func fetchSaveStates(buildID: UUID, saveProfileID: UUID) throws -> [SaveState] {
        try read { db in
            try SaveStateRecord.fetchAll(
                db,
                sql: """
                SELECT * FROM save_states
                WHERE build_id = ? AND save_profile_id = ? AND deletion_id IS NULL
                ORDER BY created_at DESC, id
                """,
                arguments: [PersistenceCodec.uuid(buildID), PersistenceCodec.uuid(saveProfileID)]
            ).map { try $0.domain() }
        }
    }

    public func fetchSaveStates(saveProfileID: UUID) throws -> [SaveState] {
        try read { db in
            try SaveStateRecord.fetchAll(
                db,
                sql: "SELECT * FROM save_states WHERE save_profile_id = ? AND deletion_id IS NULL ORDER BY created_at DESC, id",
                arguments: [PersistenceCodec.uuid(saveProfileID)]
            ).map { try $0.domain() }
        }
    }

    public func fetchSaveState(id: UUID) throws -> SaveState? {
        try read { db in
            try SaveStateRecord.fetchOne(
                db,
                sql: "SELECT * FROM save_states WHERE id = ? AND deletion_id IS NULL",
                arguments: [PersistenceCodec.uuid(id)]
            )?.domain()
        }
    }

    public func renameSaveState(id: UUID, label: String?) throws {
        try write { db in
            try db.execute(
                sql: "UPDATE save_states SET label = ? WHERE id = ? AND deletion_id IS NULL",
                arguments: [label, PersistenceCodec.uuid(id)]
            )
        }
    }

    public func reassignSaveStates(buildID: UUID, fromSaveProfileID: UUID, toSaveProfileID: UUID) throws {
        try write { db in
            try db.execute(
                sql: "UPDATE save_states SET save_profile_id = ? WHERE build_id = ? AND save_profile_id = ?",
                arguments: [
                    PersistenceCodec.uuid(toSaveProfileID),
                    PersistenceCodec.uuid(buildID),
                    PersistenceCodec.uuid(fromSaveProfileID),
                ]
            )
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
            return try Self.recipe(record, items: items)
        }
    }

    public func fetchPatchRecipes(baseBuildID: UUID) throws -> [PatchRecipe] {
        try read { db in
            try PatchRecipeRecord.fetchAll(
                db,
                sql: "SELECT * FROM patch_recipes WHERE base_build_id = ? ORDER BY created_at, id",
                arguments: [PersistenceCodec.uuid(baseBuildID)]
            ).map { record in
                let items = try PatchRecipeItemRecord.fetchAll(
                    db,
                    sql: "SELECT * FROM patch_recipe_items WHERE recipe_id = ? ORDER BY position",
                    arguments: [record.id]
                ).map { try $0.domain() }
                return try Self.recipe(record, items: items)
            }
        }
    }

    private static func recipe(_ record: PatchRecipeRecord, items: [PatchRecipeItem]) throws -> PatchRecipe {
        PatchRecipe(
            id: try PersistenceCodec.uuid(record.id),
            resultBuildID: try PersistenceCodec.uuid(record.resultBuildID),
            baseBuildID: try PersistenceCodec.uuid(record.baseBuildID),
            expectedResultSHA256: record.expectedResultSHA256,
            items: items,
            createdAt: try PersistenceCodec.date(record.createdAt)
        )
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

public final class GRDBToolchainReportRepository: ToolchainReportRepository, GRDBRepositoryBacking, @unchecked Sendable {
    let writer: any DatabaseWriter

    init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    public func saveReport(_ report: ToolchainDetectionReport, buildID: UUID, detectedAt: Date) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: try encoder.encode(report), as: UTF8.self)
        try write { db in
            try db.execute(
                sql: """
                INSERT INTO build_toolchain_reports(
                    build_id, detector, detector_version, corpus_revision, report_json, detected_at
                )
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(build_id, detector) DO UPDATE SET
                    detector_version = excluded.detector_version,
                    corpus_revision = excluded.corpus_revision,
                    report_json = excluded.report_json,
                    detected_at = excluded.detected_at
                """,
                arguments: [
                    PersistenceCodec.uuid(buildID), report.detector, report.detectorVersion,
                    report.corpusRevision, json, PersistenceCodec.date(detectedAt),
                ]
            )
        }
    }

    public func fetchReports(buildID: UUID) throws -> [ToolchainDetectionReport] {
        let rows = try read { db in
            try String.fetchAll(
                db,
                sql: "SELECT report_json FROM build_toolchain_reports WHERE build_id = ? ORDER BY detector",
                arguments: [PersistenceCodec.uuid(buildID)]
            )
        }
        return try rows.map { try JSONDecoder().decode(ToolchainDetectionReport.self, from: Data($0.utf8)) }
    }
}

public final class GRDBBuildVariableMapRepository: BuildVariableMapRepository, GRDBRepositoryBacking, @unchecked Sendable {
    let writer: any DatabaseWriter

    init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    public func insertVariableMap(_ map: BuildVariableMap) throws {
        try write { db in
            try db.execute(
                sql: """
                INSERT INTO build_variable_maps(id, build_id, asset_id, format, source, original_filename, attached_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    PersistenceCodec.uuid(map.id), PersistenceCodec.uuid(map.buildID), PersistenceCodec.uuid(map.assetID),
                    map.format.rawValue, map.source.rawValue, map.originalFilename, PersistenceCodec.date(map.attachedAt),
                ]
            )
        }
    }

    public func fetchVariableMaps(buildID: UUID) throws -> [BuildVariableMap] {
        let rows = try read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM build_variable_maps WHERE build_id = ? ORDER BY attached_at, id",
                arguments: [PersistenceCodec.uuid(buildID)]
            )
        }
        return try rows.map { row in
            let format: String = row["format"]
            let source: String = row["source"]
            guard let mapFormat = BuildVariableMap.Format(rawValue: format) else {
                throw PersistenceError.invalidEnum(type: "BuildVariableMap.Format", value: format)
            }
            guard let mapSource = BuildVariableMap.Source(rawValue: source) else {
                throw PersistenceError.invalidEnum(type: "BuildVariableMap.Source", value: source)
            }
            return BuildVariableMap(
                id: try PersistenceCodec.uuid(row["id"] as String),
                buildID: try PersistenceCodec.uuid(row["build_id"] as String),
                assetID: try PersistenceCodec.uuid(row["asset_id"] as String),
                format: mapFormat,
                source: mapSource,
                originalFilename: row["original_filename"],
                attachedAt: try PersistenceCodec.date(row["attached_at"] as String)
            )
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
    public let toolchainReports: GRDBToolchainReportRepository
    public let variableMaps: GRDBBuildVariableMapRepository
    public let assets: GRDBManagedAssetRepository
    public let settings: GRDBSettingsStore
    public let transactions: GRDBLibraryTransactionRunner
    public let deletions: GRDBLibraryDeletionRepository

    init(writer: any DatabaseWriter) {
        games = GRDBGameRepository(writer: writer)
        builds = GRDBBuildRepository(writer: writer)
        saveProfiles = GRDBSaveProfileRepository(writer: writer)
        saveStates = GRDBSaveStateRepository(writer: writer)
        patchRecipes = GRDBPatchRecipeRepository(writer: writer)
        toolchainReports = GRDBToolchainReportRepository(writer: writer)
        variableMaps = GRDBBuildVariableMapRepository(writer: writer)
        assets = GRDBManagedAssetRepository(writer: writer)
        settings = GRDBSettingsStore(writer: writer)
        transactions = GRDBLibraryTransactionRunner(writer: writer)
        deletions = GRDBLibraryDeletionRepository(writer: writer)
    }
}

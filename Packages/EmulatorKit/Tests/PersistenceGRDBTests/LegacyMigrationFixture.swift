import EmulatorDomain
import Foundation
import GRDB
@testable import PersistenceGRDB

/// Seed an older schema with only the columns it had; current repositories write the current schema.
func legacyFixture(in database: AppDatabase, includingDeletedRecords: Bool = false) throws -> Fixture {
    let current = try AppDatabase.inMemory()
    try current.migrate()
    let fixture = try Fixture.create(in: current.makeRepositories())
    let destinationTables = try database.writer.read { db in
        try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
    }
    let gameColumns = try database.writer.read { db in try db.columns(in: "games").map(\.name) }
    let alias = "Fixture Alias"
    try current.writer.write { db in
        let gameID = PersistenceCodec.uuid(fixture.game.id)
        let buildID = PersistenceCodec.uuid(fixture.build.id)
        let date = PersistenceCodec.date(fixture.game.createdAt)
        try db.execute(
            sql: "INSERT INTO game_aliases (game_id, title) VALUES (?, ?)", arguments: [gameID, alias]
        )
        try db.execute(
            sql: "INSERT INTO settings_overrides (scope_type, scope_id, key, value_json) VALUES ('build', ?, 'skipBootLogo', 'true')",
            arguments: [buildID]
        )
        let report = ToolchainDetectionReport(detector: "fixture", detectorVersion: "1", corpusRevision: "1", components: [])
        try db.execute(
            sql: "INSERT INTO build_toolchain_reports VALUES (?, ?, ?, ?, ?, ?)",
            arguments: [buildID, report.detector, report.detectorVersion, report.corpusRevision,
                String(decoding: try JSONEncoder().encode(report), as: UTF8.self), date]
        )
        try db.execute(
            sql: "INSERT INTO build_variable_maps VALUES (?, ?, ?, 'symbolFile', 'userImport', 'fixture.sym', ?)",
            arguments: [PersistenceCodec.uuid(UUID()), buildID, PersistenceCodec.uuid(fixture.romAsset.id), date]
        )
        let deletionID = PersistenceCodec.uuid(UUID())
        try db.execute(
            sql: "INSERT INTO library_deletions VALUES (?, 'build', 'Deleted Fixture', ?, ?)",
            arguments: [deletionID, gameID, date]
        )
        if includingDeletedRecords {
            try db.execute(
                sql: "UPDATE builds SET deletion_id = ? WHERE id = ?",
                arguments: [deletionID, PersistenceCodec.uuid(fixture.patchedBuild.id)]
            )
        }
        try db.execute(
            sql: "INSERT INTO tombstones VALUES (?, 'saveState', ?, ?)",
            arguments: [PersistenceCodec.uuid(UUID()), date, date]
        )
    }
    let tables = [
        "managed_assets", "games", "builds", "save_profiles", "save_states", "patch_recipes",
        "patch_recipe_items", "settings_overrides", "build_toolchain_reports", "build_variable_maps",
        "game_aliases", "library_deletions", "tombstones",
    ].filter { destinationTables.contains($0) }
    for table in tables {
        let columns = try database.writer.read { db in try db.columns(in: table).map(\.name) }
        let rows = try current.writer.read { db in try Row.fetchAll(db, sql: "SELECT \(columns.joined(separator: ",")) FROM \(table)") }
        try database.writer.write { db in
            for row in rows {
                let arguments = StatementArguments(columns.map { row[$0] as DatabaseValue })
                let placeholders = Array(repeating: "?", count: columns.count).joined(separator: ",")
                try db.execute(sql: "INSERT INTO \(table) (\(columns.joined(separator: ","))) VALUES (\(placeholders))", arguments: arguments)
            }
        }
    }
    var game = fixture.game
    game.hasPlayerTitle = gameColumns.contains("has_player_title") ? fixture.game.hasPlayerTitle : true
    game.aliases = destinationTables.contains("game_aliases") ? [alias] : []
    return Fixture(game: game, build: fixture.build, patchedBuild: fixture.patchedBuild, profile: fixture.profile,
        state: fixture.state, recipe: fixture.recipe, romAsset: fixture.romAsset)
}

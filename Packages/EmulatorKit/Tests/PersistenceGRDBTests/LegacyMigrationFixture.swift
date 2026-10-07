import EmulatorDomain
import GRDB
@testable import PersistenceGRDB

/// Seed an older schema with only the columns it had; current repositories write the current schema.
func legacyFixture(in database: AppDatabase) throws -> Fixture {
    let current = try AppDatabase.inMemory()
    try current.migrate()
    let fixture = try Fixture.create(in: current.makeRepositories())
    let tables = ["managed_assets", "games", "builds", "save_profiles", "save_states", "patch_recipes", "patch_recipe_items"]
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
    game.hasPlayerTitle = true
    return Fixture(game: game, build: fixture.build, patchedBuild: fixture.patchedBuild, profile: fixture.profile,
        state: fixture.state, recipe: fixture.recipe, romAsset: fixture.romAsset)
}

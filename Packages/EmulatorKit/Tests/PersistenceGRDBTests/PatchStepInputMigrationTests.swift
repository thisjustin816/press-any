import EmulatorDomain
import Foundation
import GRDB
import Testing
@testable import PersistenceGRDB

@Suite("Patch step input migration")
struct PatchStepInputMigrationTests {
    @Test("v13 preserves every populated v10 table and leaves input hashes NULL", arguments: [false, true])
    func upgrade(includingDeletedRecords: Bool) throws {
        let database = try AppDatabase.inMemory()
        try AppDatabase.migrator.migrate(database.writer, upTo: "v1-v10-library-model")
        let fixture = try legacyFixture(in: database, includingDeletedRecords: includingDeletedRecords)
        let before = try database.writer.read { db in
            let tables = try String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master WHERE type = 'table'
                AND name NOT LIKE 'sqlite_%' AND name != 'grdb_migrations' ORDER BY name
                """)
            return try tables.map { table in
                let columns = try db.columns(in: table).map(\.name)
                let rows = try Row.fetchAll(db, sql: "SELECT \(columns.joined(separator: ",")) FROM \(table) ORDER BY rowid")
                return (table, columns, rows)
            }
        }
        #expect(before.count == 13)
        #expect(before.allSatisfy { !$0.2.isEmpty })
        try database.migrate()
        try database.writer.read { db in
            for (table, columns, rows) in before {
                #expect(try Row.fetchAll(db, sql: "SELECT \(columns.joined(separator: ",")) FROM \(table) ORDER BY rowid") == rows)
            }
            let rows = try Row.fetchAll(db, sql: "SELECT expected_input_sha256 FROM patch_recipe_items")
            #expect(!rows.isEmpty)
            #expect(rows.allSatisfy { $0["expected_input_sha256"] as String? == nil })
            #expect(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
            #expect(try String.fetchOne(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid DESC LIMIT 1") == "v1-v13-patch-step-inputs")
        }
        #expect(try database.makeRepositories().patchRecipes.fetchPatchRecipe(resultBuildID: fixture.patchedBuild.id) == fixture.recipe)
    }

    @Test("GRDB inserts and fetches recorded and absent input hashes")
    func roundTrip() throws {
        let database = try AppDatabase.inMemory()
        try database.migrate()
        let repositories = database.makeRepositories()
        let fixture = try Fixture.create(in: repositories)
        let item = try #require(fixture.recipe.items.first)
        let hash = String(repeating: "a", count: 64)
        try database.writer.write { db in try db.execute(sql: "DELETE FROM patch_recipes") }
        let recipe = PatchRecipe(
            id: fixture.recipe.id, resultBuildID: fixture.patchedBuild.id, baseBuildID: fixture.build.id,
            expectedResultSHA256: fixture.recipe.expectedResultSHA256,
            items: [
                PatchRecipeItem(position: 0, patchAssetID: item.patchAssetID, expectedInputSHA256: hash),
                PatchRecipeItem(position: 1, patchAssetID: item.patchAssetID, enabled: false),
            ], createdAt: fixture.recipe.createdAt
        )
        try repositories.patchRecipes.insertPatchRecipe(recipe)
        #expect(try repositories.patchRecipes.fetchPatchRecipe(resultBuildID: fixture.patchedBuild.id) == recipe)
        #expect(try repositories.patchRecipes.fetchPatchRecipes(baseBuildID: fixture.build.id) == [recipe])
    }
}

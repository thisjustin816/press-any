import EmulatorDomain
import Foundation
import GRDB
import Testing
@testable import PersistenceGRDB

@Suite("GRDB migrations")
struct MigrationTests {
    @Test("a populated first-version library migrates with its rows intact")
    func populatedV1Upgrade() throws {
        let database = try AppDatabase.inMemory()
        try AppDatabase.migrator.migrate(database.writer, upTo: "mvp-v1")

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let date = PersistenceCodec.date(now)
        let gameID = UUID(), buildID = UUID(), patchedID = UUID(), profileID = UUID(), stateID = UUID(), recipeID = UUID()
        let romID = UUID(), patchID = UUID(), generatedID = UUID(), batteryID = UUID(), stateAssetID = UUID()
        let id: (UUID) -> String = PersistenceCodec.uuid
        try database.writer.write { db in
            for (asset, kind, storage, path) in [
                (romID, "sourceROM", "source", "Source/ROM/aa/a.rom"),
                (patchID, "sourcePatch", "source", "Source/Patch/bb/b.ips"),
                (generatedID, "generatedROM", "cache", "Cache/GeneratedROM/cc/c.rom"),
                (batteryID, "batterySave", "userData", "UserData/SaveProfiles/p/battery.sav"),
                (stateAssetID, "saveState", "userData", "UserData/States/s.state"),
            ] {
                try db.execute(
                    sql: """
                    INSERT INTO managed_assets
                    (id, kind, storage_class, content_sha256, byte_length, relative_path, integrity_status, created_at)
                    VALUES (?, ?, ?, ?, 1, ?, 'verified', ?)
                    """,
                    arguments: [id(asset), kind, storage, String(repeating: "a", count: 64), path, date]
                )
            }
            try db.execute(
                sql: """
                INSERT INTO games (id, primary_title, system_family, preferred_build_id, created_at, modified_at)
                VALUES (?, 'Old', 'gameboy', ?, ?, ?)
                """,
                arguments: [id(gameID), id(buildID), date, date]
            )
            try db.execute(
                sql: """
                INSERT INTO builds
                (id, game_id, system, display_name, rom_asset_id, rom_sha256, source_kind, is_base, created_at, modified_at)
                VALUES (?, ?, 'gbc', 'Original', ?, ?, 'importedROM', 1, ?, ?),
                       (?, ?, 'gbc', 'Hack', ?, ?, 'patchRecipe', 0, ?, ?)
                """,
                arguments: [
                    id(buildID), id(gameID), id(romID), String(repeating: "a", count: 64), date, date,
                    id(patchedID), id(gameID), id(generatedID), String(repeating: "c", count: 64), date, date,
                ]
            )
            try db.execute(
                sql: """
                INSERT INTO save_profiles
                (id, game_id, display_name, battery_asset_id, total_playtime_seconds, session_count, created_at, modified_at)
                VALUES (?, ?, 'Main', ?, 12.5, 2, ?, ?)
                """,
                arguments: [id(profileID), id(gameID), id(batteryID), date, date]
            )
            try db.execute(
                sql: """
                INSERT INTO save_states
                (id, build_id, save_profile_id, core_id, core_version, state_serialization_version, state_asset_id,
                 kind, auto_sequence, playtime_seconds, created_at)
                VALUES (?, ?, ?, 'sameboy', '1.0.3', 'sameboy-bess-v1', ?, 'auto', 1, 12.5, ?)
                """,
                arguments: [id(stateID), id(buildID), id(profileID), id(stateAssetID), date]
            )
            try db.execute(
                sql: """
                INSERT INTO patch_recipes (id, result_build_id, base_build_id, expected_result_sha256, created_at)
                VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [id(recipeID), id(patchedID), id(buildID), String(repeating: "c", count: 64), date]
            )
            try db.execute(
                sql: "INSERT INTO patch_recipe_items (recipe_id, position, patch_asset_id, enabled) VALUES (?, 0, ?, 1)",
                arguments: [id(recipeID), id(patchID)]
            )
        }

        try database.migrate()
        let repositories = database.makeRepositories()

        let game = try #require(try repositories.games.fetchGame(id: gameID))
        #expect(game.preferredBuildID == buildID)
        #expect(game.artworkAssetID == nil)
        #expect(game.lineage == nil)
        #expect(try repositories.builds.fetchBuilds(gameID: gameID).map(\.id) == [buildID, patchedID])
        let profile = try #require(try repositories.saveProfiles.fetchSaveProfile(id: profileID))
        #expect(profile.persistentSaveAssetID == batteryID)
        #expect(profile.totalPlaytimeSeconds == 12.5)
        #expect(profile.saveWrittenByBuildID == nil)
        #expect(profile.modifiedAt == now)
        let state = try #require(try repositories.saveStates.fetchSaveStates(buildID: buildID, saveProfileID: profileID).first)
        #expect(state.id == stateID)
        #expect(state.kind == .auto)
        #expect(state.createdAt == now)
        let recipe = try #require(try repositories.patchRecipes.fetchPatchRecipe(resultBuildID: patchedID))
        #expect(recipe.items == [PatchRecipeItem(position: 0, patchAssetID: patchID, enabled: true, ignoresBaseMismatch: false)])
        #expect(try repositories.toolchainReports.fetchReports(buildID: buildID) == [])
        #expect(try repositories.variableMaps.fetchVariableMaps(buildID: buildID) == [])
    }
}

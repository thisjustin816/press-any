import EmulatorApplication
import EmulatorDomain
import Foundation
import GRDB
import Testing
@testable import PersistenceGRDB

@Suite("GRDB migrations")
struct MigrationTests {
    @Test("slot upgrade preserves old columns and defaults pins, including deleted rows", arguments: [false, true])
    func saveStateSlotsUpgrade(deleted: Bool) throws {
        let database = try AppDatabase.inMemory()
        try AppDatabase.migrator.migrate(database.writer, upTo: "v1-v14-metadata-provenance")
        let fixture = try legacyFixture(in: database)
        if deleted {
            try database.writer.write { db in
                try db.execute(sql: "UPDATE save_states SET deletion_id = 'fixture-deletion'")
            }
        }
        let before = try database.writer.read { db in
            let columns = try db.columns(in: "save_states").map(\.name)
            return (columns, try Row.fetchAll(db, sql: "SELECT * FROM save_states ORDER BY id"))
        }
        #expect(!before.1.isEmpty)
        try database.migrate()
        try database.writer.read { db throws -> Void in
            #expect(try Row.fetchAll(db, sql: "SELECT \(before.0.joined(separator: ",")) FROM save_states ORDER BY id") == before.1)
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM save_states WHERE slot IS NOT NULL OR is_pinned != 0") == 0)
            #expect(try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations").contains("v1-v15-save-state-slots") == true)
        }
        if !deleted { #expect(try database.makeRepositories().saveStates.fetchSaveState(id: fixture.state.id) == fixture.state) }
    }

    @Test("unique slot index rejects a second live state but allows deleted slots and other contexts")
    func uniqueLiveSlot() throws {
        let database = try AppDatabase.inMemory()
        try database.migrate()
        let repositories = database.makeRepositories()
        let f = try Fixture.create(in: repositories)
        func slotState(profileID: UUID, buildID: UUID) -> SaveState {
            SaveState(id: UUID(), buildID: buildID, saveProfileID: profileID, core: f.state.core,
                stateSerializationVersion: f.state.stateSerializationVersion, stateAssetID: f.state.stateAssetID,
                kind: .slot, slot: 2, playtimeSeconds: 0, createdAt: f.state.createdAt)
        }
        let first = slotState(profileID: f.profile.id, buildID: f.build.id)
        try repositories.saveStates.insertSaveState(first)
        #expect(throws: DatabaseError.self) {
            try repositories.saveStates.insertSaveState(slotState(profileID: f.profile.id, buildID: f.build.id))
        }
        let otherProfile = SaveProfile(id: UUID(), gameID: f.game.id, displayName: "Other", createdAt: f.state.createdAt, modifiedAt: f.state.createdAt)
        try repositories.saveProfiles.insertSaveProfile(otherProfile)
        try repositories.saveStates.insertSaveState(slotState(profileID: otherProfile.id, buildID: f.build.id))
        try repositories.saveStates.insertSaveState(slotState(profileID: f.profile.id, buildID: f.patchedBuild.id))
        let deletion = LibraryDeletion(id: UUID(), kind: .saveState, title: "Slot 2", gameID: f.game.id,
            deletedAt: f.state.createdAt, records: LibraryRecordSet(saveStateIDs: [first.id]))
        try repositories.deletions.insertDeletion(deletion)
        try repositories.saveStates.insertSaveState(slotState(profileID: f.profile.id, buildID: f.build.id))
    }

    @Test("provenance upgrade preserves every populated table and adds no rows", arguments: [false, true])
    func metadataProvenanceUpgrade(includingDeletedRecords: Bool) throws {
        let database = try AppDatabase.inMemory()
        try AppDatabase.migrator.migrate(database.writer, upTo: "v1-v13-patch-step-inputs")
        let fixture = try legacyFixture(in: database, includingDeletedRecords: includingDeletedRecords)
        try database.writer.write { db in
            let declaration = BuildSaveDeclaration(between: fixture.build.id, and: fixture.patchedBuild.id, compatibility: .sharesSaves)
            try db.execute(sql: "INSERT INTO build_save_declarations VALUES (?, ?, ?)",
                arguments: [PersistenceCodec.uuid(declaration.firstBuildID), PersistenceCodec.uuid(declaration.secondBuildID), "sharesSaves"])
        }
        let before = try database.writer.read { db in
            let tables = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'grdb_migrations' ORDER BY name")
            return try tables.map { table in
                let columns = try db.columns(in: table).map(\.name)
                return (table, columns, try Row.fetchAll(db, sql: "SELECT \(columns.joined(separator: ",")) FROM \(table) ORDER BY rowid"))
            }
        }
        #expect(before.count == 14)
        #expect(before.allSatisfy { !$0.2.isEmpty })
        try database.migrate()
        try database.writer.read { db throws -> Void in
            for (table, columns, rows) in before {
                #expect(try Row.fetchAll(db, sql: "SELECT \(columns.joined(separator: ",")) FROM \(table) ORDER BY rowid") == rows)
            }
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM game_metadata_provenance") == 0)
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM build_metadata_provenance") == 0)
            #expect(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
            #expect(try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations").contains("v1-v14-metadata-provenance"))
        }
    }

    @Test("library-model and save compatibility upgrades preserve every populated table",
        arguments: ["v1-v9-game-identity", "v1-v10-library-model"], [false, true])
    func libraryModelUpgrade(from migration: String, includingDeletedRecords: Bool) throws {
        let database = try AppDatabase.inMemory()
        try AppDatabase.migrator.migrate(database.writer, upTo: migration)
        let fixture = try legacyFixture(in: database, includingDeletedRecords: includingDeletedRecords)
        let before = try database.writer.read { db in
            let tables = try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'grdb_migrations' ORDER BY name"
            )
            return try tables.map { table in
                let columns = try db.columns(in: table).map(\.name)
                let rows = try Row.fetchAll(db, sql: "SELECT \(columns.joined(separator: ",")) FROM \(table) ORDER BY rowid")
                return (table, columns, rows)
            }
        }
        #expect(before.count == 13)
        #expect(before.allSatisfy { !$0.2.isEmpty }, "every existing application table has rows to preserve")

        try database.migrate()

        try database.writer.read { db in
            for (table, columns, rows) in before {
                let upgraded = try Row.fetchAll(db, sql: "SELECT \(columns.joined(separator: ",")) FROM \(table) ORDER BY rowid")
                #expect(upgraded == rows, "migration changed existing rows in \(table)")
            }
            #expect(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
            #expect(try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid").suffix(11) == [
                "v1-v9-game-identity", "v1-v10-library-model", "v1-v11-save-compatibility",
                "v1-v12-system-screen-colors", "v1-v13-patch-step-inputs", "v1-v14-metadata-provenance",
                "v1-v15-save-state-slots", "v1-v16-image-fingerprints", "v1-v17-manual-order", "v1-v18-build-cheats",
                "v1-v19-timed-states",
            ])
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM build_save_declarations") == 0)
        }
        let repositories = database.makeRepositories()
        let game = try #require(try repositories.games.fetchGame(id: fixture.game.id))
        #expect(game == fixture.game)
        #expect(game.isFavorite == (migration == "v1-v10-library-model"))
        let build = try #require(try repositories.builds.fetchBuild(id: fixture.build.id))
        #expect(build == fixture.build)
        #expect(build.notes == (migration == "v1-v10-library-model" ? "Fixture notes\nRoute A" : ""))
        #expect(build.totalPlaytimeSeconds == (migration == "v1-v10-library-model" ? 42.5 : 0))
        #expect(try repositories.builds.fetchSaveDeclarations(buildID: build.id).isEmpty)
        #expect(try repositories.saveProfiles.fetchSaveProfile(id: fixture.profile.id) == fixture.profile)
        #expect(try repositories.saveStates.fetchSaveState(id: fixture.state.id) == fixture.state)
        let recipe = try #require(try repositories.patchRecipes.fetchPatchRecipe(resultBuildID: fixture.patchedBuild.id))
        #expect(recipe == fixture.recipe)
        if includingDeletedRecords {
            #expect(try repositories.builds.fetchBuild(id: fixture.patchedBuild.id) == nil)
            let deletion = try #require(try repositories.deletions.fetchDeletions().first)
            try repositories.deletions.restoreDeletion(id: deletion.id)
        }
        #expect(try repositories.builds.fetchBuild(id: fixture.patchedBuild.id) == fixture.patchedBuild)
    }

    @Test("Screen Colors chosen in App Settings move to the system each applies to")
    func systemScreenColorsUpgrade() throws {
        let database = try AppDatabase.inMemory()
        try AppDatabase.migrator.migrate(database.writer, upTo: "v1-v11-save-compatibility")
        let store = database.makeRepositories().settings
        try store.set(DMGPalette.pocket, key: SettingKey.dmgPalette.rawValue, scope: .app)
        try store.set(ColorCorrection.off, key: SettingKey.colorCorrection.rawValue, scope: .app)
        try store.set(ColorCorrection.accurate, key: SettingKey.colorCorrection.rawValue, scope: .system(.gameBoyColor))
        try store.set(true, key: SettingKey.skipBootAnimation.rawValue, scope: .app)

        try database.migrate()

        let palette = try store.valueJSON(key: SettingKey.dmgPalette.rawValue, scope: .system(.gameBoy))
        #expect(palette == String(decoding: try JSONEncoder().encode(DMGPalette.pocket), as: UTF8.self))
        let correction = try store.valueJSON(key: SettingKey.colorCorrection.rawValue, scope: .system(.gameBoyColor))
        #expect(correction == String(decoding: try JSONEncoder().encode(ColorCorrection.accurate), as: UTF8.self),
            "a system's own value wins over the App Settings one")
        #expect(try store.valueJSON(key: SettingKey.dmgPalette.rawValue, scope: .app) == nil)
        #expect(try store.valueJSON(key: SettingKey.colorCorrection.rawValue, scope: .app) == nil)
        #expect(try store.valueJSON(key: SettingKey.dmgPalette.rawValue, scope: .system(.gameBoyColor)) == nil)
        #expect(try store.valueJSON(key: SettingKey.skipBootAnimation.rawValue, scope: .app) == "true")
    }

    @Test("existing Base markers collapse to one and the database enforces that role")
    func singleBaseUpgrade() throws {
        let database = try AppDatabase.inMemory()
        try AppDatabase.migrator.migrate(database.writer, upTo: "mvp-v3")
        let assetID = PersistenceCodec.uuid(UUID())
        let olderDate = PersistenceCodec.date(Date(timeIntervalSince1970: 1_700_000_000))
        let newerDate = PersistenceCodec.date(Date(timeIntervalSince1970: 1_700_000_001))
        let fixtures = [true, false].map { prefersOlder in
            (game: UUID(), older: UUID(), newer: UUID(), prefersOlder: prefersOlder)
        }
        try database.writer.write { db in
            try db.execute(
                sql: """
                INSERT INTO managed_assets
                (id, kind, storage_class, content_sha256, byte_length, relative_path, integrity_status, created_at)
                VALUES (?, 'sourceROM', 'source', ?, 1, 'Source/ROM/example.rom', 'verified', ?)
                """,
                arguments: [assetID, String(repeating: "a", count: 64), olderDate]
            )
            for fixture in fixtures {
                let gameID = PersistenceCodec.uuid(fixture.game)
                try db.execute(
                    sql: """
                    INSERT INTO games (id, primary_title, system_family, preferred_build_id, created_at, modified_at)
                    VALUES (?, 'Example', 'gameboy', ?, ?, ?)
                    """,
                    arguments: [gameID, fixture.prefersOlder ? PersistenceCodec.uuid(fixture.older) : nil, olderDate, olderDate]
                )
                for (id, hash, date) in [(fixture.older, "a", olderDate), (fixture.newer, "b", newerDate)] {
                    try db.execute(
                        sql: """
                        INSERT INTO builds
                        (id, game_id, system, display_name, rom_asset_id, rom_sha256, source_kind, is_base, created_at, modified_at)
                        VALUES (?, ?, 'gb', 'Example', ?, ?, 'importedROM', 1, ?, ?)
                        """,
                        arguments: [PersistenceCodec.uuid(id), gameID, assetID, String(repeating: hash, count: 64), date, date]
                    )
                }
            }
        }

        try database.migrate()
        let repositories = database.makeRepositories()
        for fixture in fixtures {
            let builds = try repositories.builds.fetchBuilds(gameID: fixture.game)
            #expect(builds.count == 2)
            #expect(builds.filter(\.isBase).map(\.id) == [fixture.prefersOlder ? fixture.older : fixture.newer])
            let demoted = try #require(builds.first { !$0.isBase })
            #expect(throws: (any Error).self) {
                try database.writer.write { db in
                    try db.execute(sql: "UPDATE builds SET is_base = 1 WHERE id = ?", arguments: [PersistenceCodec.uuid(demoted.id)])
                }
            }
        }
    }

    @Test("release sort keys stored before prereleases sorted gain the release marker")
    func releaseSortMarkerUpgrade() throws {
        let database = try AppDatabase.inMemory()
        try AppDatabase.migrator.migrate(database.writer, upTo: "v1-v5-single-base")
        let date = PersistenceCodec.date(Date(timeIntervalSince1970: 1_700_000_000))
        let assetID = PersistenceCodec.uuid(UUID()), gameID = PersistenceCodec.uuid(UUID())
        let release = UUID(), unversioned = UUID()
        let key = "0000000001.0000000000.0000000000.0000000000"
        try database.writer.write { db in
            try db.execute(
                sql: """
                INSERT INTO managed_assets
                (id, kind, storage_class, content_sha256, byte_length, relative_path, integrity_status, created_at)
                VALUES (?, 'sourceROM', 'source', ?, 1, 'Source/ROM/example.rom', 'verified', ?)
                """,
                arguments: [assetID, String(repeating: "a", count: 64), date]
            )
            try db.execute(
                sql: "INSERT INTO games (id, primary_title, system_family, created_at, modified_at) VALUES (?, 'Example', 'gameboy', ?, ?)",
                arguments: [gameID, date, date]
            )
            for (id, hash, sortKey) in [(release, "a", key as String?), (unversioned, "b", nil)] {
                try db.execute(
                    sql: """
                    INSERT INTO builds
                    (id, game_id, system, display_name, rom_asset_id, rom_sha256, source_kind, is_base,
                     version_sort_key, created_at, modified_at)
                    VALUES (?, ?, 'gb', 'Example', ?, ?, 'importedROM', 0, ?, ?, ?)
                    """,
                    arguments: [PersistenceCodec.uuid(id), gameID, assetID, String(repeating: hash, count: 64), sortKey, date, date]
                )
            }
        }

        try database.migrate()
        let builds = database.makeRepositories().builds
        #expect(try builds.fetchBuild(id: release)?.versionSortKey == key + "~")
        #expect(try builds.fetchBuild(id: unversioned)?.versionSortKey == nil)
        // A beta of the same version now sorts before the release imported earlier.
        #expect(key + "-beta" < key + "~")
    }

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
        #expect(game.aliases.isEmpty)
        #expect(game.hasPlayerTitle, "preexisting titles have no recorded provenance")
        #expect(!game.isFavorite)
        let builds = try repositories.builds.fetchBuilds(gameID: gameID)
        #expect(builds.map(\.id) == [buildID, patchedID])
        #expect(builds.allSatisfy { $0.notes.isEmpty && $0.totalPlaytimeSeconds == 0 })
        #expect(builds.allSatisfy { $0.baseTitle == nil && $0.hackTitle == nil && $0.author == nil && $0.translation == nil && $0.status == nil })
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
        let violations = try database.writer.read { db in try Row.fetchAll(db, sql: "PRAGMA foreign_key_check") }
        #expect(violations.isEmpty)
    }
}

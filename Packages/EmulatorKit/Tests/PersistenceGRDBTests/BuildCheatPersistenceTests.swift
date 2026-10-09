import AssetStorage
import EmulatorApplication
import EmulatorDomain
import Foundation
import GRDB
@testable import PersistenceGRDB
import Testing

@Suite("Build cheats in GRDB")
struct BuildCheatPersistenceTests {
    private static let now = Date(timeIntervalSince1970: 1_700_000_500)

    /// Accepts anything shaped like a GameShark code, so these tests don't need a core.
    static func isValid(_ code: String) -> Bool { code.count == 8 && code.allSatisfy(\.isHexDigit) }

    @Test("v18 adds cheats and a Cheats On switch without changing populated v17 tables", arguments: [false, true])
    func upgrade(deleted: Bool) throws {
        let database = try AppDatabase.inMemory()
        try AppDatabase.migrator.migrate(database.writer, upTo: "v1-v17-manual-order")
        let fixture = try legacyFixture(in: database, includingDeletedRecords: deleted)
        let before = try database.writer.read { db in
            let tables = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'grdb_migrations'")
            return try tables.map { table in
                let columns = try db.columns(in: table).map(\.name).joined(separator: ", ")
                return (table, columns, try Row.fetchAll(db, sql: "SELECT \(columns) FROM \(table) ORDER BY rowid"))
            }
        }
        #expect(before.contains { $0.0 == "builds" && !$0.2.isEmpty })
        try database.migrate()
        try database.writer.read { db throws -> Void in
            for (table, columns, rows) in before {
                #expect(try Row.fetchAll(db, sql: "SELECT \(columns) FROM \(table) ORDER BY rowid") == rows)
            }
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM build_cheats") == 0)
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM builds WHERE cheats_enabled != 1") == 0)
            #expect(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
            #expect(try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations").contains("v1-v18-build-cheats"))
        }
        let repositories = database.makeRepositories()
        #expect(try repositories.builds.fetchBuild(id: fixture.build.id)?.cheatsEnabled == true)
        let cheat = try operations(repositories).add(buildID: fixture.build.id, name: "Moon Garden Lives",
            codes: "010900C0", isValid: Self.isValid)
        #expect(try repositories.cheats.fetchCheats(buildID: fixture.build.id) == [cheat])
    }

    @Test("cheats keep their order, codes and switches after reopening")
    func orderSurvivesReopening() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.sqlite")
        let database = try AppDatabase(url: url)
        try database.migrate()
        let repositories = database.makeRepositories()
        let fixture = try Fixture.create(in: repositories)
        let operations = operations(repositories)
        let first = try operations.add(buildID: fixture.build.id, name: "First", codes: "010100C0", isValid: Self.isValid)
        let second = try operations.add(buildID: fixture.build.id, name: "Second", codes: "010200C0\n\n  010300c0 ", isValid: Self.isValid)
        let third = try operations.add(buildID: fixture.build.id, name: "Third", codes: "010400C0", isValid: Self.isValid)
        try operations.reorder(buildID: fixture.build.id, orderedIDs: [third.id, first.id, second.id])
        try operations.setEnabled(cheatID: first.id, false)
        try operations.setCheatsEnabled(buildID: fixture.build.id, enabled: false)
        try operations.delete(cheatID: third.id)

        let reopened = try AppDatabase(url: url)
        try reopened.migrate()
        let cheats = try reopened.makeRepositories().cheats.fetchCheats(buildID: fixture.build.id)
        #expect(cheats.map(\.id) == [first.id, second.id])
        #expect(cheats.map(\.position) == [0, 1])
        #expect(cheats.map(\.isEnabled) == [false, true])
        #expect(cheats[1].codes == ["010200C0", "010300C0"])
        #expect(try reopened.makeRepositories().builds.fetchBuild(id: fixture.build.id)?.cheatsEnabled == false)
        #expect(try reopened.makeRepositories().cheats.fetchCheats(buildID: fixture.patchedBuild.id).isEmpty)
    }

    @Test("a bad line saves nothing and names the line; a missing name saves nothing")
    func refusedEntries() throws {
        let database = try AppDatabase.inMemory()
        try database.migrate()
        let repositories = database.makeRepositories()
        let fixture = try Fixture.create(in: repositories)
        let operations = operations(repositories)
        #expect(throws: BuildCheatError.unreadableLine(3)) {
            try operations.add(buildID: fixture.build.id, name: "Jane's", codes: "010100C0\n\nNOPE", isValid: Self.isValid)
        }
        #expect(throws: BuildCheatError.missingName) {
            try operations.add(buildID: fixture.build.id, name: "  ", codes: "010100C0", isValid: Self.isValid)
        }
        #expect(throws: BuildCheatError.noCodes) {
            try operations.add(buildID: fixture.build.id, name: "Empty", codes: " \n ", isValid: Self.isValid)
        }
        #expect(BuildCheatError.unreadableLine(2).localizedDescription == "Line 2 isn’t a Game Genie or GameShark code.")
        let saved = try operations.add(buildID: fixture.build.id, name: "Jane's", codes: "010100C0", isValid: Self.isValid)
        #expect(throws: BuildCheatError.unreadableLine(1)) {
            try operations.edit(cheatID: saved.id, name: "Renamed", codes: "BAD", isValid: Self.isValid)
        }
        #expect(try repositories.cheats.fetchCheats(buildID: fixture.build.id) == [saved])
    }

    @Test("a stale metadata write keeps the Cheats On switch")
    func metadataWriteKeepsSwitch() throws {
        let database = try AppDatabase.inMemory()
        try database.migrate()
        let repositories = database.makeRepositories()
        let fixture = try Fixture.create(in: repositories)
        let stale = try #require(try repositories.builds.fetchBuild(id: fixture.build.id))
        try repositories.builds.setCheatsEnabled(buildID: fixture.build.id, enabled: false)
        var renamed = stale
        renamed.notes = "Moon Garden route"
        try repositories.builds.updateBuildMetadata(renamed)
        let current = try #require(try repositories.builds.fetchBuild(id: fixture.build.id))
        #expect(current.notes == "Moon Garden route")
        #expect(!current.cheatsEnabled)
    }

    @Test("Recently Deleted hides and restores a Build's cheats, and purging removes them")
    func deletionLifecycle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try AppDatabase.inMemory()
        try database.migrate()
        let repositories = database.makeRepositories()
        let fixture = try Fixture.create(in: repositories)
        let cheat = try operations(repositories).add(buildID: fixture.patchedBuild.id, name: "Moon Garden",
            codes: "010100C0", isValid: Self.isValid)
        let deletion = deletionOperations(repositories, store: try ManagedFileStore(rootURL: root))
        let deleted = try deletion.delete(try deletion.planBuildDeletion(buildID: fixture.patchedBuild.id))
        #expect(try repositories.cheats.fetchCheats(buildID: fixture.patchedBuild.id).isEmpty)
        #expect(try repositories.cheats.fetchCheat(id: cheat.id) == nil)
        #expect(throws: BuildOperationError.buildNotFound(fixture.patchedBuild.id)) {
            try repositories.cheats.insertCheat(BuildCheat(id: UUID(), buildID: fixture.patchedBuild.id, name: "Late",
                codes: ["010100C0"], position: 1, createdAt: Self.now, modifiedAt: Self.now))
        }
        #expect(throws: BuildCheatError.cheatNotFound(cheat.id)) { try repositories.cheats.updateCheat(cheat) }
        try deletion.restore(deletionID: deleted.id)
        #expect(try repositories.cheats.fetchCheats(buildID: fixture.patchedBuild.id) == [cheat])

        // A whole Game hides them too.
        let game = try deletion.delete(try deletion.planGameDeletion(gameID: fixture.game.id))
        #expect(try repositories.cheats.fetchCheats(buildID: fixture.patchedBuild.id).isEmpty)
        try deletion.restore(deletionID: game.id)
        #expect(try repositories.cheats.fetchCheats(buildID: fixture.patchedBuild.id) == [cheat])

        let again = try deletion.delete(try deletion.planBuildDeletion(buildID: fixture.patchedBuild.id))
        try deletion.purge(deletionID: again.id)
        #expect(try database.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM build_cheats") } == 0)
        #expect(try repositories.deletions.fetchTombstones().contains { $0.recordID == fixture.patchedBuild.id })
    }

    @Test("copying a Build copies its cheats, moving keeps them", arguments: [ReorganizationMode.copy, .move])
    func copyAndMove(mode: ReorganizationMode) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try AppDatabase.inMemory()
        try database.migrate()
        let repositories = database.makeRepositories()
        let fixture = try Fixture.create(in: repositories)
        let cheats = operations(repositories)
        let first = try cheats.add(buildID: fixture.build.id, name: "First", codes: "010100C0", isValid: Self.isValid)
        let second = try cheats.add(buildID: fixture.build.id, name: "Second", codes: "010200C0\n010300C0", isValid: Self.isValid)
        try cheats.setEnabled(cheatID: first.id, false)
        try cheats.setCheatsEnabled(buildID: fixture.build.id, enabled: false)
        let source = try repositories.cheats.fetchCheats(buildID: fixture.build.id)
        let builds = BuildOperations(games: repositories.games, builds: repositories.builds,
            profiles: repositories.saveProfiles, states: repositories.saveStates, recipes: repositories.patchRecipes,
            cheats: repositories.cheats, assets: repositories.assets, assetStore: try ManagedFileStore(rootURL: root),
            transactions: repositories.transactions, now: { Self.now })
        let game = try builds.promoteBuild(buildID: fixture.build.id, title: "Jane's Moon Garden", mode: mode)
        let promoted = try #require(try repositories.builds.fetchBuilds(gameID: game.id).first)
        let copied = try repositories.cheats.fetchCheats(buildID: promoted.id)
        #expect(!promoted.cheatsEnabled)
        #expect(copied.map(\.name) == ["First", "Second"])
        #expect(copied.map(\.codes) == source.map(\.codes))
        #expect(copied.map(\.isEnabled) == [false, true])
        #expect(copied.map(\.position) == [0, 1])
        switch mode {
        case .copy:
            #expect(Set(copied.map(\.id)).isDisjoint(with: [first.id, second.id]))
            #expect(try repositories.cheats.fetchCheats(buildID: fixture.build.id) == source)
            // Editing the copy leaves the original alone.
            try cheats.edit(cheatID: copied[1].id, name: "Changed", codes: "010900C0", isValid: Self.isValid)
            #expect(try repositories.cheats.fetchCheats(buildID: fixture.build.id) == source)
        case .move:
            #expect(promoted.id == fixture.build.id)
            #expect(copied == source)
        }
    }

    @Test("merging Games keeps moved Builds' cheats and copies them for a copy", arguments: [ReorganizationMode.copy, .move])
    func mergeGames(mode: ReorganizationMode) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = try AppDatabase.inMemory()
        try database.migrate()
        let repositories = database.makeRepositories()
        let fixture = try Fixture.create(in: repositories)
        let target = Game(id: UUID(), primaryTitle: "Target", systemFamily: "gameboy", createdAt: Self.now, modifiedAt: Self.now)
        try repositories.games.insertGame(target)
        let cheat = try operations(repositories).add(buildID: fixture.build.id, name: "Moon Garden",
            codes: "010100C0", isValid: Self.isValid)
        let builds = BuildOperations(games: repositories.games, builds: repositories.builds,
            profiles: repositories.saveProfiles, states: repositories.saveStates, recipes: repositories.patchRecipes,
            cheats: repositories.cheats, assets: repositories.assets, assetStore: try ManagedFileStore(rootURL: root),
            transactions: repositories.transactions, now: { Self.now })
        try builds.mergeGame(sourceGameID: fixture.game.id, into: target.id, mode: mode)
        let merged = try #require(try repositories.builds.fetchBuilds(gameID: target.id).first { $0.imageSHA256 == fixture.build.imageSHA256 })
        let cheats = try repositories.cheats.fetchCheats(buildID: merged.id)
        #expect(cheats.map(\.name) == ["Moon Garden"])
        #expect((cheats.first?.id == cheat.id) == (mode == .move))
    }

    private func operations(_ repositories: GRDBRepositorySet) -> BuildCheatOperations {
        BuildCheatOperations(builds: repositories.builds, cheats: repositories.cheats,
            transactions: repositories.transactions, now: { Self.now })
    }

    private func deletionOperations(_ repositories: GRDBRepositorySet, store: ManagedFileStore) -> LibraryDeletionOperations {
        LibraryDeletionOperations(games: repositories.games, builds: repositories.builds,
            profiles: repositories.saveProfiles, states: repositories.saveStates, recipes: repositories.patchRecipes,
            deletions: repositories.deletions, assetStore: store, transactions: repositories.transactions, now: { Self.now })
    }
}

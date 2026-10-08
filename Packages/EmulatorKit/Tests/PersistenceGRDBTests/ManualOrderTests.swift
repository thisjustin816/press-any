import EmulatorApplication
import EmulatorDomain
import Foundation
import GRDB
@testable import PersistenceGRDB
import Testing

@Suite("Manual library order")
struct ManualOrderTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_500)

    @Test("v17 adds manual positions without changing populated v16 tables", arguments: [false, true])
    func upgrade(deleted: Bool) throws {
        let database = try AppDatabase.inMemory()
        try AppDatabase.migrator.migrate(database.writer, upTo: "v1-v16-image-fingerprints")
        let fixture = try legacyFixture(in: database, includingDeletedRecords: deleted)
        let before = try database.writer.read { db in
            let tables = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'grdb_migrations'")
            // Later migrations may add columns, so compare the columns the table had.
            return try tables.map { table in
                let columns = try db.columns(in: table).map(\.name).joined(separator: ", ")
                return (table, columns, try Row.fetchAll(db, sql: "SELECT \(columns) FROM \(table) ORDER BY rowid"))
            }
        }
        try database.migrate()
        try database.writer.read { db throws -> Void in
            for (table, columns, rows) in before {
                #expect(try Row.fetchAll(db, sql: "SELECT \(columns) FROM \(table) ORDER BY rowid") == rows)
            }
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM game_manual_positions") == 0)
            #expect(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
            #expect(try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations").contains("v1-v17-manual-order"))
        }
        let games = database.makeRepositories().games
        #expect(try games.fetchManualPositions().isEmpty)
        try games.setManualOrder([fixture.game.id])
        #expect(try games.fetchManualPositions() == [fixture.game.id: 0])
    }

    @Test("positions save in order, survive reopening and leave new Games unplaced")
    func saveAndReload() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.sqlite")
        let database = try AppDatabase(url: url)
        try database.migrate()
        let games = database.makeRepositories().games
        let first = try insertGame("First", into: games)
        let second = try insertGame("Second", into: games)
        try games.setManualOrder([second.id, first.id])
        let later = try insertGame("Later", into: games)

        let reopened = try AppDatabase(url: url)
        try reopened.migrate()
        let positions = try reopened.makeRepositories().games.fetchManualPositions()
        #expect(positions == [second.id: 0, first.id: 1])
        #expect(positions[later.id] == nil)
    }

    @Test("a deleted Game keeps its position for restore and loses it when purged")
    func deletionKeepsPosition() throws {
        let database = try AppDatabase.inMemory()
        try database.migrate()
        let repositories = database.makeRepositories()
        let fixture = try Fixture.create(in: repositories)
        let other = try insertGame("Other", into: repositories.games)
        try repositories.games.setManualOrder([other.id, fixture.game.id])
        let deleted = LibraryDeletion(
            id: UUID(), kind: .game, title: fixture.game.primaryTitle, gameID: fixture.game.id, deletedAt: now,
            records: LibraryRecordSet(gameIDs: [fixture.game.id], buildIDs: [fixture.build.id, fixture.patchedBuild.id],
                saveProfileIDs: [fixture.profile.id], saveStateIDs: [fixture.state.id])
        )

        try repositories.deletions.insertDeletion(deleted)
        #expect(try repositories.games.fetchManualPositions() == [other.id: 0])
        #expect(throws: BuildOperationError.gameNotFound(fixture.game.id)) {
            try repositories.games.setManualOrder([other.id, fixture.game.id])
        }
        try repositories.deletions.restoreDeletion(id: deleted.id)
        #expect(try repositories.games.fetchManualPositions() == [other.id: 0, fixture.game.id: 1])

        try repositories.deletions.insertDeletion(deleted)
        _ = try repositories.deletions.purgeDeletion(id: deleted.id, at: now)
        #expect(try database.writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM game_manual_positions") } == 1)
    }

    @Test("an unknown Game saves nothing")
    func unknownGameSavesNothing() throws {
        let database = try AppDatabase.inMemory()
        try database.migrate()
        let games = database.makeRepositories().games
        let game = try insertGame("Game", into: games)
        let unknown = UUID()
        #expect(throws: BuildOperationError.gameNotFound(unknown)) { try games.setManualOrder([game.id, unknown]) }
        #expect(try games.fetchManualPositions().isEmpty)
    }

    private func insertGame(_ title: String, into games: GRDBGameRepository) throws -> Game {
        let game = Game(id: UUID(), primaryTitle: title, systemFamily: "gameBoy", createdAt: now, modifiedAt: now)
        try games.insertGame(game)
        return game
    }
}

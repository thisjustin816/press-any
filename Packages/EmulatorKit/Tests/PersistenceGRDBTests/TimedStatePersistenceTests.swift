import AssetStorage
import EmulationSession
import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import GRDB
import Importing
import Testing
@testable import PersistenceGRDB

@Suite struct TimedStatePersistenceTests {
    @Test func timedStateRoundTripsThroughDatabaseJSONAndLibraryBackup() throws {
        let library = try RestoreLibrary()
        defer { library.remove() }
        let profile = try library.addProfile(bytes: Data([1]))
        let worker = SessionWorker(core: FakeEmulatorCore())
        let service = SaveStateService(states: library.repos.saveStates, assets: library.repos.assets,
            assetStore: library.store, transactions: library.repos.transactions,
            now: { Date(timeIntervalSince1970: 1_700_000_100) })
        let state = try service.save(worker: worker,
            context: LaunchContext(gameID: library.rom.game.id, buildID: library.rom.build.id, saveProfileID: profile.id),
            kind: .auto, isTimed: true, playtimeSeconds: 60)
        #expect(try library.repos.saveStates.fetchSaveState(id: state.id) == state)
        #expect(try JSONDecoder().decode(SaveState.self, from: JSONEncoder().encode(state)) == state)
        try library.repos.saveStates.renameSaveState(id: state.id, label: "Boss")
        var expected = try #require(try library.repos.saveStates.fetchSaveState(id: state.id))
        expected.isPinned = true
        try library.repos.saveStates.updateSaveState(expected)
        #expect(expected.timingNote == "Timed")

        let archive = try library.export(includeROMs: true)
        let destination = try AppDatabase.inMemory()
        try destination.migrate()
        let repos = destination.makeRepositories()
        let store = try ManagedFileStore(rootURL: library.root.appendingPathComponent("Restored"))
        let backup = LibraryBackupService(repository: repos.backup, assetStore: store)
        let prepared = try backup.prepare(from: archive)
        #expect(prepared.snapshot.states == [expected])
        _ = try backup.restore(prepared, review: backup.review(prepared), choices: [:])
        let restored = try #require(try repos.saveStates.fetchSaveState(id: state.id))
        #expect(restored == expected)
        #expect(restored.displayName == "Boss")
        #expect(restored.kindName == "Auto State")
        #expect(restored.timingNote == "Timed")
        let asset = try #require(try repos.assets.fetchAsset(id: restored.stateAssetID))
        #expect(try store.readData(at: store.managedURL(relativePath: asset.relativePath)) == worker.perform { try $0.serializeState() })
    }

    @Test func upgradePreservesExistingStatesAndDefaultsTimedOriginToFalse() throws {
        let db = try AppDatabase.inMemory()
        try AppDatabase.migrator.migrate(db.writer, upTo: "v1-v18-build-cheats")
        let fixture = try legacyFixture(in: db)
        let before = try db.writer.read { db in
            let columns = try db.columns(in: "save_states").map(\.name)
            return (columns, try Row.fetchAll(db, sql: "SELECT * FROM save_states ORDER BY id"))
        }
        try db.migrate()
        try db.writer.read { db throws -> Void in
            #expect(try Row.fetchAll(db, sql: "SELECT \(before.0.joined(separator: ",")) FROM save_states ORDER BY id") == before.1)
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM save_states WHERE is_timed != 0") == 0)
        }
        #expect(try db.makeRepositories().saveStates.fetchSaveState(id: fixture.state.id) == fixture.state)
    }
}

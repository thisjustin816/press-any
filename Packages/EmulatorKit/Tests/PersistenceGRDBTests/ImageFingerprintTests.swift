import EmulatorApplication
import EmulatorDomain
import Foundation
import GRDB
import Testing
@testable import PersistenceGRDB

@Suite("Image fingerprint persistence")
struct ImageFingerprintTests {
    private func fingerprint(_ sha256: String) -> ImageFingerprint {
        .init(imageSHA256: sha256, bankSize: 0x4000, bankHashes: [0, UInt64.max, 0x1122334455667788, 0x1122334455667788],
            headerTitle: "MOON GARDEN", cartridgeType: 0x1b, ramSizeCode: 3, cgbFlag: 0x80)
    }

    @Test("v16 adds fingerprints without changing populated v15 tables", arguments: [false, true])
    func upgrade(deleted: Bool) throws {
        let database = try AppDatabase.inMemory()
        try AppDatabase.migrator.migrate(database.writer, upTo: "v1-v15-save-state-slots")
        _ = try legacyFixture(in: database, includingDeletedRecords: deleted)
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
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM image_fingerprints") == 0)
            #expect(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
            #expect(try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations").contains("v1-v16-image-fingerprints"))
        }
    }

    @Test("bulk read round-trips 64-bit hashes, stored headers and replacement")
    func roundTrip() throws {
        let database = try AppDatabase.inMemory()
        try database.migrate()
        let repositories = database.makeRepositories()
        let repository = repositories.fingerprints
        for sha256 in ["a", "b"] {
            try repositories.assets.insertAsset(.init(id: UUID(), kind: .sourceImage, storageClass: .source,
                contentSHA256: sha256, byteLength: 0x8000, relativePath: "Source/ROM/\(sha256).rom",
                integrityStatus: .verified, createdAt: .now))
        }
        let first = fingerprint("a")
        try repository.saveFingerprint(first)
        #expect(try database.writer.read { db in
            try String.fetchOne(db, sql: "SELECT hex(bank_hashes) FROM image_fingerprints WHERE image_sha256 = 'a'")
        } == "0000000000000000FFFFFFFFFFFFFFFF88776655443322118877665544332211")
        try repository.saveFingerprint(fingerprint("b"))
        #expect(try repository.fetchFingerprints(imageSHA256s: ["a", "missing"]) == ["a": first])
        #expect(try repository.fetchFingerprints(imageSHA256s: []).isEmpty)
        let empty = ImageFingerprint(imageSHA256: "a", bankSize: 0x4000, bankHashes: [], headerTitle: "NEW",
            cartridgeType: 0, ramSizeCode: 0, cgbFlag: 0)
        try repository.saveFingerprint(empty)
        #expect(try repository.fetchFingerprints(imageSHA256s: ["a"])["a"] == empty)
        try repository.deleteFingerprint(imageSHA256: "a")
        #expect(try repository.fetchFingerprints(imageSHA256s: ["a"]).isEmpty)
    }

    @Test("Recently Deleted retains fingerprints and purging source images removes them")
    func purge() throws {
        let database = try AppDatabase.inMemory()
        try database.migrate()
        let repositories = database.makeRepositories()
        let fixture = try Fixture.create(in: repositories)
        let row = fingerprint(fixture.build.imageSHA256)
        try repositories.fingerprints.saveFingerprint(row)
        let deletion = LibraryDeletion(id: UUID(), kind: .game, title: fixture.game.primaryTitle, gameID: fixture.game.id,
            deletedAt: .now, records: LibraryRecordSet(gameIDs: [fixture.game.id], buildIDs: [fixture.build.id, fixture.patchedBuild.id],
                saveProfileIDs: [fixture.profile.id], saveStateIDs: [fixture.state.id]))
        try repositories.deletions.insertDeletion(deletion)
        #expect(try repositories.fingerprints.fetchFingerprints(imageSHA256s: [row.imageSHA256])[row.imageSHA256] == row)
        _ = try repositories.deletions.purgeDeletion(id: deletion.id, at: .now)
        #expect(try repositories.assets.fetchAsset(id: fixture.build.imageAssetID) == nil)
        #expect(try repositories.fingerprints.fetchFingerprints(imageSHA256s: [row.imageSHA256]).isEmpty)
        try repositories.fingerprints.saveFingerprint(row)
        #expect(try repositories.fingerprints.fetchFingerprints(imageSHA256s: [row.imageSHA256]).isEmpty,
            "a backfill finishing after purge cannot recreate the row")
    }
}

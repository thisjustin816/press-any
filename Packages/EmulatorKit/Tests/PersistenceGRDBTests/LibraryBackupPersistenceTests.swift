import AssetStorage
import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import GRDB
import Importing
import Testing
@testable import PersistenceGRDB

@Suite struct LibraryBackupPersistenceTests {
    @Test func everyTableAndRepositoryHasAnExplicitDecision() throws {
        let db = try database()
        let tables = try db.writer.read { try String.fetchAll($0, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'") }
        try requireDecisions(Set(tables), decisions: Set(BackupCoverage.tables.keys))
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let ports = package.appendingPathComponent("Sources/EmulatorApplication/Ports")
        let files = try FileManager.default.contentsOfDirectory(at: ports, includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }
        let text = try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
        let protocols = protocolNames(in: text)
        #expect(protocols.count >= 18)
        try requireDecisions(protocols, decisions: Set(BackupCoverage.ports.keys))
        #expect(throws: CoverageError.self) { try requireDecisions(protocolNames(in: text + "\npublic protocol NewDataRepository: Sendable {}"), decisions: Set(BackupCoverage.ports.keys)) }
        try requireColumnDecisions(db)
        try db.writer.write { try $0.execute(sql: "CREATE TABLE new_library_data (id INTEGER PRIMARY KEY)") }
        let withNewTable = try db.writer.read { try String.fetchAll($0, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'") }
        #expect(throws: CoverageError.self) { try requireDecisions(Set(withNewTable), decisions: Set(BackupCoverage.tables.keys)) }
        try db.writer.write { try $0.execute(sql: "DROP TABLE new_library_data") }
        try db.writer.write { try $0.execute(sql: "ALTER TABLE save_profiles ADD COLUMN favorite_color TEXT") }
        #expect(throws: CoverageError.self) { try requireColumnDecisions(db) }
    }

    @Test func exactSnapshotPersistsWithoutPlayerOverridesAndRollsBackFinalFailure() throws {
        let db = try database(), repos = db.makeRepositories()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let game = Game(id: UUID(), primaryTitle: "Example", systemFamily: "gameboy", aliases: ["Alias"], isFavorite: true, createdAt: date, modifiedAt: date)
        var snapshot = LibraryBackupSnapshot()
        snapshot.games = [game]
        snapshot.manualPositions = [BackupManualPosition(gameID: game.id, position: 3)]
        snapshot.gameProvenance = [BackupProvenance(ownerID: game.id, values: [MetadataProvenance(field: .title, source: .filename, providedValue: "Example", recordedAt: date)])]
        snapshot.settings = [BackupSetting(scopeType: "app", scopeID: "app", key: "releasePreference", valueJSON: "{}")]
        let input = snapshot
        let report = RestoreReport(restoredAt: date, added: 1)
        _ = try repos.backup.commitSnapshot(replacingLibrary: false) { _ in (input, report, true) }
        let actual = try repos.backup.readSnapshot { $0 }
        #expect(actual.games == [game])
        #expect(actual.manualPositions == input.manualPositions)
        #expect(try repos.games.fetchManualPositions() == [game.id: 3])
        #expect(actual.gameProvenance == input.gameProvenance)
        #expect(actual.settings == input.settings)
        #expect(try repos.backup.lastRestoreReport() == report)
        #expect(actual.migrationID == "v1-v17-manual-order")
        try db.writer.write { try $0.execute(sql: """
            CREATE TRIGGER fail_restore BEFORE INSERT ON settings_overrides
            WHEN NEW.key = 'backup.lastRestoreReport'
            BEGIN SELECT RAISE(ABORT, 'restore failure'); END;
            """) }
        #expect(throws: (any Error).self) {
            try repos.backup.commitSnapshot(replacingLibrary: true) { _ in
                var changed = input
                changed.games[0].primaryTitle = "Replaced"
                return (changed, RestoreReport(restoredAt: date, added: 99), true)
            }
        }
        #expect(try repos.backup.readSnapshot { $0 } == actual)
        #expect(try repos.backup.lastRestoreReport() == report)
    }

    @Test func missingROMRestoresAndExactDuplicateImportRepairsItsFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceStore = try ManagedFileStore(rootURL: root.appendingPathComponent("SourceLibrary"))
        let sourceDB = try database(), sourceRepos = sourceDB.makeRepositories()
        let rom = TestROM.make(title: "BACKUP")
        let picked = root.appendingPathComponent("Example.gb")
        try rom.write(to: picked)
        let original = try imported(url: picked, repositories: sourceRepos, store: sourceStore)
        let exportService = LibraryBackupService(repository: sourceRepos.backup, assetStore: sourceStore)
        let archive = try exportService.export(to: root, displayName: "Test", appVersion: "1", appBuild: "1")
        let destinationStore = try ManagedFileStore(rootURL: root.appendingPathComponent("Destination"))
        let destinationDB = try database(), destinationRepos = destinationDB.makeRepositories()
        let service = LibraryBackupService(repository: destinationRepos.backup, assetStore: destinationStore)
        let prepared = try service.prepare(from: archive)
        let report = try service.restore(prepared, review: service.review(prepared), choices: [:])
        #expect(report.missingROMs.map(\.id) == [original.build.id])
        let restored = try #require(try destinationRepos.builds.fetchBuild(id: original.build.id))
        #expect(restored.imageSHA256 == original.build.imageSHA256)
        let asset = try #require(try destinationRepos.assets.fetchAsset(id: restored.imageAssetID))
        let assetURL = try destinationStore.managedURL(relativePath: asset.relativePath)
        #expect(!destinationStore.fileExists(at: assetURL))
        let repaired = try imported(url: picked, repositories: destinationRepos, store: destinationStore)
        #expect(!repaired.createdNewBuild)
        #expect(repaired.build.id == original.build.id)
        #expect(try destinationStore.readData(at: destinationStore.managedURL(relativePath: asset.relativePath)) == rom)
    }

    @Test func failedRestoreRemovesPlacedFilesAndPreservesDatabase() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ManagedFileStore(rootURL: root.appendingPathComponent("source"))
        let db = try database(), repositories = db.makeRepositories()
        let picked = root.appendingPathComponent("Example.gb")
        try TestROM.make(title: "BACKUP").write(to: picked)
        _ = try imported(url: picked, repositories: repositories, store: store)
        let service = LibraryBackupService(repository: repositories.backup, assetStore: store)
        let url = try service.export(to: root, displayName: "Test", appVersion: "1", appBuild: "1", includeROMs: true)
        let destinationDB = try database(), destinationRepos = destinationDB.makeRepositories()
        let destinationStore = try ManagedFileStore(rootURL: root.appendingPathComponent("destination"))
        let restore = LibraryBackupService(repository: destinationRepos.backup, assetStore: destinationStore)
        let prepared = try restore.prepare(from: url)
        try destinationDB.writer.write { try $0.execute(sql: """
            CREATE TRIGGER fail_restore BEFORE INSERT ON settings_overrides
            WHEN NEW.key = 'backup.lastRestoreReport' BEGIN SELECT RAISE(ABORT, 'failure'); END;
            """) }
        #expect(throws: (any Error).self) { try restore.restore(prepared, review: restore.review(prepared), choices: [:]) }
        #expect(try destinationRepos.games.fetchGames().isEmpty)
        #expect(try destinationRepos.assets.fetchAssets().isEmpty)
        #expect(try destinationRepos.backup.lastRestoreReport() == nil)
        for asset in prepared.snapshot.assets {
            let assetURL = try destinationStore.managedURL(relativePath: asset.relativePath)
            #expect(!destinationStore.fileExists(at: assetURL))
        }
    }

    @Test func snapshotUsesOneReadTransactionAndExcludesOperationalSettings() throws {
        let db = try database(), repos = db.makeRepositories()
        try repos.settings.setValueJSON("true", key: "skipBootAnimation", scope: .app)
        try repos.settings.setValueJSON("{}", key: "session.launchMarker", scope: .app)
        try repos.settings.setValueJSON("1", key: "noIntro.appliedVersion", scope: .system(.gameBoy))
        let keys = try repos.backup.readSnapshot { snapshot in
            #expect(GRDBTransactionContext.current != nil)
            #expect(GRDBTransactionContext.current?.isInsideTransaction == true)
            let stored = try repos.settings.valueJSON(key: "skipBootAnimation", scope: .app)
            #expect(stored == "true")
            return snapshot.settings.map(\.key)
        }
        #expect(keys == ["skipBootAnimation"])
    }

    @Test func deletedCopyLineageIsOmittedFromBackupAndPreservedByMerge() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try database(), repos = db.makeRepositories()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let game = Game(id: UUID(), primaryTitle: "Example", systemFamily: "gameboy", createdAt: date, modifiedAt: date)
        let original = SaveProfile(id: UUID(), gameID: game.id, displayName: "Original", createdAt: date, modifiedAt: date)
        let copy = SaveProfile(id: UUID(), gameID: game.id, displayName: "Copy", copiedFromProfileID: original.id, createdAt: date, modifiedAt: date)
        try repos.games.insertGame(game)
        try repos.saveProfiles.insertSaveProfile(original)
        try repos.saveProfiles.insertSaveProfile(copy)
        let deletion = LibraryDeletion(id: UUID(), kind: .saveProfile, title: original.displayName, gameID: game.id,
            deletedAt: date, records: LibraryRecordSet(saveProfileIDs: [original.id]))
        try repos.deletions.insertDeletion(deletion)
        let store = try ManagedFileStore(rootURL: root.appendingPathComponent("Library"))
        let service = LibraryBackupService(repository: repos.backup, assetStore: store)
        let url = try service.export(to: root, displayName: "Test", appVersion: "1", appBuild: "1")
        let prepared = try service.prepare(from: url)
        #expect(prepared.snapshot.profiles.map(\.id) == [copy.id])
        #expect(prepared.snapshot.profiles.first?.copiedFromProfileID == nil)
        let review = try service.review(prepared)
        let choices = Dictionary(uniqueKeysWithValues: review.conflicts.map { ($0.id, RestoreChoice.library) })
        _ = try service.restore(prepared, review: review, choices: choices)
        #expect(try repos.saveProfiles.fetchSaveProfile(id: copy.id)?.copiedFromProfileID == original.id)
        #expect(try repos.deletions.fetchDeletions() == [deletion])
    }

    private func database() throws -> AppDatabase {
        let db = try AppDatabase.inMemory()
        try db.migrate()
        return db
    }

    private func imported(url: URL, repositories: GRDBRepositorySet, store: ManagedFileStore) throws -> ROMImportResult {
        let analyzer = ROMImportAnalyzer(builds: repositories.builds, games: repositories.games, fingerprints: repositories.fingerprints, toolchainReports: repositories.toolchainReports, assetStore: store)
        let analysis = try analyzer.analyzeROM(at: url, targetGameID: nil)
        let committer = ImportCommitter(games: repositories.games, builds: repositories.builds,
            assets: repositories.assets, toolchainReports: repositories.toolchainReports, fingerprints: repositories.fingerprints,
            assetStore: store, transactions: repositories.transactions)
        let disposition: ROMImportDisposition = analysis.exactExistingBuildID.map { ROMImportDisposition.duplicateExisting(buildID: $0) } ?? .createGame(title: "Example")
        return try committer.commit(ROMImportPlan(analysis: analysis, disposition: disposition, buildDisplayName: "Base", markAsBase: true))
    }

    private func protocolNames(in text: String) -> Set<String> {
        Set(text.split(separator: "\n").filter { $0.hasPrefix("public protocol ") }.compactMap { line in
            line.split(separator: " ").dropFirst(2).first.map { String($0).split(separator: ":").first.map(String.init) ?? "" }
        })
    }

    private func requireColumnDecisions(_ db: AppDatabase) throws {
        let tables = try db.writer.read { try String.fetchAll($0, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'") }
        try requireDecisions(Set(tables), decisions: Set(BackupCoverage.columns.keys))
        for table in tables {
            let columns = try db.writer.read { db in
                try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))").map { $0["name"] as String }
            }
            try requireDecisions(Set(columns.map { "\(table).\($0)" }),
                decisions: Set((BackupCoverage.columns[table] ?? []).map { "\(table).\($0)" }))
        }
    }

    private func requireDecisions(_ names: Set<String>, decisions: Set<String>) throws {
        let missing = names.subtracting(decisions)
        if !missing.isEmpty { throw CoverageError.missing(missing.sorted()) }
    }
    private enum CoverageError: Error { case missing([String]) }
}

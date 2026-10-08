import AssetStorage
import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import GRDB
import Importing
import Testing
@testable import PersistenceGRDB

/// Backups of a real database, where cascades, Recently Deleted and tombstones apply to cheats.
@Suite struct CheatBackupTests {
    @Test func cheatsRoundTripIntoAnEmptyLibraryWithTheirOrderAndSwitches() throws {
        let library = try RestoreLibrary()
        defer { library.remove() }
        let lives = try library.addCheat("Lives", codes: "010900C0")
        let jump = try library.addCheat("Moon Jump", codes: "010100C1\n010200C2")
        let time = try library.addCheat("Time", codes: "990-00B")
        try library.cheats.reorder(buildID: library.rom.build.id, orderedIDs: [time.id, lives.id, jump.id])
        try library.cheats.setEnabled(cheatID: jump.id, false)
        try library.cheats.setCheatsEnabled(buildID: library.rom.build.id, enabled: false)
        let expected = try library.repos.cheats.fetchCheats(buildID: library.rom.build.id)
        let archive = try library.export(includeROMs: true)

        let destination = try EmptyLibrary(root: library.root)
        let prepared = try destination.service.prepare(from: archive)
        #expect(prepared.manifest.recordCounts["cheats"] == 3)
        let review = try destination.service.review(prepared)
        #expect(review.conflicts.isEmpty)
        let report = try destination.service.restore(prepared, review: review, choices: [:])
        #expect(report.missingROMs.isEmpty)
        let restored = try destination.repos.cheats.fetchCheats(buildID: library.rom.build.id)
        #expect(restored == expected)
        #expect(restored.map(\.name) == ["Time", "Lives", "Moon Jump"])
        #expect(restored.map(\.isEnabled) == [true, true, false])
        #expect(restored.first { $0.id == jump.id }?.codes == ["010100C1", "010200C2"])
        #expect(try destination.repos.builds.fetchBuild(id: library.rom.build.id)?.cheatsEnabled == false)

        // Restoring the same backup again changes nothing.
        let again = try destination.service.review(destination.service.prepare(from: archive))
        #expect(again.added == 0)
        #expect(again.conflicts.isEmpty)
    }

    @Test func aBuildInRecentlyDeletedStillBacksUpAndGetsItsCheatsBackWhenRestored() throws {
        let library = try RestoreLibrary()
        defer { library.remove() }
        let other = try library.importBuild(TestROM.make(title: "MOONGARDEN", payloadByte: 1), name: "Jane's Hack")
        let kept = try library.addCheat("Kept", codes: "010900C0")
        let hidden = try library.addCheat("Hidden", codes: "010100C1", buildID: other.build.id)
        let before = try library.export()

        let deletion = try library.deletion.delete(try library.deletion.planBuildDeletion(buildID: other.build.id))
        let during = try library.service.prepare(from: library.export())
        #expect(during.snapshot.cheats.map(\.id) == [kept.id])
        #expect(!during.snapshot.builds.contains { $0.id == other.build.id })

        // The older backup can't bring the deleted Build or its cheat back.
        let older = try library.service.prepare(from: before)
        let review = try library.service.review(older)
        #expect(Set(review.leftAlone) == ["Jane's Hack (Build)", "Hidden (Cheat)"])
        #expect(review.conflicts.isEmpty)
        _ = try library.service.restore(older, review: review, choices: [:])
        #expect(try library.repos.cheats.fetchCheats(buildID: other.build.id).isEmpty)

        try library.deletion.restore(deletionID: deletion.id)
        #expect(try library.repos.cheats.fetchCheats(buildID: other.build.id) == [hidden])
        let after = try library.service.prepare(from: library.export())
        #expect(Set(after.snapshot.cheats.map(\.id)) == [kept.id, hidden.id])
    }

    @Test func purgingABuildRemovesItsCheatsAndAnOlderBackupLeavesThemAlone() throws {
        let library = try RestoreLibrary()
        defer { library.remove() }
        let other = try library.importBuild(TestROM.make(title: "MOONGARDEN", payloadByte: 1), name: "Jane's Hack")
        let kept = try library.addCheat("Kept", codes: "010900C0")
        _ = try library.addCheat("Purged", codes: "010100C1", buildID: other.build.id)
        let before = try library.export()

        let deletion = try library.deletion.delete(try library.deletion.planBuildDeletion(buildID: other.build.id))
        try library.deletion.purge(deletionID: deletion.id)
        #expect(try library.cheatRows() == 1)

        let older = try library.service.prepare(from: before)
        let review = try library.service.review(older)
        #expect(Set(review.leftAlone) == ["Jane's Hack (Build)", "Purged (Cheat)"])
        let report = try library.service.restore(older, review: review, choices: [:])
        #expect(report.notCarriedOver.contains { $0.hasPrefix("2 items in Recently Deleted or deleted for good were left alone") })
        #expect(try library.cheatRows() == 1)
        #expect(try library.repos.cheats.fetchCheats(buildID: library.rom.build.id) == [kept])
        #expect(try library.repos.builds.fetchBuild(id: other.build.id) == nil)
    }

    @Test(arguments: [RestoreChoice.library, .archive])
    func aCheatBothSidesChangedIsAConflictAndIdenticalOnesAreSkipped(_ choice: RestoreChoice) throws {
        let library = try RestoreLibrary()
        defer { library.remove() }
        let changed = try library.addCheat("Lives", codes: "010900C0")
        let same = try library.addCheat("Same", codes: "010100C1")
        try library.cheats.setEnabled(cheatID: changed.id, false)
        let backedUp = try #require(try library.repos.cheats.fetchCheat(id: changed.id))
        let archive = try library.export()
        let edited = try library.cheats.edit(cheatID: changed.id, name: "Infinite Lives", codes: "019900C0",
            isValid: CheatBackupTests.isValid)
        try library.cheats.setEnabled(cheatID: changed.id, true)
        let current = try #require(try library.repos.cheats.fetchCheat(id: changed.id))
        #expect(edited.name == current.name)

        let prepared = try library.service.prepare(from: archive)
        let review = try library.service.review(prepared)
        let conflicts = review.conflicts.filter { $0.kind == "Cheat" }
        #expect(conflicts.map(\.id) == ["Cheat/\(changed.id.uuidString)"])
        #expect(conflicts.first?.name == "Lives for Base")
        #expect(conflicts.first?.suggestedChoice == .library)
        #expect(conflicts.first?.allowsKeepBoth == false)
        #expect(review.added == 0)
        #expect(throws: LibraryBackupError.unresolvedConflict("Lives for Base")) {
            try library.service.restore(prepared, review: review, choices: [:])
        }
        #expect(throws: LibraryBackupError.unsafeChoice("Lives for Base")) {
            try library.service.restore(prepared, review: review, choices: [conflicts[0].id: .keepBoth])
        }
        _ = try library.service.restore(prepared, review: review, choices: [conflicts[0].id: choice])
        let cheats = try library.repos.cheats.fetchCheats(buildID: library.rom.build.id)
        #expect(cheats.count == 2)
        #expect(cheats.first { $0.id == same.id } == same)
        #expect(cheats.first { $0.id == changed.id } == (choice == .archive ? backedUp : current))
    }

    @Test func aGamePackageCarriesOnlyItsGamesCheats() throws {
        let library = try RestoreLibrary()
        defer { library.remove() }
        let own = try library.addCheat("Moon Garden Lives", codes: "010900C0")
        let otherGame = try library.importGame(TestROM.make(title: "JANE", payloadByte: 2), title: "Jane's Quest")
        _ = try library.addCheat("Jane's Lives", codes: "010100C1", buildID: otherGame.build.id)
        let package = try library.service.export(to: library.root.appendingPathComponent("Exports"), displayName: "Test",
            appVersion: "1", appBuild: "1", includeROMs: true, gameID: library.rom.game.id)

        let destination = try EmptyLibrary(root: library.root)
        let prepared = try destination.service.prepare(from: package)
        #expect(prepared.manifest.isGamePackage)
        #expect(prepared.snapshot.cheats == [own])
        #expect(prepared.manifest.recordCounts["cheats"] == 1)
        _ = try destination.service.restore(prepared, review: destination.service.review(prepared), choices: [:])
        #expect(try destination.repos.cheats.fetchCheats(buildID: library.rom.build.id) == [own])
        #expect(try destination.cheatRows() == 1)
        #expect(try destination.repos.games.fetchGames().map(\.id) == [library.rom.game.id])
    }

    @Test func replacingTheLibraryKeepsOnlyTheBackupsCheats() throws {
        let library = try RestoreLibrary()
        defer { library.remove() }
        let backedUp = try library.addCheat("Lives", codes: "010900C0")
        let archive = try library.export(includeROMs: true)
        _ = try library.addCheat("Added Later", codes: "010100C1")
        let prepared = try library.service.prepare(from: archive)
        let review = try library.service.review(prepared)
        let safety = try library.service.makeSafetyBackup(for: prepared, review: review,
            to: library.root.appendingPathComponent("Safety"), displayName: "Test", appVersion: "1", appBuild: "1")
        #expect(try library.service.prepare(from: safety).snapshot.cheats.count == 2)
        _ = try library.service.restore(prepared, review: review, choices: [:], replaceEntireLibrary: true, safetyBackupURL: safety)
        #expect(try library.repos.cheats.fetchCheats(buildID: library.rom.build.id) == [backedUp])
    }

    static func isValid(_ code: String) -> Bool { code.count >= 6 && code.allSatisfy { $0.isHexDigit || $0 == "-" } }
}

extension RestoreLibrary {
    var cheats: BuildCheatOperations {
        // Whole seconds survive the database's millisecond dates unchanged.
        BuildCheatOperations(builds: repos.builds, cheats: repos.cheats, transactions: repos.transactions,
            now: { Date(timeIntervalSince1970: 1_700_000_000) })
    }

    var deletion: LibraryDeletionOperations {
        LibraryDeletionOperations(games: repos.games, builds: repos.builds, profiles: repos.saveProfiles,
            states: repos.saveStates, recipes: repos.patchRecipes, deletions: repos.deletions, assetStore: store,
            transactions: repos.transactions)
    }

    @discardableResult
    func addCheat(_ name: String, codes: String, buildID: UUID? = nil) throws -> BuildCheat {
        try cheats.add(buildID: buildID ?? rom.build.id, name: name, codes: codes, isValid: CheatBackupTests.isValid)
    }

    func importGame(_ data: Data, title: String) throws -> ROMImportResult {
        let picked = root.appendingPathComponent("\(title).gb")
        try data.write(to: picked)
        let analyzer = ROMImportAnalyzer(builds: repos.builds, games: repos.games, fingerprints: repos.fingerprints,
            toolchainReports: repos.toolchainReports, assetStore: store)
        let committer = ImportCommitter(games: repos.games, builds: repos.builds, assets: repos.assets,
            toolchainReports: repos.toolchainReports, fingerprints: repos.fingerprints, assetStore: store, transactions: repos.transactions)
        return try committer.commit(ROMImportPlan(analysis: analyzer.analyzeROM(at: picked, targetGameID: nil),
            disposition: .createGame(title: title), buildDisplayName: "Base", markAsBase: true))
    }

    func cheatRows() throws -> Int {
        try db.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM build_cheats") } ?? 0
    }
}

/// A library with no Games, to restore into.
private struct EmptyLibrary {
    let db: AppDatabase
    let repos: GRDBRepositorySet
    let service: LibraryBackupService

    init(root: URL) throws {
        let store = try ManagedFileStore(rootURL: root.appendingPathComponent("Empty-\(UUID().uuidString)"))
        db = try AppDatabase.inMemory()
        try db.migrate()
        repos = db.makeRepositories()
        service = LibraryBackupService(repository: repos.backup, assetStore: store)
    }

    func cheatRows() throws -> Int {
        try db.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM build_cheats") } ?? 0
    }
}

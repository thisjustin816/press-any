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

/// Restores into a real database, where uniqueness, Recently Deleted and tombstones apply.
@Suite struct LibraryRestoreSafetyTests {
    @Test func choosingTheBackupSaveLetsTheNextInGameSaveSucceed() throws {
        let library = try RestoreLibrary()
        defer { library.remove() }
        let profile = try library.addProfile(bytes: Data([1, 2, 3]))
        let archive = try library.export()
        try library.saves.replacePersistentSaveData(Data([4, 5, 6]), profileID: profile.id, writtenByBuildID: nil)
        let prepared = try library.service.prepare(from: archive)
        let review = try library.service.review(prepared)
        let conflict = try #require(review.conflicts.first { $0.kind == "Save Profile" })
        _ = try library.service.restore(prepared, review: review, choices: [conflict.id: .archive])
        #expect(try library.batteryBytes(of: profile.id) == Data([1, 2, 3]))

        try library.saves.replacePersistentSaveData(Data([7, 8, 9]), profileID: profile.id, writtenByBuildID: nil)
        #expect(try library.batteryBytes(of: profile.id) == Data([7, 8, 9]))
        let copy = try #require(try library.repos.saveProfiles.fetchSaveProfiles(gameID: library.rom.game.id)
            .first { $0.displayName == "Jane before restore" })
        #expect(try library.batteryBytes(of: copy.id) == Data([4, 5, 6]))
    }

    @Test func recentlyDeletedAndPurgedRecordsAreLeftAloneAndReported() throws {
        let library = try RestoreLibrary()
        defer { library.remove() }
        let kept = try library.addProfile(bytes: Data([1]), name: "Jane")
        let deleted = try library.addProfile(bytes: Data([2]), name: "Moon Garden Run")
        let purged = try library.addProfile(bytes: Data([3]), name: "Old Run")
        let archive = try library.export()
        let deletion = LibraryDeletion(id: UUID(), kind: .saveProfile, title: deleted.displayName, gameID: library.rom.game.id,
            deletedAt: Date(), records: LibraryRecordSet(saveProfileIDs: [deleted.id]))
        try library.repos.deletions.insertDeletion(deletion)
        let purge = LibraryDeletion(id: UUID(), kind: .saveProfile, title: purged.displayName, gameID: library.rom.game.id,
            deletedAt: Date(), records: LibraryRecordSet(saveProfileIDs: [purged.id]))
        try library.repos.deletions.insertDeletion(purge)
        _ = try library.repos.deletions.purgeDeletion(id: purge.id, at: Date())

        let prepared = try library.service.prepare(from: archive)
        let review = try library.service.review(prepared)
        #expect(Set(review.leftAlone) == ["Moon Garden Run (Save Profile)", "Old Run (Save Profile)"])
        #expect(review.conflicts.isEmpty)
        let report = try library.service.restore(prepared, review: review, choices: [:])
        #expect(report.notCarriedOver.contains { $0.hasPrefix("2 items in Recently Deleted or deleted for good were left alone") })
        #expect(try library.repos.saveProfiles.fetchSaveProfiles(gameID: library.rom.game.id).map(\.id) == [kept.id])
        #expect(try library.repos.deletions.fetchDeletions().map(\.id) == [deletion.id])
    }

    @Test func aROMHeldOnlyByARecentlyDeletedBuildIsReusedOnRestore() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let other = try RestoreLibrary(root: root, name: "Other")
        let archive = try other.export(includeROMs: true)
        let library = try RestoreLibrary(root: root, name: "Library")
        try library.repos.deletions.insertDeletion(LibraryDeletion(id: UUID(), kind: .game, title: "Moon Garden",
            gameID: library.rom.game.id, deletedAt: Date(),
            records: LibraryRecordSet(gameIDs: [library.rom.game.id], buildIDs: [library.rom.build.id])))
        let prepared = try library.service.prepare(from: archive)
        let report = try library.service.restore(prepared, review: library.service.review(prepared), choices: [:])
        #expect(report.missingROMs.isEmpty)
        let restored = try #require(try library.repos.builds.fetchBuild(id: other.rom.build.id))
        #expect(restored.imageAssetID == library.rom.sourceAsset.id)
        #expect(try library.repos.assets.fetchAssets().filter { $0.kind == .sourceImage }.count == 1)
    }

    @Test func restoringABackupWithoutROMsAfterReplaceReconnectsTheROMLeftOnDisk() throws {
        let library = try RestoreLibrary()
        defer { library.remove() }
        let romPath = library.rom.sourceAsset.relativePath
        let withoutROMs = try library.export()
        let emptyDB = try AppDatabase.inMemory()
        try emptyDB.migrate()
        let emptyStore = try ManagedFileStore(rootURL: library.root.appendingPathComponent("Empty"))
        let empty = try LibraryBackupService(repository: emptyDB.makeRepositories().backup, assetStore: emptyStore)
            .export(to: library.root, displayName: "Empty", appVersion: "1", appBuild: "1")
        let replacement = try library.service.prepare(from: empty)
        let review = try library.service.review(replacement)
        let safety = try library.service.makeSafetyBackup(for: replacement, review: review,
            to: library.root.appendingPathComponent("Exports"), displayName: "Safety", appVersion: "1", appBuild: "1")
        _ = try library.service.restore(replacement, review: review, choices: [:], replaceEntireLibrary: true, safetyBackupURL: safety)
        #expect(try library.repos.assets.fetchAssets().isEmpty)

        let undo = try library.service.prepare(from: withoutROMs)
        let undoReview = try library.service.review(undo)
        #expect(undoReview.missingROMs.isEmpty)
        let report = try library.service.restore(undo, review: undoReview, choices: [:])
        #expect(report.missingROMs.isEmpty)
        let build = try #require(try library.repos.builds.fetchBuild(id: library.rom.build.id))
        #expect(try library.repos.assets.fetchAsset(id: build.imageAssetID)?.relativePath == romPath)
        let check = try ManagedAssetIntegrityChecker(assets: library.repos.assets, assetStore: library.store)
            .inspect(cleanup: .removeProvableOrphans)
        #expect(check.removedRelativePaths.isEmpty)
        #expect(library.store.fileExists(at: try library.store.managedURL(relativePath: romPath)))
    }

    @Test func aMissingSaveFileDoesNotBlockMergeAndIsRepairedFromTheBackup() throws {
        let library = try RestoreLibrary()
        defer { library.remove() }
        let profile = try library.addProfile(bytes: Data([1, 2, 3]))
        let archive = try library.export()
        let asset = try library.batteryAsset(of: profile.id)
        try library.store.removeIfExists(library.store.managedURL(relativePath: asset.relativePath))
        let prepared = try library.service.prepare(from: archive)
        let review = try library.service.review(prepared)
        #expect(review.conflicts.isEmpty)
        _ = try library.service.restore(prepared, review: review, choices: [:])
        #expect(try library.batteryBytes(of: profile.id) == Data([1, 2, 3]))
    }

    @Test func choosingTheBackupOverADamagedSaveRestoresWithoutABeforeRestoreCopy() throws {
        let library = try RestoreLibrary()
        defer { library.remove() }
        var profile = try library.addProfile(bytes: Data([1, 2, 3]))
        let archive = try library.export()
        profile.displayName = "Jane Renamed"
        try library.repos.saveProfiles.updateSaveProfile(profile)
        let asset = try library.batteryAsset(of: profile.id)
        try library.store.writeDataAtomically(Data([9, 9]), to: library.store.managedURL(relativePath: asset.relativePath))
        let prepared = try library.service.prepare(from: archive)
        let review = try library.service.review(prepared)
        let conflict = try #require(review.conflicts.first { $0.kind == "Save Profile" })
        let report = try library.service.restore(prepared, review: review, choices: [conflict.id: .archive])
        #expect(try library.batteryBytes(of: profile.id) == Data([1, 2, 3]))
        #expect(report.notCarriedOver.contains { $0.contains("missing or damaged") })
        #expect(try library.repos.saveProfiles.fetchSaveProfiles(gameID: library.rom.game.id).count == 1)
    }

    @Test func deletingTheBuildThatWroteASaveDoesNotBlockBackupOrMerge() throws {
        let library = try RestoreLibrary()
        defer { library.remove() }
        let second = try library.importBuild(TestROM.make(title: "MOONGARDEN", payloadByte: 2), name: "Moon Garden v2")
        let profile = try library.addProfile(bytes: Data([1, 2, 3]))
        #expect(profile.saveWrittenByBuildID == library.rom.build.id)
        var game = try #require(try library.repos.games.fetchGame(id: library.rom.game.id))
        game.preferredBuildID = library.rom.build.id
        try library.repos.games.updateGame(game)
        let deletion = LibraryDeletionOperations(games: library.repos.games, builds: library.repos.builds,
            profiles: library.repos.saveProfiles, states: library.repos.saveStates, recipes: library.repos.patchRecipes,
            deletions: library.repos.deletions, assetStore: library.store, transactions: library.repos.transactions)
        try deletion.delete(deletion.planBuildDeletion(buildID: library.rom.build.id))

        let archive = try library.export()
        let prepared = try library.service.prepare(from: archive)
        #expect(prepared.snapshot.builds.map(\.id) == [second.build.id])
        #expect(prepared.snapshot.profiles.first?.saveWrittenByBuildID == nil)
        #expect(prepared.snapshot.games.first?.preferredBuildID == nil)
        let review = try library.service.review(prepared)
        #expect(review.conflicts.isEmpty)
        _ = try library.service.restore(prepared, review: review, choices: [:])
        #expect(try library.repos.saveProfiles.fetchSaveProfile(id: profile.id)?.saveWrittenByBuildID == library.rom.build.id)
    }

    @Test func deletedRecordRefusalHasAReadableMessage() {
        let message = GRDBLibraryBackupError.deletedRecord(table: "save_profiles", id: UUID()).localizedDescription
        #expect(message.contains("Recently Deleted"))
    }
}

struct RestoreLibrary {
    let root: URL
    let ownsRoot: Bool
    let store: ManagedFileStore
    let db: AppDatabase
    let repos: GRDBRepositorySet
    let service: LibraryBackupService
    let saves: PersistentSaveService
    let rom: ROMImportResult

    init(root: URL? = nil, name: String = "Library", rom romData: Data = TestROM.make(title: "MOONGARDEN")) throws {
        ownsRoot = root == nil
        let root = root ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = try ManagedFileStore(rootURL: root.appendingPathComponent(name))
        db = try AppDatabase.inMemory()
        try db.migrate()
        repos = db.makeRepositories()
        service = LibraryBackupService(repository: repos.backup, assetStore: store)
        saves = PersistentSaveService(profiles: repos.saveProfiles, assets: repos.assets, assetStore: store)
        let picked = root.appendingPathComponent("\(name) Moon Garden.gb")
        try romData.write(to: picked)
        let analyzer = ROMImportAnalyzer(builds: repos.builds, games: repos.games, fingerprints: repos.fingerprints,
            toolchainReports: repos.toolchainReports, assetStore: store)
        let committer = ImportCommitter(games: repos.games, builds: repos.builds, assets: repos.assets,
            toolchainReports: repos.toolchainReports, fingerprints: repos.fingerprints, assetStore: store, transactions: repos.transactions)
        rom = try committer.commit(ROMImportPlan(analysis: analyzer.analyzeROM(at: picked, targetGameID: nil),
            disposition: .createGame(title: "Moon Garden"), buildDisplayName: "Base", markAsBase: true))
    }

    func importBuild(_ data: Data, name: String) throws -> ROMImportResult {
        let picked = root.appendingPathComponent("\(name).gb")
        try data.write(to: picked)
        let analyzer = ROMImportAnalyzer(builds: repos.builds, games: repos.games, fingerprints: repos.fingerprints,
            toolchainReports: repos.toolchainReports, assetStore: store)
        let committer = ImportCommitter(games: repos.games, builds: repos.builds, assets: repos.assets,
            toolchainReports: repos.toolchainReports, fingerprints: repos.fingerprints, assetStore: store, transactions: repos.transactions)
        return try committer.commit(ROMImportPlan(analysis: analyzer.analyzeROM(at: picked, targetGameID: rom.game.id),
            disposition: .addBuild(gameID: rom.game.id), buildDisplayName: name, markAsBase: false))
    }

    func remove() { if ownsRoot { try? FileManager.default.removeItem(at: root) } }

    func addProfile(bytes: Data, name: String = "Jane") throws -> SaveProfile {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let profile = SaveProfile(id: UUID(), gameID: rom.game.id, displayName: name, createdAt: date, modifiedAt: date)
        try repos.saveProfiles.insertSaveProfile(profile)
        return try saves.replacePersistentSaveData(bytes, profileID: profile.id, writtenByBuildID: rom.build.id)
    }

    func batteryAsset(of profileID: UUID) throws -> ManagedAsset {
        let profile = try #require(try repos.saveProfiles.fetchSaveProfile(id: profileID))
        let assetID = try #require(profile.persistentSaveAssetID)
        return try #require(try repos.assets.fetchAsset(id: assetID))
    }

    func batteryBytes(of profileID: UUID) throws -> Data {
        try store.readData(at: store.managedURL(relativePath: batteryAsset(of: profileID).relativePath))
    }

    func export(includeROMs: Bool = false) throws -> URL {
        try service.export(to: root.appendingPathComponent("Exports"), displayName: "Test", appVersion: "1", appBuild: "1",
            includeROMs: includeROMs)
    }
}

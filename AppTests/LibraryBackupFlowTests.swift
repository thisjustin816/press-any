import EmulatorApplication
import EmulatorDomain
import Foundation
import Importing
import XCTest
@testable import PressAny

@MainActor
final class LibraryBackupFlowTests: XCTestCase {
    func testExportOptionsDefaultToNoROMsAndRefreshSizeBeforeExporting() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try AppContainer(rootURL: root)
        let build = try importROM(container, root: root)
        let model = LibraryBackupViewModel(service: container.libraryBackup, directory: root.appendingPathComponent("Exports"),
            appInfo: LibraryBackupAppInfo(displayName: "Test App", version: "1", build: "2"))
        XCTAssertFalse(model.includeROMs)
        XCTAssertFalse(model.canExport)
        await model.loadSummary()
        let sizeWithoutROMs = try XCTUnwrap(model.summary).approximateByteLength
        XCTAssertEqual(model.summary?.recordCounts["games"], 1)
        XCTAssertTrue(model.canExport)
        model.includeROMs = true
        await model.loadSummary()
        XCTAssertGreaterThan(try XCTUnwrap(model.summary).approximateByteLength, sizeWithoutROMs)
        await model.export()
        let url = try XCTUnwrap(model.exportedURL)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.progress, 1)
        XCTAssertTrue(try container.libraryBackup.prepare(from: url).manifest.includesROMs)
        XCTAssertTrue(url.lastPathComponent.hasPrefix("Test App Backup "))
        XCTAssertEqual(url.pathExtension, "zip")

        let package = LibraryBackupViewModel(service: container.libraryBackup, directory: root, gameID: build.gameID,
            appInfo: LibraryBackupAppInfo(displayName: "Test App", version: "1", build: "2"))
        await package.loadSummary()
        await package.export()
        let packageURL = try XCTUnwrap(package.exportedURL)
        XCTAssertTrue(try container.libraryBackup.prepare(from: packageURL).manifest.isGamePackage)
        XCTAssertFalse(try container.libraryBackup.prepare(from: packageURL).manifest.includesROMs)
    }

    func testReviewRequiresSaveChoiceAndKeepBothCreatesProfileCopy() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try AppContainer(rootURL: root)
        let build = try importROM(container, root: root)
        let saveURL = root.appendingPathComponent("Example.sav")
        try Data([1, 2, 3]).write(to: saveURL)
        let profile = try container.importBatterySave.execute(gameID: build.gameID, sourceURL: saveURL, name: "Main")
        let archive = try container.libraryBackup.export(to: root, displayName: "Test", appVersion: "1", appBuild: "1")
        var changed = profile
        changed.displayName = "Player Main"
        changed.modifiedAt = Date().addingTimeInterval(60)
        try container.repositories.saveProfiles.updateSaveProfile(changed)
        let model = LibraryRestoreViewModel(service: container.libraryBackup, url: archive, directory: root, isSessionActive: { false })
        await model.load()
        XCTAssertNil(model.errorMessage)
        let conflict = try XCTUnwrap(model.review?.conflicts.first { $0.kind == "Save Profile" })
        XCTAssertTrue(conflict.requiresExplicitChoice)
        XCTAssertNil(model.choices[conflict.id])
        XCTAssertFalse(model.canRestore)
        model.choose(.keepBoth, for: conflict.id)
        XCTAssertTrue(model.canRestore)
        await model.merge()
        XCTAssertNil(model.errorMessage)
        XCTAssertNotNil(model.report)
        XCTAssertTrue(try container.repositories.saveProfiles.fetchSaveProfiles(gameID: build.gameID).contains { $0.displayName == "Main from backup" })
        XCTAssertEqual(try container.repositories.backup.lastRestoreReport(), model.report)
    }

    func testReplacementWritesSafetyBackupBeforeConfirmationAndHonorsCancel() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try AppContainer(rootURL: root)
        _ = try importROM(container, root: root)
        let archive = try container.libraryBackup.export(to: root, displayName: "Test", appVersion: "1", appBuild: "1")
        let before = try container.repositories.games.fetchGames()
        let model = LibraryRestoreViewModel(service: container.libraryBackup, url: archive, directory: root, isSessionActive: { false })
        await model.load()
        XCTAssertFalse(model.isReplacementConfirmationPresented)
        await model.prepareReplacement()
        let safety = try XCTUnwrap(model.safetyBackupURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: safety.path))
        XCTAssertTrue(model.isReplacementConfirmationPresented)
        XCTAssertEqual(try container.repositories.games.fetchGames(), before)
        model.cancelReplacement()
        XCTAssertFalse(model.isReplacementConfirmationPresented)
        XCTAssertNil(model.report)
        await model.confirmReplacement()
        XCTAssertNil(model.report)
        await model.prepareReplacement()
        await model.confirmReplacement()
        XCTAssertNil(model.errorMessage)
        XCTAssertNotNil(model.report)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(model.safetyBackupURL).path))
    }

    func testRunningGameBlocksRestoreAndBuildCannotBeKeptBoth() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try AppContainer(rootURL: root)
        let build = try importROM(container, root: root)
        let archive = try container.libraryBackup.export(to: root, displayName: "Test", appVersion: "1", appBuild: "1")
        var changed = build
        changed.notes = "Library note"
        try container.repositories.builds.updateBuildMetadata(changed)
        let model = LibraryRestoreViewModel(service: container.libraryBackup, url: archive, directory: root, isSessionActive: { true })
        await model.load()
        let conflict = try XCTUnwrap(model.review?.conflicts.first { $0.kind == "Build" })
        let suggested = model.choices[conflict.id]
        model.choose(.keepBoth, for: conflict.id)
        XCTAssertEqual(model.choices[conflict.id], suggested)
        await model.merge()
        XCTAssertEqual(model.errorMessage, "Close the current game before restoring.")
        XCTAssertNil(model.report)
        await model.prepareReplacement()
        XCTAssertNil(model.safetyBackupURL)
    }

    func testSharedBackupRoutesToRestoreAndROMZipStillImports() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try AppContainer(rootURL: root)
        let url = root.appendingPathComponent("backup.zip")
        let bytes = try ZipArchiveWriter.archive(entries: [ZipArchiveEntry(filename: "backup-manifest.json", data: Data("{}".utf8)),
                                                           ZipArchiveEntry(relativePath: "Source/ROM/game.rom", data: Data([1]))])
        try bytes.write(to: url)
        let files = try container.sharedFileInbox.receiveAll(url)
        XCTAssertEqual(files.map(\.kind), [.backup])
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(files.first).url), bytes)
        files.forEach(container.sharedFileInbox.discard)
        let romZip = root.appendingPathComponent("ROM.zip")
        try ZipArchiveWriter.archive(entries: [ZipArchiveEntry(relativePath: "download/Example.gb", data: Data([1]))]).write(to: romZip)
        let roms = try container.sharedFileInbox.receiveAll(romZip)
        XCTAssertEqual(roms.map(\.kind), [.rom])
        XCTAssertEqual(roms.map(\.originalFilename), ["Example.gb"])
        roms.forEach(container.sharedFileInbox.discard)
    }

    private func importROM(_ container: AppContainer, root: URL) throws -> Build {
        let url = root.appendingPathComponent("Example.gb")
        try TestROM.make(title: "BACKUP").write(to: url)
        let coordinator = ImportCoordinator(analyzer: container.importAnalyzer, committer: container.importCommitter, assetStore: container.fileStore)
        let review = ImportReviewViewModel(analysis: try coordinator.analyzeROM(at: url), games: [], coordinator: coordinator)
        return try review.commit().build
    }
}

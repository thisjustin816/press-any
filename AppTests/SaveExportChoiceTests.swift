import EmulatorApplication
import EmulatorDomain
import Foundation
import XCTest
@testable import PressAny

@MainActor
final class SaveExportChoiceTests: XCTestCase {
    func testASaveThatCanShrinkAsksForASizeBeforeAnythingIsWritten() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try AppContainer(rootURL: root)
        let exports = root.appendingPathComponent("Exports", isDirectory: true)
        let build = try importROM(into: container, root: root, ramSizeCode: 0x04)
        var save = Data(repeating: 0xFF, count: 128 * 1024)
        save[0] = 0x42
        let profile = try savedProfile(in: container, root: root, build: build, save: save)
        let model = detailModel(container, gameID: build.gameID, exports: exports)
        model.reload()

        model.exportSave(of: profile)

        XCTAssertEqual(
            model.saveExportChoice?.entries.map(\.title),
            ["Original Size (128 KB)", "Minimized (8 KB)", "Custom: 32 KB", "Custom: 64 KB"]
        )
        XCTAssertNil(model.infoMessage)
        XCTAssertEqual(try exported(exports), [], "nothing is written until a size is chosen")

        model.exportSave(of: profile, size: .minimized)

        let files = try exported(exports)
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].hasSuffix(" (8 KB).sav"), files[0])
        XCTAssertEqual(try Data(contentsOf: exports.appendingPathComponent(files[0])), save.prefix(8 * 1024))
        XCTAssertEqual(model.infoMessage?.contains(files[0]), true)
    }

    func testASaveThatCannotShrinkExportsStraightAway() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try AppContainer(rootURL: root)
        let exports = root.appendingPathComponent("Exports", isDirectory: true)
        let build = try importROM(into: container, root: root, ramSizeCode: 0x04)
        // Not the 128 KB the header declares, so it is exported as it is.
        let profile = try savedProfile(in: container, root: root, build: build, save: Data([1, 2, 3]))
        let model = detailModel(container, gameID: build.gameID, exports: exports)
        model.reload()

        model.exportSave(of: profile)

        XCTAssertNil(model.saveExportChoice)
        let files = try exported(exports)
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].hasSuffix(" - Main.sav"), "the original size keeps the plain name: \(files[0])")
        XCTAssertEqual(try Data(contentsOf: exports.appendingPathComponent(files[0])), Data([1, 2, 3]))
    }

    /// What is in `exports`, which is each test's own folder: the container's is the app's real
    /// Exports folder, shared by every test.
    private func exported(_ exports: URL) throws -> [String] {
        guard FileManager.default.fileExists(atPath: exports.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: exports.path).sorted()
    }

    /// A profile that holds `save`, last written by `build` as a played profile is.
    private func savedProfile(in container: AppContainer, root: URL, build: Build, save: Data) throws -> SaveProfile {
        let source = root.appendingPathComponent("\(UUID()).sav")
        try save.write(to: source)
        var profile = try container.importBatterySave.execute(gameID: build.gameID, sourceURL: source, name: "Main")
        profile.saveWrittenByBuildID = build.id
        try container.repositories.saveProfiles.updateSaveProfile(profile)
        return profile
    }

    /// A 32 KB image whose header declares MBC5 with RAM and a battery, and `ramSizeCode` of RAM.
    private func importROM(into container: AppContainer, root: URL, ramSizeCode: UInt8) throws -> Build {
        let file = root.appendingPathComponent("Example.gb")
        var data = Data(repeating: 0, count: 0x8000)
        data[0x147] = 0x1B
        data[0x149] = ramSizeCode
        try data.write(to: file)
        let coordinator = ImportCoordinator(analyzer: container.importAnalyzer, committer: container.importCommitter, assetStore: container.fileStore)
        let review = ImportReviewViewModel(analysis: try coordinator.analyzeROM(at: file), games: [], coordinator: coordinator)
        return try review.commit().build
    }

    private func detailModel(_ container: AppContainer, gameID: UUID, exports: URL) -> GameDetailViewModel {
        GameDetailViewModel(
            gameID: gameID, games: container.repositories.games, builds: container.repositories.builds,
            profiles: container.repositories.saveProfiles, buildOperations: container.buildOperations,
            createBlank: container.createBlankSaveProfile, duplicateProfile: container.duplicateSaveProfile,
            badges: container.setSaveProfileBadge, renames: container.renameSaveProfile,
            deletion: container.libraryDeletion,
            importSave: container.importBatterySave, patchCreator: container.patchCreator,
            evictImage: container.evictGeneratedImage, artwork: container.gameArtwork,
            variableMaps: container.attachVariableMap, replaceSave: container.replaceBatterySave,
            exporter: container.exportFiles, exportsDirectory: exports
        )
    }
}

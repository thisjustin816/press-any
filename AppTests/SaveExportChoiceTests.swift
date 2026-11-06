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
            ["8 KB (minimum)", "32 KB", "64 KB", "128 KB (original)"]
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

    func testAnInBetweenSizeExportsAtThatSize() throws {
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
        let choice = try XCTUnwrap(model.saveExportChoice)
        let entry = try XCTUnwrap(choice.entries.first { $0.title == "32 KB" })

        model.exportSave(of: choice.profile, size: entry.size)

        let files = try exported(exports)
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].hasSuffix(" (32 KB).sav"), files[0])
        XCTAssertEqual(try Data(contentsOf: exports.appendingPathComponent(files[0])), save.prefix(32 * 1024))
    }

    func testTheOriginalSizeKeepsThePlainName() throws {
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
        let choice = try XCTUnwrap(model.saveExportChoice)
        let entry = try XCTUnwrap(choice.entries.first { $0.title == "128 KB (original)" })

        model.exportSave(of: choice.profile, size: entry.size)

        let files = try exported(exports)
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].hasSuffix(" - Main.sav"), files[0])
        XCTAssertEqual(try Data(contentsOf: exports.appendingPathComponent(files[0])), save)
    }

    func testAMinimumOf32KBListsEverySizeFromThere() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try AppContainer(rootURL: root)
        let exports = root.appendingPathComponent("Exports", isDirectory: true)
        let build = try importROM(into: container, root: root, ramSizeCode: 0x04)
        var save = Data(repeating: 0xFF, count: 128 * 1024)
        save[0x2000] = 0x42
        let profile = try savedProfile(in: container, root: root, build: build, save: save)
        let model = detailModel(container, gameID: build.gameID, exports: exports)
        model.reload()

        model.exportSave(of: profile)

        XCTAssertEqual(
            model.saveExportChoice?.entries.map(\.title),
            ["32 KB (minimum)", "64 KB", "128 KB (original)"]
        )
    }

    func testAnMBC5SaveOf32KBListsTheSmallerAndTheLargerSizes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try AppContainer(rootURL: root)
        let exports = root.appendingPathComponent("Exports", isDirectory: true)
        let build = try importROM(into: container, root: root, ramSizeCode: 0x03)
        var save = Data(repeating: 0xFF, count: 32 * 1024)
        save[0] = 0x42
        let profile = try savedProfile(in: container, root: root, build: build, save: save)
        let model = detailModel(container, gameID: build.gameID, exports: exports)
        model.reload()

        model.exportSave(of: profile)

        XCTAssertEqual(
            model.saveExportChoice?.entries.map(\.title),
            ["8 KB (minimum)", "32 KB (original)", "64 KB", "128 KB"]
        )
    }

    func testAnMBC1SaveOf8KBOffersOnlyTheNextSizeUp() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try AppContainer(rootURL: root)
        let exports = root.appendingPathComponent("Exports", isDirectory: true)
        let build = try importROM(into: container, root: root, ramSizeCode: 0x02, cartridgeType: 0x03)
        var save = Data(repeating: 0xFF, count: 8 * 1024)
        save[0] = 0x42
        let profile = try savedProfile(in: container, root: root, build: build, save: save)
        let model = detailModel(container, gameID: build.gameID, exports: exports)
        model.reload()

        model.exportSave(of: profile)

        let choice = try XCTUnwrap(model.saveExportChoice, "an 8 KB save is asked about when it can grow")
        XCTAssertEqual(choice.entries.map(\.title), ["8 KB (original)", "32 KB"])
        XCTAssertEqual(try exported(exports), [], "nothing is written until a size is chosen")

        model.exportSave(of: choice.profile, size: try XCTUnwrap(choice.entries.last).size)

        let files = try exported(exports)
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].hasSuffix(" (32 KB).sav"), files[0])
        let written = try Data(contentsOf: exports.appendingPathComponent(files[0]))
        XCTAssertEqual(written, save + Data(repeating: 0xFF, count: 24 * 1024))
    }

    func testASaveOfAMapperWithNoKnownLimitOf8KBExportsStraightAway() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try AppContainer(rootURL: root)
        let exports = root.appendingPathComponent("Exports", isDirectory: true)
        // A Pocket Camera cartridge, whose RAM isn't one of the mappers with a known limit.
        let build = try importROM(into: container, root: root, ramSizeCode: 0x02, cartridgeType: 0xFC)
        let profile = try savedProfile(
            in: container, root: root, build: build, save: Data(repeating: 0xFF, count: 8 * 1024)
        )
        let model = detailModel(container, gameID: build.gameID, exports: exports)
        model.reload()

        model.exportSave(of: profile)

        XCTAssertNil(model.saveExportChoice)
        XCTAssertEqual(try exported(exports).count, 1)
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

    /// A 32 KB image whose header declares `cartridgeType` (MBC5 with RAM and a battery unless
    /// given) and `ramSizeCode` of RAM.
    private func importROM(
        into container: AppContainer, root: URL, ramSizeCode: UInt8, cartridgeType: UInt8 = 0x1B
    ) throws -> Build {
        let file = root.appendingPathComponent("Example.gb")
        var data = Data(repeating: 0, count: 0x8000)
        data[0x147] = cartridgeType
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

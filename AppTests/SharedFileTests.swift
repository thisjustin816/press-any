import EmulatorApplication
import Foundation
import Importing
import UniformTypeIdentifiers
import XCTest
@testable import PressAny

@MainActor
final class SharedFileTests: XCTestCase {
    func testReceiptKeepsBytesAndFilenameAfterSenderRemovesItsFile() throws {
        try withInbox { inbox, root, _ in
            for name in ["Example (Europe).GB", "staged.GB", "Example.gbc", "Update.ips", "Update.bps"] {
                let source = root.appendingPathComponent(name)
                let bytes = Data([1, 2, 3])
                try bytes.write(to: source)
                let received = try inbox.receive(source)
                XCTAssertEqual(received.originalFilename, name)
                XCTAssertEqual(received.url.lastPathComponent, name)
                XCTAssertNotEqual(received.url, source)
                try FileManager.default.removeItem(at: source)
                XCTAssertEqual(try Data(contentsOf: received.url), bytes)
                inbox.discard(received)
                XCTAssertFalse(FileManager.default.fileExists(atPath: received.url.path))
            }
        }
    }

    func testTheCopyIOSLeavesInDocumentsInboxIsRemovedWhetherOrNotItIsAccepted() throws {
        let documents = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
        let inboxFolder = documents.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inboxFolder, withIntermediateDirectories: true)
        try withInbox { inbox, _, _ in
            let accepted = inboxFolder.appendingPathComponent("Shared \(UUID().uuidString).gb")
            try Data([1, 2, 3]).write(to: accepted)
            let received = try inbox.receive(accepted)
            XCTAssertFalse(FileManager.default.fileExists(atPath: accepted.path))
            XCTAssertEqual(try Data(contentsOf: received.url), Data([1, 2, 3]))
            inbox.discard(received)

            let rejected = inboxFolder.appendingPathComponent("Shared \(UUID().uuidString).zip")
            try Data([1]).write(to: rejected)
            XCTAssertThrowsError(try inbox.receive(rejected))
            XCTAssertFalse(FileManager.default.fileExists(atPath: rejected.path))
        }
    }

    func testDiscardKeepsSenderAndOtherQueuedCopies() throws {
        try withInbox { inbox, root, _ in
            let source = root.appendingPathComponent("Example.gb")
            try Data([1]).write(to: source)
            let first = try inbox.receive(source)
            let second = try inbox.receive(source)
            inbox.discard(first)
            inbox.discard(first)
            XCTAssertEqual(try Data(contentsOf: source), Data([1]))
            XCTAssertEqual(try Data(contentsOf: second.url), Data([1]))
            inbox.discard(second)
        }
    }

    func testRejectsRemoteURLsUnknownTypesFoldersAndLinks() throws {
        try withInbox { inbox, root, _ in
            XCTAssertThrowsError(try inbox.receive(URL(string: "https://example.com/game.gb")!))
            let text = root.appendingPathComponent("notes.txt")
            try Data([1]).write(to: text)
            XCTAssertThrowsError(try inbox.receive(text))
            let directory = root.appendingPathComponent("folder.gb")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            XCTAssertThrowsError(try inbox.receive(directory))
            let link = root.appendingPathComponent("link.gb")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: text)
            XCTAssertThrowsError(try inbox.receive(link))
        }
    }

    func testRejectsOversizedROMsAndPatchesBeforeStaging() throws {
        try withInbox { inbox, root, _ in
            for (name, bytes) in [("large.gb", 8 * 1024 * 1024 + 1), ("large.bps", 16 * 1024 * 1024 + 1)] {
                let source = root.appendingPathComponent(name)
                try Data(repeating: 0, count: bytes).write(to: source)
                XCTAssertThrowsError(try inbox.receive(source)) { error in
                    XCTAssertTrue(error is ImportSizeError)
                }
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Library/Staging").path))
        }
    }

    func testSharedROMReviewAndQuickPlayKeepFilenameAndSurviveReceiptCleanup() throws {
        try withInbox { inbox, root, container in
            let source = root.appendingPathComponent("Example (Europe) (Rev A).gb")
            let bytes = Data(repeating: 0, count: 0x8000)
            try bytes.write(to: source)
            let received = try inbox.receive(source)
            let coordinator = ImportCoordinator(
                analyzer: container.importAnalyzer,
                committer: container.importCommitter,
                assetStore: container.fileStore
            )
            let analysis = try coordinator.analyzeROM(at: received.url)
            let review = ImportReviewViewModel(analysis: analysis, games: [], coordinator: coordinator)
            let session = try container.quickPlayWorkspace.start(romURL: received.url)
            let result = try review.commit()
            inbox.discard(received)
            XCTAssertEqual(result.build.region, "Europe")
            XCTAssertEqual(result.build.revision, "A")
            XCTAssertEqual(result.sourceAsset.originalFilename, source.lastPathComponent)
            XCTAssertEqual(session.originalFilename, source.lastPathComponent)
            XCTAssertEqual(try Data(contentsOf: session.imageURL), bytes)
            XCTAssertEqual(try Data(contentsOf: container.launchImageResolver.resolve(buildID: result.build.id)), bytes)
            XCTAssertEqual(try Data(contentsOf: source), bytes)
        }
    }

    func testSharedPatchCreatesASeparateBuildAndPreservesBothSources() throws {
        try withInbox { inbox, root, container in
            let rom = root.appendingPathComponent("Example.gb")
            let original = Data(repeating: 0, count: 0x8000)
            try original.write(to: rom)
            let analysis = try container.importAnalyzer.analyzeROM(at: rom, targetGameID: nil)
            let imported = try container.importCommitter.commit(.init(
                analysis: analysis,
                disposition: .createGame(title: "Example"),
                buildDisplayName: "Original",
                markAsBase: true
            ))
            let patch = root.appendingPathComponent("Update.ips")
            // One IPS record changes byte 1; the generated cartridge header remains valid for import.
            let patchBytes = Data("PATCH".utf8) + Data([0, 0, 1, 0, 1, 0x58]) + Data("EOF".utf8)
            try patchBytes.write(to: patch)
            let received = try inbox.receive(patch)
            let build = try container.patchCreator.execute(.init(
                gameID: imported.game.id,
                baseBuildID: imported.build.id,
                patchURLs: [received.url],
                displayName: "Update"
            ))
            inbox.discard(received)
            XCTAssertNotEqual(build.id, imported.build.id)
            XCTAssertEqual(build.parentBuildID, imported.build.id)
            var expected = original
            expected[1] = 0x58
            XCTAssertEqual(try Data(contentsOf: container.launchImageResolver.resolve(buildID: build.id)), expected)
            XCTAssertEqual(try Data(contentsOf: container.launchImageResolver.resolve(buildID: imported.build.id)), original)
            XCTAssertEqual(try Data(contentsOf: patch), patchBytes)
            let recipe = try XCTUnwrap(container.repositories.patchRecipes.fetchPatchRecipe(resultBuildID: build.id))
            let asset = try XCTUnwrap(container.repositories.assets.fetchAsset(id: recipe.items[0].patchAssetID))
            XCTAssertEqual(asset.originalFilename, patch.lastPathComponent)
        }
    }

    func testAppRegistersTheFileTypesUsedByItsPickers() throws {
        let declarations = try XCTUnwrap(Bundle.main.infoDictionary?["UTImportedTypeDeclarations"] as? [[String: Any]])
        let documents = try XCTUnwrap(Bundle.main.infoDictionary?["CFBundleDocumentTypes"] as? [[String: Any]])
        let registered = Set(documents.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] })
        for (type, suffix) in [(UTType.gameBoyROM, "gb"), (.gameBoyColorROM, "gbc"), (.ipsPatch, "ips"), (.bpsPatch, "bps")] {
            XCTAssertTrue(registered.contains(type.identifier))
            let declaration = try XCTUnwrap(declarations.first { $0["UTTypeIdentifier"] as? String == type.identifier })
            let tags = try XCTUnwrap(declaration["UTTypeTagSpecification"] as? [String: Any])
            XCTAssertEqual(tags["public.filename-extension"] as? [String], [suffix])
            XCTAssertTrue(type.conforms(to: .data))
        }
    }

    private func withInbox(_ body: (SharedFileInbox, URL, AppContainer) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try AppContainer(rootURL: root.appendingPathComponent("Library"))
        try body(container.sharedFileInbox, root, container)
    }
}

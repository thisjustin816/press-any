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
            for name in ["Example (Europe).GB", "staged.GB", "Example.gbc", "Update.ips", "Update.bps", "Example.sav", "Example.SRM"] {
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

    func testAZipYieldsItsROMsPatchesAndSavesAndSkipsEverythingElse() throws {
        try withInbox { inbox, root, _ in
            let source = root.appendingPathComponent("Mole Mania DX.zip")
            try storedZip([
                ("readme.txt", Data("read me".utf8)),
                ("Mole Mania DX/mole_mania_dx_v1_3.bps", Data([1, 2, 3])),
                ("game.gb", Data([4, 5])),
                ("game.srm", Data([6])),
            ]).write(to: source)
            let received = try inbox.receiveAll(source)
            XCTAssertEqual(received.map(\.originalFilename), ["mole_mania_dx_v1_3.bps", "game.gb", "game.srm"])
            XCTAssertEqual(received.map(\.kind), [.patch, .rom, .save])
            XCTAssertEqual(try Data(contentsOf: received[0].url), Data([1, 2, 3]))
            received.forEach(inbox.discard)

            let readmeOnly = root.appendingPathComponent("Readme.zip")
            try storedZip([("readme.txt", Data("read me".utf8))]).write(to: readmeOnly)
            XCTAssertThrowsError(try inbox.receiveAll(readmeOnly))
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

    func testRejectsOversizedROMsPatchesAndSavesBeforeStaging() throws {
        try withInbox { inbox, root, _ in
            for (name, bytes) in [("large.gb", 8 * 1024 * 1024 + 1), ("large.bps", 16 * 1024 * 1024 + 1), ("large.srm", 4 * 1024 * 1024 + 1)] {
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
        let expected: [(type: UTType, suffixes: [String], compatible: [String])] = [
            (.gameBoyROM, ["gb"], [
                "com.rileytestut.delta.game.gbc", "com.provenance.rom.gb",
                "com.github.liji32.sameboy.gb", "com.retroarch.gb"
            ]),
            (.gameBoyColorROM, ["gbc"], [
                "com.rileytestut.delta.game.gbc", "com.provenance.rom.gbc",
                "com.github.liji32.sameboy.gbc", "com.retroarch.gbc"
            ]),
            (.ipsPatch, ["ips"], []),
            (.bpsPatch, ["bps"], []),
            (.gameBoySave, ["sav", "srm"], [])
        ]
        for (type, suffixes, compatible) in expected {
            let suffix = suffixes.joined(separator: ", ")
            let matchingDocuments = documents.filter {
                ($0["LSItemContentTypes"] as? [String] ?? []).contains(type.identifier)
            }
            XCTAssertEqual(matchingDocuments.count, 1, suffix)
            let document = try XCTUnwrap(matchingDocuments.first, suffix)
            XCTAssertEqual(document["LSHandlerRank"] as? String, "Owner", suffix)
            XCTAssertEqual(document["CFBundleTypeRole"] as? String, "Viewer", suffix)
            let registered = Set(try XCTUnwrap(document["LSItemContentTypes"] as? [String]))
            XCTAssertTrue(Set(compatible).isSubset(of: registered), suffix)
            let declaration = try XCTUnwrap(declarations.first { $0["UTTypeIdentifier"] as? String == type.identifier })
            let tags = try XCTUnwrap(declaration["UTTypeTagSpecification"] as? [String: Any])
            XCTAssertEqual(tags["public.filename-extension"] as? [String], suffixes)
            XCTAssertTrue(type.conforms(to: .data))
        }
        let zip = try XCTUnwrap(documents.first { ($0["LSItemContentTypes"] as? [String])?.contains("com.pkware.zip-archive") == true },
                                "Files types a .zip as com.pkware.zip-archive")
        XCTAssertEqual(zip["LSHandlerRank"] as? String, "Alternate", "other zips keep opening where they did")
        let exported = Bundle.main.infoDictionary?["UTExportedTypeDeclarations"] as? [[String: Any]] ?? []
        for declaration in exported {
            let tags = declaration["UTTypeTagSpecification"] as? [String: Any] ?? [:]
            let suffixes = tags["public.filename-extension"] as? [String]
                ?? (tags["public.filename-extension"] as? String).map { [$0] } ?? []
            XCTAssertTrue(Set(suffixes.map { $0.lowercased() }).isDisjoint(with: expected.flatMap { $0.suffixes }))
        }
    }

    /// A zip whose entries are stored uncompressed, which is enough to test the inbox; the reader's
    /// own tests cover deflate.
    private func storedZip(_ files: [(String, Data)]) -> Data {
        func le16(_ value: Int) -> Data { Data([UInt8(value & 0xff), UInt8(value >> 8 & 0xff)]) }
        func le32(_ value: UInt32) -> Data { Data((0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }) }
        func crc32(_ data: Data) -> UInt32 {
            var crc: UInt32 = 0xffff_ffff
            for byte in data {
                crc ^= UInt32(byte)
                for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xedb8_8320 : crc >> 1 }
            }
            return ~crc
        }
        var archive = Data()
        var directory = Data()
        for (name, data) in files {
            let nameData = Data(name.utf8)
            let crc = crc32(data)
            let offset = UInt32(archive.count)
            archive += le32(0x0403_4b50) + le16(20) + le16(0) + le16(0) + le16(0) + le16(0)
            archive += le32(crc) + le32(UInt32(data.count)) + le32(UInt32(data.count)) + le16(nameData.count) + le16(0)
            archive += nameData + data
            directory += le32(0x0201_4b50) + le16(20) + le16(20) + le16(0) + le16(0) + le16(0) + le16(0)
            directory += le32(crc) + le32(UInt32(data.count)) + le32(UInt32(data.count)) + le16(nameData.count)
            directory += le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(offset) + nameData
        }
        let directoryOffset = UInt32(archive.count)
        archive += directory
        archive += le32(0x0605_4b50) + le16(0) + le16(0) + le16(files.count) + le16(files.count)
        archive += le32(UInt32(directory.count)) + le32(directoryOffset) + le16(0)
        return archive
    }

    private func withInbox(_ body: (SharedFileInbox, URL, AppContainer) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try AppContainer(rootURL: root.appendingPathComponent("Library"))
        try body(container.sharedFileInbox, root, container)
    }
}

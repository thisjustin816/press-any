import AssetStorage
import EmulatorApplication
import Foundation
import Importing
import Testing
@testable import PressAny

@MainActor
struct ZipGlobalsInboxTests {
    @Test func globalsStayWithTheirROMUntilReceiptIsDiscarded() throws {
        try withInbox { inbox, root in
            let source = try writeZip([
                ("Release/Example.gbc", Data([1, 2])),
                ("Release/globals.i", Data("VAR_SCORE = 0\nVAR_LIVES = 1\n".utf8)),
            ], root: root)
            let files = try inbox.receiveAll(source)
            #expect(files.map(\.originalFilename) == ["Example.gbc"])
            let rom = try #require(files.first)
            let map = rom.url.deletingLastPathComponent().appendingPathComponent("globals.i")
            #expect(rom.variableMapURL == map)
            try FileManager.default.removeItem(at: source)
            #expect(try Data(contentsOf: map) == Data("VAR_SCORE = 0\nVAR_LIVES = 1\n".utf8))
            #expect(try Data(contentsOf: rom.url) == Data([1, 2]))
            inbox.discard(rom)
            #expect(!FileManager.default.fileExists(atPath: rom.url.path))
            #expect(!FileManager.default.fileExists(atPath: map.path))
        }
    }

    @Test func eachArchiveFolderKeepsItsOwnMapAndAcceptsEitherGlobalsFilename() throws {
        try withInbox { inbox, root in
            let source = try writeZip([
                ("One/Example.gb", Data([1])), ("One/GLOBALS.I", Data([11])),
                ("Two/Example.gbc", Data([2])), ("Two/game_globals.i", Data([22])),
                ("Three/Example.gb", Data([3])), ("Elsewhere/globals.i", Data([33])),
            ], root: root)
            let files = try inbox.receiveAll(source)
            defer { files.forEach(inbox.discard) }
            #expect(files.count == 3)
            #expect(try Data(contentsOf: #require(files[0].variableMapURL)) == Data([11]))
            #expect(try Data(contentsOf: #require(files[1].variableMapURL)) == Data([22]))
            #expect(files[2].variableMapURL == nil)
        }
    }

    @Test func ambiguousROMsOrMapsAreNotAttached() throws {
        try withInbox { inbox, root in
            for entries: [(String, Data)] in [
                [("One.gb", Data([1])), ("Two.gbc", Data([2])), ("globals.i", Data([3]))],
                [("One.gb", Data([1])), ("globals.i", Data([2])), ("game_globals.i", Data([3]))],
            ] {
                let files = try inbox.receiveAll(writeZip(entries, root: root))
                #expect(!files.isEmpty)
                #expect(files.allSatisfy { $0.variableMapURL == nil })
                files.forEach(inbox.discard)
            }
        }
    }

    @Test func unrelatedIncludesAndNOIFilesStayIgnored() throws {
        try withInbox { inbox, root in
            let files = try inbox.receiveAll(writeZip([
                ("Example.gb", Data([1])),
                ("engine.i", Data(repeating: 0, count: Int(ImportSizeLimit.variableMap.bytes) + 1)),
                ("Example.noi", Data("DEF _score 0xC000\n".utf8)),
                ("__MACOSX/globals.i", Data([2])), ("._globals.i", Data([3])),
            ], root: root))
            defer { files.forEach(inbox.discard) }
            #expect(files.map(\.originalFilename) == ["Example.gb"])
            #expect(files.first?.variableMapURL == nil)
        }
    }

    @Test func oversizedGlobalsAreRejectedAndLeaveNoReceipt() throws {
        try withInbox { inbox, root in
            let source = try writeZip([
                ("Example.gb", Data([1])),
                ("globals.i", Data(repeating: 0, count: Int(ImportSizeLimit.variableMap.bytes) + 1)),
            ], root: root)
            #expect(throws: ZipArchiveError.entryTooLarge("globals.i")) { try inbox.receiveAll(source) }
            let staging = root.appendingPathComponent("Library/Staging")
            #expect(try FileManager.default.contentsOfDirectory(atPath: staging.path).isEmpty)
            #expect(FileManager.default.fileExists(atPath: source.path))
        }
    }

    @Test func aGlobalsFileAloneDoesNotMakeAnImportableArchive() throws {
        try withInbox { inbox, root in
            let source = try writeZip([("globals.i", Data([1]))], root: root)
            #expect(throws: SharedFileError.self) { try inbox.receiveAll(source) }
        }
    }

    private func writeZip(_ files: [(String, Data)], root: URL) throws -> URL {
        let source = root.appendingPathComponent("\(UUID().uuidString).zip")
        try ZipArchiveWriter.archive(entries: files.map { .init(relativePath: $0.0, data: $0.1) }).write(to: source)
        return source
    }

    private func withInbox(_ body: (SharedFileInbox, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ManagedFileStore(rootURL: root.appendingPathComponent("Library"))
        try body(SharedFileInbox(store: store), root)
    }
}

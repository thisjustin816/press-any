import Foundation
import Importing
import Testing

@Suite struct ZipArchiveWriterTests {
    @Test func storedWriterRoundTripsFoldersEmptyFilesAndUTF8() throws {
        let entries = [ZipArchiveEntry(relativePath: "UserData/", data: Data()),
                       ZipArchiveEntry(relativePath: "UserData/empty.sav", data: Data()),
                       ZipArchiveEntry(relativePath: "UserData/Pokémon 日本語.png", data: Data([1, 2, 3]))]
        let archive = try ZipArchiveWriter.archive(entries: entries)
        #expect(try ZipArchiveReader.backupEntries(in: archive) == entries)
    }

    @Test func rootManifestRoutesBeforeROMMatchLimit() throws {
        let manyROMs = (0..<40).map { ZipArchiveEntry(relativePath: "game-\($0).gb", data: Data([1])) }
        let backup = try ZipArchiveWriter.archive(entries: manyROMs + [ZipArchiveEntry(filename: "backup-manifest.json", data: Data("{}".utf8))])
        #expect(try ZipArchiveReader.isLibraryBackup(backup))
        #expect(try ZipArchiveReader.backupEntries(in: backup).count == 41)
        let rom = try ZipArchiveWriter.archive(entries: [ZipArchiveEntry(relativePath: "folder/game.gb", data: Data([1]))])
        #expect(try !ZipArchiveReader.isLibraryBackup(rom))
        #expect(try ZipArchiveReader.entries(in: rom, extensions: ["gb"]) { _ in 10 } == [ZipArchiveEntry(filename: "game.gb", data: Data([1]))])
        let nested = try ZipArchiveWriter.archive(entries: [ZipArchiveEntry(relativePath: "folder/backup-manifest.json", data: Data())])
        #expect(try !ZipArchiveReader.isLibraryBackup(nested))
    }

    @Test(arguments: ["../save.sav", "/save.sav", "folder/../save.sav", "folder\\save.sav", "folder//save.sav"])
    func traversalPathsAreRefused(_ path: String) {
        #expect(throws: ZipArchiveError.self) { try ZipArchiveWriter.archive(entries: [ZipArchiveEntry(relativePath: path, data: Data())]) }
        #expect(throws: ZipArchiveError.self) { try ZipArchiveReader.backupEntries(in: ZipTestArchive.make([(path, Data())])) }
    }

    @Test func duplicatesChecksumsAndBudgetsAreRefused() throws {
        let entry = ZipArchiveEntry(filename: "save.sav", data: Data([1]))
        #expect(throws: ZipArchiveError.self) { try ZipArchiveWriter.archive(entries: [entry, entry]) }
        #expect(throws: ZipArchiveError.self) { try ZipArchiveReader.backupEntries(in: ZipTestArchive.make([("a", Data()), ("a", Data())])) }
        var damaged = try ZipArchiveWriter.archive(entries: [entry])
        damaged[30 + entry.filename.utf8.count] ^= 1
        #expect(throws: ZipArchiveError.damaged) { try ZipArchiveReader.backupEntries(in: damaged) }
        #expect(throws: ZipArchiveError.tooManyEntries) { try ZipArchiveWriter.archive(entries: (0...4096).map { ZipArchiveEntry(filename: "\($0)", data: Data()) }) }
        #expect(throws: ZipArchiveError.archiveTooLarge) {
            try ZipArchiveWriter.archive(entries: [ZipArchiveEntry(filename: "large", data: Data(count: 1_000))], maximumBytes: 1_000)
        }
    }

    @Test func streamedFilesRoundTripAndBackupsMayExceedTheROMZipLimit() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var large = Data(repeating: 0xa5, count: ZipArchiveReader.maximumArchiveBytes + 3 << 20)
        for offset in stride(from: 0, to: large.count, by: 1 << 20) { large[offset] = UInt8(truncatingIfNeeded: offset >> 20) }
        let source = root.appendingPathComponent("rom")
        try large.write(to: source)
        let archive = root.appendingPathComponent("backup.zip")
        try ZipArchiveWriter.write([
            ZipArchiveWriter.Item(relativePath: "Source/ROM/moon.rom", content: .file(source)),
            ZipArchiveWriter.Item(relativePath: "backup-manifest.json", content: .data(Data("{}".utf8))),
        ], to: archive)
        let backup = try ZipArchiveReader.BackupArchive(contentsOf: archive)
        #expect(backup.paths == ["Source/ROM/moon.rom", "backup-manifest.json"])
        #expect(try backup.data(at: "Source/ROM/moon.rom") == large)
        let bytes = try Data(contentsOf: archive)
        #expect(try ZipArchiveReader.isLibraryBackup(bytes))
        #expect(throws: ZipArchiveError.archiveTooLarge) { try ZipArchiveReader.entries(in: bytes, extensions: ["rom"]) { _ in .max } }
    }
}

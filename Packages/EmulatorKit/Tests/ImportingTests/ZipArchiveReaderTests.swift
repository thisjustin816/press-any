import Foundation
import Importing
import XCTest

final class ZipArchiveReaderTests: XCTestCase {
    private let romsAndPatches: Set<String> = ["gb", "gbc", "ips", "bps", "sav", "srm"]

    func testReadsStoredAndDeflatedEntriesAndSkipsReadmesFoldersAndMacMetadata() throws {
        let rom = Data((0..<4_096).map { UInt8($0 % 7) })
        let patch = Data("BPS1 patch bytes".utf8)
        let archive = try zip([
            "readme.txt": Data("read me".utf8),
            "Mole Mania DX/": Data(),
            "Mole Mania DX/mole_mania_dx_v1_3.bps": patch,
            "__MACOSX/Mole Mania DX/._mole_mania_dx_v1_3.bps": Data([0]),
            "game.gb": rom,
        ])
        let entries = try ZipArchiveReader.entries(in: archive, extensions: romsAndPatches) { _ in 8 << 20 }
        XCTAssertEqual(Set(entries.map(\.filename)), ["mole_mania_dx_v1_3.bps", "game.gb"])
        XCTAssertEqual(entries.first { $0.filename == "game.gb" }?.data, rom)
        XCTAssertEqual(entries.first { $0.filename.hasSuffix(".bps") }?.data, patch)
    }

    func testAnEntryLargerThanItsLimitIsRefusedBeforeItIsInflated() throws {
        let archive = try zip(["big.gb": Data(repeating: 0, count: 2_048)])
        XCTAssertThrowsError(try ZipArchiveReader.entries(in: archive, extensions: romsAndPatches) { _ in 1_024 }) { error in
            XCTAssertEqual(error as? ZipArchiveError, .entryTooLarge("big.gb"))
        }
    }

    func testDamagedAndNonZipDataAreRefused() throws {
        XCTAssertThrowsError(try ZipArchiveReader.entries(in: Data("not a zip".utf8), extensions: romsAndPatches) { _ in 1 << 20 }) { error in
            XCTAssertEqual(error as? ZipArchiveError, .notAZip)
        }
        var archive = try zip(["game.gb": Data(repeating: 1, count: 512)], compress: false)
        // Flip a byte of the stored entry so its CRC32 no longer matches.
        let index = try XCTUnwrap(archive.range(of: Data(repeating: 1, count: 16))).lowerBound
        archive[index] = 2
        XCTAssertThrowsError(try ZipArchiveReader.entries(in: archive, extensions: romsAndPatches) { _ in 1 << 20 }) { error in
            XCTAssertEqual(error as? ZipArchiveError, .damaged)
        }
    }

    /// Builds a zip with the system's `zip` tool, deflating unless asked not to.
    private func zip(_ files: [String: Data], compress: Bool = true) throws -> Data {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source", isDirectory: true)
        for (path, data) in files {
            let url = source.appendingPathComponent(path)
            if path.hasSuffix("/") {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } else {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url)
            }
        }
        let output = root.appendingPathComponent("archive.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = source
        process.arguments = ["-q", "-r", compress ? "-6" : "-0", output.path, "."]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return try Data(contentsOf: output)
    }
}

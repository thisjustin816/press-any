import Foundation
import Importing
import XCTest

final class ZipArchiveReaderTests: XCTestCase {
    private let romsAndPatches: Set<String> = ["gb", "gbc", "ips", "bps", "sav", "srm"]

    func testReadsStoredAndDeflatedEntriesAndSkipsReadmesFoldersAndMacMetadata() throws {
        let archive = try XCTUnwrap(Data(base64Encoded: hackDownload.joined()))
        let entries = try ZipArchiveReader.entries(in: archive, extensions: romsAndPatches) { _ in 8 << 20 }
        XCTAssertEqual(entries.map(\.filename), ["mole_mania_dx_v1_3.bps", "game.gb"])
        XCTAssertEqual(entries.first?.data, Data("BPS1 patch bytes".utf8))
        XCTAssertEqual(entries.last?.data, Data((0..<4_096).map { UInt8($0 % 7) }))
    }

    func testAnEntryLargerThanItsLimitIsRefusedBeforeItIsInflated() throws {
        let archive = try XCTUnwrap(Data(base64Encoded: hackDownload.joined()))
        XCTAssertThrowsError(try ZipArchiveReader.entries(in: archive, extensions: romsAndPatches) { _ in 1_024 }) { error in
            XCTAssertEqual(error as? ZipArchiveError, .entryTooLarge("game.gb"))
        }
    }

    func testDamagedAndNonZipDataAreRefused() throws {
        XCTAssertThrowsError(try ZipArchiveReader.entries(in: Data("not a zip".utf8), extensions: romsAndPatches) { _ in 1 << 20 }) { error in
            XCTAssertEqual(error as? ZipArchiveError, .notAZip)
        }
        var archive = try XCTUnwrap(Data(base64Encoded: hackDownload.joined()))
        // Flip a byte of the stored patch so its CRC32 no longer matches.
        let index = try XCTUnwrap(archive.range(of: Data("BPS1 patch bytes".utf8))).lowerBound
        archive[index] ^= 0xff
        XCTAssertThrowsError(try ZipArchiveReader.entries(in: archive, extensions: romsAndPatches) { _ in 1 << 20 }) { error in
            XCTAssertEqual(error as? ZipArchiveError, .damaged)
        }
    }

    /// A zip laid out like a hack download, made with Python's zipfile: a deflated readme.txt, a
    /// "Mole Mania DX/" folder holding a stored mole_mania_dx_v1_3.bps ("BPS1 patch bytes"), its
    /// __MACOSX resource fork, and a deflated game.gb of 4,096 bytes counting 0 to 6 over and over.
    private let hackDownload = [
        "UEsDBBQAAAAIAOCLOV3heHJ7CQAAAAcAAAAKAAAAcmVhZG1lLnR4dCtKTUxRyE0FAFBLAwQUAAAAAADgizldAAAAAAAAAAAA",
        "AAAADgAAAE1vbGUgTWFuaWEgRFgvUEsDBBQAAAAAAECMOV2xxiqpEAAAABAAAAAkAAAATW9sZSBNYW5pYSBEWC9tb2xlX21h",
        "bmlhX2R4X3YxXzMuYnBzQlBTMSBwYXRjaCBieXRlc1BLAwQUAAAAAABAjDldje8C0gEAAAABAAAALwAAAF9fTUFDT1NYL01v",
        "bGUgTWFuaWEgRFgvLl9tb2xlX21hbmlhX2R4X3YxXzMuYnBzAFBLAwQUAAAACABAjDldd9PBdB0AAAAAEAAABwAAAGdhbWUu",
        "Z2LtxcERADAEADC07D+yPVzySWS93xOSJEmSJOluC1BLAQIUAxQAAAAIAOCLOV3heHJ7CQAAAAcAAAAKAAAAAAAAAAAAAACA",
        "AQAAAAByZWFkbWUudHh0UEsBAhQDFAAAAAAA4Is5XQAAAAAAAAAAAAAAAA4AAAAAAAAAAAAAAIABMQAAAE1vbGUgTWFuaWEg",
        "RFgvUEsBAhQDFAAAAAAAQIw5XbHGKqkQAAAAEAAAACQAAAAAAAAAAAAAAIABXQAAAE1vbGUgTWFuaWEgRFgvbW9sZV9tYW5p",
        "YV9keF92MV8zLmJwc1BLAQIUAxQAAAAAAECMOV2N7wLSAQAAAAEAAAAvAAAAAAAAAAAAAACAAa8AAABfX01BQ09TWC9Nb2xl",
        "IE1hbmlhIERYLy5fbW9sZV9tYW5pYV9keF92MV8zLmJwc1BLAQIUAxQAAAAIAECMOV1308F0HQAAAAAQAAAHAAAAAAAAAAAA",
        "AACAAf0AAABnYW1lLmdiUEsFBgAAAAAFAAUAWAEAAD8BAAAAAA==",
    ]
}

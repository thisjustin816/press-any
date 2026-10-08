import Foundation
import Importing
import XCTest

final class ZipArchiveValidationTests: XCTestCase {
    func testRejectsCentralLocalNameMismatch() {
        var archive = ZipTestArchive.make([("game.gb", Data([1]))])
        archive[30] = Character("x").asciiValue!
        assertDamaged(archive)
    }

    func testRejectsTruncatedCentralDirectory() {
        var archive = ZipTestArchive.make([("game.gb", Data([1]))])
        let end = archive.count - 22
        archive.zipSet16(2, at: end + 8)
        archive.zipSet16(2, at: end + 10)
        assertDamaged(archive)
    }

    func testRejectsZip64EntrySizeSentinel() {
        var archive = ZipTestArchive.make([("game.gb", Data([1]))])
        archive.zipSet32(.max, at: archive.zipCentralOffset + 20)
        assertDamaged(archive)
    }

    func testROMImportSkipsLinksAndUnsupportedEntriesThatBackupsRefuse() throws {
        let rom = Data(repeating: 1, count: 64)
        func archive(_ entries: [(String, Data)], patch: (inout Data, _ secondRecord: Int) -> Void) -> Data {
            var archive = ZipTestArchive.make(entries)
            patch(&archive, archive.zipCentralOffset + 46 + entries[0].0.utf8.count)
            return archive
        }
        let link = archive([("Moon/moon.gb", rom), ("latest.gb", Data("Moon/moon.gb".utf8))]) { archive, second in
            archive.zipSet32(0xa1ff_0000, at: second + 38)
        }
        let encryptedReadme = archive([("moon.gb", rom), ("readme.txt", Data([2]))]) { archive, second in
            archive.zipSet16(0x0801, at: second + 8)
            archive.zipSet16(0x0801, at: Int(archive.zipUInt32(at: second + 42)) + 6)
        }
        let newerReadme = archive([("moon.gb", rom), ("-", Data([2]))]) { archive, second in
            archive.zipSet16(45, at: second + 6)
        }
        var trailing = ZipTestArchive.make([("moon.gb", rom)])
        trailing.append(Data("signed".utf8))
        for archive in [link, encryptedReadme, newerReadme, trailing] {
            let entries = try ZipArchiveReader.entries(in: archive, extensions: ["gb"]) { _ in 8 << 20 }
            XCTAssertEqual(entries.map(\.data), [rom])
            XCTAssertThrowsError(try ZipArchiveReader.backupEntries(in: archive))
        }
        let encryptedROM = archive([("readme.txt", Data([2])), ("moon.gb", rom)]) { archive, second in
            archive.zipSet16(0x0801, at: second + 8)
            archive.zipSet16(0x0801, at: Int(archive.zipUInt32(at: second + 42)) + 6)
        }
        XCTAssertThrowsError(try ZipArchiveReader.entries(in: encryptedROM, extensions: ["gb"]) { _ in 8 << 20 }) { error in
            XCTAssertEqual(error as? ZipArchiveError, .encrypted)
        }
    }

    private func assertDamaged(_ archive: Data, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try ZipArchiveReader.entries(in: archive, extensions: ["gb"]) { _ in 8 << 20 }, file: file, line: line) { error in
            XCTAssertEqual(error as? ZipArchiveError, .damaged, file: file, line: line)
        }
    }
}

/// Independent ZIP fixtures allow malformed headers that the production writer refuses.
enum ZipTestArchive {
    static func make(_ entries: [(String, Data)], method: UInt16 = 0, flags: UInt16 = 0x0800,
                     version: UInt16 = 20, extra: Data = Data(), declaredSize: UInt32? = nil) -> Data {
        var archive = Data()
        var directory = Data()
        for (name, data) in entries {
            let name = Data(name.utf8)
            let localOffset = UInt32(archive.count)
            let checksum = crc(data)
            let size = declaredSize ?? UInt32(data.count)
            archive.zipAppend32(0x0403_4b50)
            archive.zipAppend16(version)
            archive.zipAppend16(flags)
            archive.zipAppend16(method)
            archive.zipAppend32(0)
            archive.zipAppend32(checksum)
            archive.zipAppend32(UInt32(data.count))
            archive.zipAppend32(size)
            archive.zipAppend16(UInt16(name.count))
            archive.zipAppend16(UInt16(extra.count))
            archive.append(name)
            archive.append(extra)
            archive.append(data)

            directory.zipAppend32(0x0201_4b50)
            directory.zipAppend16(0x0314)
            directory.zipAppend16(version)
            directory.zipAppend16(flags)
            directory.zipAppend16(method)
            directory.zipAppend32(0)
            directory.zipAppend32(checksum)
            directory.zipAppend32(UInt32(data.count))
            directory.zipAppend32(size)
            directory.zipAppend16(UInt16(name.count))
            directory.zipAppend16(UInt16(extra.count))
            directory.zipAppend16(0)
            directory.zipAppend16(0)
            directory.zipAppend16(0)
            directory.zipAppend32(0)
            directory.zipAppend32(localOffset)
            directory.append(name)
            directory.append(extra)
        }
        let offset = UInt32(archive.count)
        archive.append(directory)
        archive.zipAppend32(0x0605_4b50)
        archive.zipAppend32(0)
        archive.zipAppend16(UInt16(entries.count))
        archive.zipAppend16(UInt16(entries.count))
        archive.zipAppend32(UInt32(directory.count))
        archive.zipAppend32(offset)
        archive.zipAppend16(0)
        return archive
    }

    private static func crc(_ data: Data) -> UInt32 {
        var crc: UInt32 = .max
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = crc & 1 == 0 ? crc >> 1 : (crc >> 1) ^ 0xedb8_8320
            }
        }
        return ~crc
    }
}

extension Data {
    var zipCentralOffset: Int { Int(zipUInt32(at: count - 6)) }

    func zipUInt16(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    func zipUInt32(at offset: Int) -> UInt32 {
        UInt32(self[offset]) | UInt32(self[offset + 1]) << 8
            | UInt32(self[offset + 2]) << 16 | UInt32(self[offset + 3]) << 24
    }

    mutating func zipSet16(_ value: UInt16, at offset: Int) {
        self[offset] = UInt8(truncatingIfNeeded: value)
        self[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
    }

    mutating func zipSet32(_ value: UInt32, at offset: Int) {
        zipSet16(UInt16(truncatingIfNeeded: value), at: offset)
        zipSet16(UInt16(truncatingIfNeeded: value >> 16), at: offset + 2)
    }

    mutating func zipAppend16(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }

    mutating func zipAppend32(_ value: UInt32) {
        zipAppend16(UInt16(truncatingIfNeeded: value))
        zipAppend16(UInt16(truncatingIfNeeded: value >> 16))
    }
}

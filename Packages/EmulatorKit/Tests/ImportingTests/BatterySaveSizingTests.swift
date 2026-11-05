import EmulatorDomain
import Foundation
@testable import Importing
import XCTest

final class BatterySaveSizingTests: XCTestCase {
    private let kb = 1024

    func testAMostlyBlankSaveShrinksToTheSmallestRealSizeThatHoldsIt() {
        // Data only in the first 1,558 bytes of a 128 KB save.
        let save = Self.save(128 * kb, writing: [0: 0x42, 1557: 0x01])

        let options = BatterySaveSizing.options(for: save, header: Self.header())

        XCTAssertEqual(options.originalBytes, 128 * kb)
        XCTAssertEqual(options.minimizedBytes, 8 * kb)
        XCTAssertEqual(options.customSizes, [32 * kb, 64 * kb])
    }

    func testDataPastTheFirstBankNeedsTheNextRealSize() {
        let save = Self.save(128 * kb, writing: [0x2000: 0x01])

        let options = BatterySaveSizing.options(for: save, header: Self.header())

        XCTAssertEqual(options.minimizedBytes, 32 * kb, "0x2001 bytes don't fit in 8 KB")
        XCTAssertEqual(options.customSizes, [64 * kb])
    }

    func testABlankSaveShrinksToTheMinimum() {
        let options = BatterySaveSizing.options(for: Self.save(128 * kb, writing: [:]), header: Self.header())

        XCTAssertEqual(options.minimizedBytes, 8 * kb)
    }

    func testOnlyAnErasedTailCountsAsUnused() {
        // A game that zero-fills its RAM leaves a 0x00 tail, which SameBoy would not refill.
        let save = Self.save(128 * kb, writing: [128 * kb - 1: 0x00])

        let options = BatterySaveSizing.options(for: save, header: Self.header())

        XCTAssertNil(options.minimizedBytes)
        XCTAssertEqual(options.customSizes, [])
        XCTAssertEqual(options.originalBytes, 128 * kb)
    }

    func testA32KBSaveShrinksToTheMinimumAndAnMBC5ACanAlsoGrow() {
        let save = Self.save(32 * kb, writing: [0: 0x01])

        let options = BatterySaveSizing.options(for: save, header: Self.header(ram: 0x03))

        XCTAssertEqual(options.minimizedBytes, 8 * kb)
        XCTAssertEqual(options.smallerSizes, [8 * kb])
        XCTAssertEqual(options.largerSizes, [64 * kb, 128 * kb])
    }

    func testA32KBMBC1SaveShrinksButHasNothingBetweenOrAbove() {
        let save = Self.save(32 * kb, writing: [0: 0x01])

        let options = BatterySaveSizing.options(for: save, header: Self.header(type: 0x03, ram: 0x03))

        XCTAssertEqual(options.smallerSizes, [8 * kb])
        XCTAssertEqual(options.customSizes, [])
    }

    func testA64KBSaveOffersTheSizesBelowIt() {
        let save = Self.save(64 * kb, writing: [0: 0x01])

        let options = BatterySaveSizing.options(for: save, header: Self.header(ram: 0x05))

        XCTAssertEqual(options.minimizedBytes, 8 * kb)
        XCTAssertEqual(options.smallerSizes, [8 * kb, 32 * kb])
        XCTAssertEqual(options.largerSizes, [128 * kb])
    }

    func testAClockTrailerKeepsTheSaveAtItsOriginalSize() {
        // MBC3 with a timer: the file is the RAM plus a 48-byte clock, so a shorter file would
        // read the clock as RAM and reset it.
        let save = Self.save(32 * kb + 48, writing: [0: 0x01])

        let options = BatterySaveSizing.options(for: save, header: Self.header(type: 0x10, ram: 0x03))

        XCTAssertNil(options.minimizedBytes)
        XCTAssertEqual(options.originalBytes, 32 * kb + 48)
    }

    func testCartridgesWhoseRAMIsNotPlainBankedRAMAreNeverShrunk() {
        // MBC2, MMM01, MBC7, TPP1 and HuC3.
        for type: UInt8 in [0x05, 0x06, 0x0B, 0x0C, 0x0D, 0x22, 0xBC, 0xFE] {
            let save = Self.save(32 * kb, writing: [0: 0x01])
            let options = BatterySaveSizing.options(for: save, header: Self.header(type: type, ram: 0x03))
            XCTAssertNil(options.minimizedBytes, "type \(type)")
        }
    }

    func testRAMNoLargerThanTheMinimumHasNothingToShrink() {
        for ram: UInt8 in [0x01, 0x02] {
            let size = ram == 0x01 ? 2 * kb : 8 * kb
            let options = BatterySaveSizing.options(for: Self.save(size, writing: [0: 0x01]), header: Self.header(ram: ram))
            XCTAssertNil(options.minimizedBytes, "RAM code \(ram)")
        }
    }

    func testAnMBC5SaveOf8KBCanGrowToEveryLargerRealSize() {
        let save = Self.save(8 * kb, writing: [0: 0x42])

        let options = BatterySaveSizing.options(for: save, header: Self.header(type: 0x1B, ram: 0x02))

        XCTAssertNil(options.minimizedBytes)
        XCTAssertEqual(options.largerSizes, [32 * kb, 64 * kb, 128 * kb])
        XCTAssertEqual(options.customSizes, [32 * kb, 64 * kb, 128 * kb])
        XCTAssertTrue(options.hasChoices)
    }

    func testAnMBC1OrMBC3SaveGrowsNoFurtherThanTheMapperReaches() {
        for type: UInt8 in [0x01, 0x02, 0x03, 0x11, 0x12, 0x13] {
            let options = BatterySaveSizing.options(
                for: Self.save(8 * kb, writing: [0: 0x42]), header: Self.header(type: type, ram: 0x02)
            )
            XCTAssertEqual(options.largerSizes, [32 * kb], "type \(type)")
        }
    }

    func testAMapperWithNoKnownLimitIsNeverGrown() {
        // Pocket Camera, HuC1, MBC6 and a ROM-and-RAM cartridge with no mapper.
        for type: UInt8 in [0xFC, 0xFF, 0x20, 0x08, 0x09, 0x00] {
            let options = BatterySaveSizing.options(
                for: Self.save(8 * kb, writing: [0: 0x42]), header: Self.header(type: type, ram: 0x02)
            )
            XCTAssertEqual(options.largerSizes, [], "type \(type)")
        }
    }

    func testASaveAtTheMappersLimitHasNoLargerSize() {
        let options = BatterySaveSizing.options(
            for: Self.save(128 * kb, writing: [0: 0x42]), header: Self.header(type: 0x1B, ram: 0x04)
        )
        XCTAssertEqual(options.largerSizes, [])
        let mbc1 = BatterySaveSizing.options(
            for: Self.save(32 * kb, writing: [0: 0x42]), header: Self.header(type: 0x03, ram: 0x03)
        )
        XCTAssertEqual(mbc1.largerSizes, [])
    }

    func testCartridgesWhoseRAMIsNotPlainBankedRAMAreNeverGrown() {
        for type: UInt8 in [0x05, 0x06, 0x0B, 0x0C, 0x0D, 0x22, 0xBC, 0xFE] {
            let options = BatterySaveSizing.options(
                for: Self.save(8 * kb, writing: [0: 0x01]), header: Self.header(type: type, ram: 0x02)
            )
            XCTAssertEqual(options.largerSizes, [], "type \(type)")
            XCTAssertFalse(options.hasChoices, "type \(type)")
        }
    }

    func testASaveWithAClockOrAnotherLengthIsNeverGrown() {
        // MBC3 with a timer keeps the clock after the RAM, so more RAM would put RAM over it.
        let clock = BatterySaveSizing.options(
            for: Self.save(8 * kb + 48, writing: [0: 0x01]), header: Self.header(type: 0x10, ram: 0x02)
        )
        XCTAssertEqual(clock.largerSizes, [])
        let other = BatterySaveSizing.options(
            for: Self.save(32 * kb, writing: [0: 0x01]), header: Self.header(type: 0x1B, ram: 0x02)
        )
        XCTAssertEqual(other.largerSizes, [])
    }

    func testASaveThatIsNotTheHeadersSizeIsLeftAlone() {
        // An imported save keeps its own length until the game first saves over it.
        let save = Self.save(32 * kb, writing: [0: 0x01])

        let options = BatterySaveSizing.options(for: save, header: Self.header(ram: 0x04))

        XCTAssertNil(options.minimizedBytes)
        XCTAssertEqual(options.originalBytes, 32 * kb)
    }

    func testWithoutAHeaderTheSaveIsLeftAlone() {
        let options = BatterySaveSizing.options(for: Self.save(128 * kb, writing: [0: 0x01]), header: nil)

        XCTAssertNil(options.minimizedBytes)
        XCTAssertEqual(options.originalBytes, 128 * kb)
    }

    func testAResizedSaveIsTheStartOfTheOriginal() throws {
        let save = Self.save(128 * kb, writing: [0: 0x42, 1557: 0x01])
        let options = BatterySaveSizing.options(for: save, header: Self.header())

        XCTAssertEqual(try BatterySaveSizing.bytes(of: save, size: .original, options: options), save)
        XCTAssertEqual(try BatterySaveSizing.bytes(of: save, size: .minimized, options: options), save.prefix(8 * kb))
        XCTAssertEqual(
            try BatterySaveSizing.bytes(of: save, size: .custom(bytes: 32 * kb), options: options), save.prefix(32 * kb)
        )
    }

    func testAGrownSaveIsTheOriginalFollowedByErasedBytes() throws {
        let save = Self.save(8 * kb, writing: [0: 0x42, 0x1FFF: 0x01])
        let options = BatterySaveSizing.options(for: save, header: Self.header(type: 0x1B, ram: 0x02))

        let grown = try BatterySaveSizing.bytes(of: save, size: .custom(bytes: 32 * kb), options: options)

        XCTAssertEqual(grown.count, 32 * kb)
        XCTAssertEqual(grown.prefix(8 * kb), save)
        XCTAssertEqual(Set(grown.dropFirst(8 * kb)), [0xFF])
        XCTAssertEqual(try BatterySaveSizing.bytes(of: save, size: .original, options: options), save)
    }

    func testASizeThatIsNotOfferedIsRefused() {
        let save = Self.save(128 * kb, writing: [0x2000: 0x01])
        let options = BatterySaveSizing.options(for: save, header: Self.header())

        for size: SaveExportSize in [.custom(bytes: 8 * kb), .custom(bytes: 4 * kb), .custom(bytes: 12_345), .custom(bytes: 256 * kb)] {
            XCTAssertThrowsError(try BatterySaveSizing.bytes(of: save, size: size, options: options), "\(size)") {
                XCTAssertEqual($0 as? SaveExportSizeError, .notOffered)
            }
        }
        let unshrinkable = BatterySaveSizing.options(for: save, header: nil)
        XCTAssertThrowsError(try BatterySaveSizing.bytes(of: save, size: .minimized, options: unshrinkable))
    }

    private static func save(_ size: Int, writing bytes: [Int: UInt8]) -> Data {
        var data = Data(repeating: 0xFF, count: size)
        for (offset, byte) in bytes { data[offset] = byte }
        return data
    }

    private static func header(type: UInt8 = 0x1B, ram: UInt8 = 0x04) -> GBROMHeader {
        GBROMHeader(
            title: "TEST", system: .gameBoyColor, cgbFlag: 0x80, cartridgeType: type, romSizeCode: 0x06,
            ramSizeCode: ram, headerChecksum: 0, headerChecksumValid: true, globalChecksum: 0, globalChecksumValid: true
        )
    }
}

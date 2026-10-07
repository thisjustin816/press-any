import EmulatorKitTestSupport
import Foundation
import Importing
import XCTest

final class ROMComparisonTests: XCTestCase {
    func testIdenticalImagesHaveNoChanges() {
        let rom = TestROM.make(title: "IDENTICAL")
        let result = ROMComparison.compare(rom, rom)

        XCTAssertTrue(result.isIdentical)
        XCTAssertEqual(result.oldSize, 0x8000)
        XCTAssertEqual(result.newSize, 0x8000)
        XCTAssertEqual(result.changedByteCount, 0)
        XCTAssertEqual(result.addedByteCount, 0)
        XCTAssertEqual(result.removedByteCount, 0)
        XCTAssertEqual(result.changedRanges, [])
        XCTAssertEqual(result.oldBankCount, 2)
        XCTAssertEqual(result.newBankCount, 2)
        XCTAssertEqual(result.changedBanks, [])
        XCTAssertEqual(result.addedBanks, [])
        XCTAssertEqual(result.removedBanks, [])
        XCTAssertEqual(result.headerChanges, [])
    }

    func testOneChangedByteInBankThree() {
        let old = TestROM.make(title: "BANKS") + Data(repeating: 0, count: 0x8000)
        var new = old
        new[0xc123] = 1

        let result = ROMComparison.compare(old, new)

        XCTAssertFalse(result.isIdentical)
        XCTAssertEqual(result.changedByteCount, 1)
        XCTAssertEqual(result.changedRanges, [0xc123..<0xc124])
        XCTAssertEqual(result.changedBanks, [.init(index: 3, changedByteCount: 1)])
        XCTAssertEqual(result.headerChanges, [])
    }

    func testChangedRunCrossesBankBoundary() {
        let old = TestROM.make(title: "BOUNDARY") + Data(repeating: 0, count: 0x4000)
        var new = old
        new.replaceSubrange(0x7ffe..<0x8003, with: [1, 2, 3, 4, 5])

        let result = ROMComparison.compare(old, new)

        XCTAssertEqual(result.changedByteCount, 5)
        XCTAssertEqual(result.changedRanges, [0x7ffe..<0x8003])
        XCTAssertEqual(result.changedBanks, [
            .init(index: 1, changedByteCount: 2), .init(index: 2, changedByteCount: 3),
        ])
    }

    func testSeparateRunsInOneBankSumTheirChangedBytes() {
        let old = TestROM.make(title: "RUNS")
        var new = old
        new.replaceSubrange(0x4001..<0x4003, with: [1, 1])
        new.replaceSubrange(0x4004..<0x4007, with: [1, 1, 1])

        let result = ROMComparison.compare(old, new)

        XCTAssertEqual(result.changedByteCount, 5)
        XCTAssertEqual(result.changedRanges, [0x4001..<0x4003, 0x4004..<0x4007])
        XCTAssertEqual(result.changedBanks, [.init(index: 1, changedByteCount: 5)])
    }

    func testGrowthAddsBytesAndBanksWithoutChangingSharedBytes() {
        let old = TestROM.make(title: "GROWTH")
        let new = old + Data(repeating: 1, count: 0x8000)
        let result = ROMComparison.compare(old, new)

        XCTAssertFalse(result.isIdentical)
        XCTAssertEqual(result.oldSize, 0x8000)
        XCTAssertEqual(result.newSize, 0x10000)
        XCTAssertEqual(result.addedByteCount, 0x8000)
        XCTAssertEqual(result.removedByteCount, 0)
        XCTAssertEqual(result.changedByteCount, 0)
        XCTAssertEqual(result.changedRanges, [])
        XCTAssertEqual(result.oldBankCount, 2)
        XCTAssertEqual(result.newBankCount, 4)
        XCTAssertEqual(result.changedBanks, [])
        XCTAssertEqual(result.addedBanks, [2, 3])
        XCTAssertEqual(result.removedBanks, [])
        XCTAssertEqual(result.headerChanges, [])
    }

    func testShrinkageRemovesBytesAndBanks() {
        let new = TestROM.make(title: "SHRINK")
        let old = new + Data(repeating: 1, count: 0x8000)
        let result = ROMComparison.compare(old, new)

        XCTAssertFalse(result.isIdentical)
        XCTAssertEqual(result.oldSize, 0x10000)
        XCTAssertEqual(result.newSize, 0x8000)
        XCTAssertEqual(result.addedByteCount, 0)
        XCTAssertEqual(result.removedByteCount, 0x8000)
        XCTAssertEqual(result.changedByteCount, 0)
        XCTAssertEqual(result.changedRanges, [])
        XCTAssertEqual(result.oldBankCount, 4)
        XCTAssertEqual(result.newBankCount, 2)
        XCTAssertEqual(result.changedBanks, [])
        XCTAssertEqual(result.addedBanks, [])
        XCTAssertEqual(result.removedBanks, [2, 3])
    }

    func testTitleCartridgeTypeAndUpdatedHeaderChecksumAreListed() throws {
        let old = TestROM.make(title: "TITLE")
        var new = old
        new[0x134] = Character("N").asciiValue!
        new[0x147] = 1
        var checksum: UInt8 = 0
        for offset in 0x134...0x14c { checksum = checksum &- new[offset] &- 1 }
        new[0x14d] = checksum

        let result = ROMComparison.compare(old, new)

        XCTAssertEqual(result.headerChanges, [
            .title(old: "TITLE", new: "NITLE"),
            .cartridgeType(old: 0, new: 1),
            .headerChecksum(old: try GBROMHeaderParser.parse(old).headerChecksum, new: checksum),
        ])
    }

    func testEveryOtherHeaderFieldIsComparedWithItsStoredValue() {
        let old = TestROM.make(title: "FIELDS")
        var new = old
        new[0x143] = 0xc0
        new[0x148] = 2
        new[0x149] = 3
        new[0x14c] = 4
        new[0x14e] = 0xab
        new[0x14f] = 0xcd
        let oldGlobal = UInt16(old[0x14e]) << 8 | UInt16(old[0x14f])

        XCTAssertEqual(ROMComparison.compare(old, new).headerChanges, [
            .system(old: .gameBoy, new: .gameBoyColor),
            .cgbFlag(old: 0, new: 0xc0),
            .romSizeCode(old: 0, new: 2),
            .ramSizeCode(old: 0, new: 3),
            .globalChecksum(old: oldGlobal, new: 0xabcd),
            .revisionNumber(old: 0, new: 4),
        ])
    }

    func testShortHeaderIsUnavailableInEitherDirectionWhileBytesStillCompare() {
        let full = TestROM.make(title: "SHORT")
        var short = Data(full.prefix(0x100))
        short[0xff] = 1

        for (old, new) in [(short, full), (full, short)] {
            let result = ROMComparison.compare(old, new)
            XCTAssertNil(result.headerChanges)
            XCTAssertFalse(result.isIdentical)
            XCTAssertEqual(result.changedByteCount, 1)
            XCTAssertEqual(result.changedRanges, [0xff..<0x100])
            XCTAssertEqual(result.changedBanks, [.init(index: 0, changedByteCount: 1)])
        }
    }

    func testPartialBanksAndChangesAtBothEndsOfSharedBytes() {
        let old = TestROM.make(title: "PARTIAL") + Data([0, 0, 0])
        var new = old
        new[0] = 1
        new[0x8002] = 1
        new.append(1)

        let result = ROMComparison.compare(old, new)

        XCTAssertEqual(result.oldBankCount, 3)
        XCTAssertEqual(result.newBankCount, 3)
        XCTAssertEqual(result.addedByteCount, 1)
        XCTAssertEqual(result.changedByteCount, 2)
        XCTAssertEqual(result.changedRanges, [0..<1, 0x8002..<0x8003])
        XCTAssertEqual(result.changedBanks, [
            .init(index: 0, changedByteCount: 1), .init(index: 2, changedByteCount: 1),
        ])
        XCTAssertEqual(result.addedBanks, [])
        XCTAssertEqual(result.removedBanks, [])
    }

    func testEmptyImagesAndAnEmptySharedLength() {
        let empty = ROMComparison.compare(Data(), Data())
        XCTAssertTrue(empty.isIdentical)
        XCTAssertEqual(empty.oldBankCount, 0)
        XCTAssertEqual(empty.newBankCount, 0)
        XCTAssertEqual(empty.changedRanges, [])
        XCTAssertNil(empty.headerChanges)

        let rom = TestROM.make(title: "EMPTY")
        for (old, new) in [(Data(), rom), (rom, Data())] {
            let result = ROMComparison.compare(old, new)
            XCTAssertFalse(result.isIdentical)
            XCTAssertEqual(result.changedByteCount, 0)
            XCTAssertEqual(result.changedRanges, [])
            XCTAssertEqual(result.changedBanks, [])
            XCTAssertEqual(result.addedBanks, old.isEmpty ? [0, 1] : [])
            XCTAssertEqual(result.removedBanks, new.isEmpty ? [0, 1] : [])
            XCTAssertNil(result.headerChanges)
        }
    }

    func testSlicedImagesUseOffsetsFromTheStartOfEachImage() {
        let old = TestROM.make(title: "SLICED")
        var new = old
        new[0x4000] = 1
        let framedOld = Data([2, 3]) + old
        let framedNew = Data([4, 5, 6]) + new

        XCTAssertEqual(ROMComparison.compare(framedOld[2...], framedNew[3...]), ROMComparison.compare(old, new))
    }

    func testEightMiBImageWithAChangeInTheLastBank() {
        let old = TestROM.make(title: "LARGE") + Data(repeating: 0, count: 0x800000 - 0x8000)
        var new = old
        new[0x7fffff] = 1

        let result = ROMComparison.compare(old, new)

        XCTAssertEqual(result.oldBankCount, 512)
        XCTAssertEqual(result.newBankCount, 512)
        XCTAssertEqual(result.changedByteCount, 1)
        XCTAssertEqual(result.changedRanges, [0x7fffff..<0x800000])
        XCTAssertEqual(result.changedBanks, [.init(index: 511, changedByteCount: 1)])
    }
}

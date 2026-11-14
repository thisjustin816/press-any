import EmulationCore
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import XCTest
@testable import SameBoyAdapter

final class SameBoySaveSizeTests: XCTestCase {
    func testASaveExportedAtTheMinimumLoadsBackAtTheFullSize() throws {
        try SameBoyAdapterTests.requireGeneratedBootROMs()
        let core = SameBoyAdapter()
        // MBC5 with RAM and a battery, 128 KB of RAM.
        let rom = TestROM.make(title: "BIG RAM", cgb: true, cartridgeType: 0x1B, ramSizeCode: 0x04)
        try core.loadImage(rom, system: .gameBoyColor)
        var original = Data(repeating: 0xFF, count: 128 * 1024)
        for offset in 0..<1558 { original[offset] = UInt8(truncatingIfNeeded: offset &* 7) }

        try core.loadPersistentSave(Data(original.prefix(8 * 1024)))

        XCTAssertEqual(try core.persistentSaveData(), original, "the banks that were trimmed come back erased")
    }

    func testASaveExportedLargerLoadsBackAtTheSizeTheGameDeclares() throws {
        try SameBoyAdapterTests.requireGeneratedBootROMs()
        let core = SameBoyAdapter()
        // MBC5 with RAM and a battery, 8 KB of RAM.
        let rom = TestROM.make(title: "SMALL RAM", cgb: true, cartridgeType: 0x1B, ramSizeCode: 0x02)
        try core.loadImage(rom, system: .gameBoyColor)
        var original = Data(repeating: 0xFF, count: 8 * 1024)
        for offset in 0..<1558 { original[offset] = UInt8(truncatingIfNeeded: offset &* 7) }

        try core.loadPersistentSave(original + Data(repeating: 0xFF, count: 24 * 1024))

        XCTAssertEqual(try core.persistentSaveData(), original, "the padding past the declared RAM is dropped")
    }
}

final class SameBoyCartridgeClockSaveTests: XCTestCase {
    /// SameBoy writes an MBC3 cartridge's clock and the host time after its RAM on every read, so
    /// the save differs a second later though the game wrote nothing.
    func testAClockThatOnlyKeptTimeIsNoChangeButTheGameSavingIs() throws {
        try SameBoyAdapterTests.requireGeneratedBootROMs()
        let core = SameBoyAdapter()
        // MBC3+TIMER+RAM+BATTERY, 32 KB of RAM.
        let rom = TestROM.make(title: "CLOCK", cartridgeType: 0x10, ramSizeCode: 0x03)
        try core.loadImage(rom, system: .gameBoy)
        for _ in 0..<10 { _ = try core.runFrame(input: .init()) }
        let first = try core.persistentSaveData()
        Thread.sleep(forTimeInterval: 1.2)
        for _ in 0..<10 { _ = try core.runFrame(input: .init()) }
        let later = try core.persistentSaveData()
        XCTAssertEqual(first.count, 32 * 1024 + 48)
        XCTAssertNotEqual(first, later, "the clock and host time moved")
        XCTAssertFalse(core.persistentSaveChanged(from: first, to: later))

        var saved = later
        saved[0] ^= 0xFF
        XCTAssertTrue(core.persistentSaveChanged(from: first, to: saved), "a change to the RAM is a save")
    }

    func testACartridgeWithoutAClockIsComparedByteForByte() throws {
        try SameBoyAdapterTests.requireGeneratedBootROMs()
        let core = SameBoyAdapter()
        let rom = TestROM.make(title: "NO CLOCK", cartridgeType: 0x1B, ramSizeCode: 0x02)
        try core.loadImage(rom, system: .gameBoy)
        let save = try core.persistentSaveData()
        var changed = save
        changed[changed.count - 1] ^= 1
        XCTAssertFalse(core.persistentSaveChanged(from: save, to: save))
        XCTAssertTrue(core.persistentSaveChanged(from: save, to: changed), "the last bytes are RAM, not a clock")
    }
}

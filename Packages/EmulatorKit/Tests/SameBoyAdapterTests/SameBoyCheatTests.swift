import EmulationCore
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import XCTest
@testable import SameBoyAdapter

final class SameBoyCheatTests: XCTestCase {
    // The program writes 0x11 to C000 once, then copies C000 to C001 and the ROM byte at 4000 to
    // C002 over and over. C001 and C002 hold what the game read, cheats included.
    private static let program: [UInt8] = [
        0x3e, 0x11,       // ld a, $11
        0xea, 0x00, 0xc0, // ld [$C000], a
        0xfa, 0x00, 0xc0, // ld a, [$C000]
        0xea, 0x01, 0xc0, // ld [$C001], a
        0xfa, 0x00, 0x40, // ld a, [$4000]
        0xea, 0x02, 0xc0, // ld [$C002], a
        0x18, 0xf2,       // jr back to the read of C000
    ]
    /// GameShark: 0x42 at C000, in any bank.
    private static let gameShark = "014200C0"
    /// Game Genie: 0x99 at 4000.
    private static let gameGenie = "990-00B"
    /// Game Genie: 0x99 at 4000, only while the ROM holds 0x00 there.
    private static let gameGenieWithCompare = "990-00B-EFA"

    func testAGameSharkCodeChangesWhatTheGameReadsFromRAMUntilItIsOff() throws {
        for system in [GameSystem.gameBoy, .gameBoyColor] {
            let core = try booted(system)
            XCTAssertEqual(try ramCopy(core), 0x11, "\(system)")
            try core.setCheatCodes([Self.gameShark])
            XCTAssertEqual(try ramCopy(core), 0x42, "\(system)")
            core.setCheatsEnabled(false)
            XCTAssertEqual(try ramCopy(core), 0x11, "\(system)")
            core.setCheatsEnabled(true)
            XCTAssertEqual(try ramCopy(core), 0x42, "\(system)")
            try core.setCheatCodes([])
            XCTAssertEqual(try ramCopy(core), 0x11, "\(system)")
        }
    }

    func testAGameGenieCodeChangesTheByteReadFromROM() throws {
        let core = try booted(.gameBoy)
        XCTAssertEqual(try romCopy(core), 0x00)
        try core.setCheatCodes([Self.gameGenie])
        XCTAssertEqual(try romCopy(core), 0x99)
        core.setCheatsEnabled(false)
        XCTAssertEqual(try romCopy(core), 0x00)
        core.setCheatsEnabled(true)
        try core.setCheatCodes([Self.gameGenieWithCompare])
        XCTAssertEqual(try romCopy(core), 0x99)
        try core.setCheatCodes([])
        XCTAssertEqual(try romCopy(core), 0x00)

        // The compare value names the byte the ROM must hold for the code to apply.
        let other = try booted(.gameBoy, payloadByte: 0x01)
        try other.setCheatCodes([Self.gameGenieWithCompare])
        XCTAssertEqual(try romCopy(other), 0x01)
    }

    func testReplacingTheSetRemovesTheOldCodes() throws {
        let core = try booted(.gameBoy)
        try core.setCheatCodes([Self.gameShark, Self.gameGenie])
        XCTAssertEqual(try ramCopy(core), 0x42)
        XCTAssertEqual(try romCopy(core), 0x99)
        try core.setCheatCodes([Self.gameGenie])
        XCTAssertEqual(try ramCopy(core), 0x11)
        XCTAssertEqual(try romCopy(core), 0x99)
        XCTAssertEqual(core.cheatCodes, [Self.gameGenie])
    }

    func testMalformedCodesAreRefusedAndKeepTheActiveSet() throws {
        let core = SameBoyAdapter()
        for code in [Self.gameShark, Self.gameGenie, "990-00b", Self.gameGenieWithCompare, "99000B"] {
            XCTAssertTrue(core.isValidCheatCode(code), code)
        }
        // SameBoy itself refuses 123-456: it names an address past the ROM.
        for code in ["", "ZZZ-ZZZ", "123-456", "014200C", "014200C00", "+14200C0", " 14200C0", "0x4200C0",
                     "0142-00C0", "990-00B-EFA-123", "-990-00B", "990-00B-", "990 00B"] {
            XCTAssertFalse(core.isValidCheatCode(code), code)
        }

        let booted = try booted(.gameBoy)
        try booted.setCheatCodes([Self.gameShark])
        XCTAssertThrowsError(try booted.setCheatCodes([Self.gameGenie, "123-456"])) { error in
            XCTAssertEqual(error as? SameBoyAdapterError, .cheatCodeRefused)
        }
        XCTAssertEqual(booted.cheatCodes, [Self.gameShark])
        XCTAssertEqual(try ramCopy(booted), 0x42)
        XCTAssertEqual(try romCopy(booted), 0x00)
    }

    func testCheatsStayThroughStatesResetsAndNewImagesAndCanBeSetFirst() throws {
        try SameBoyAdapterTests.requireGeneratedBootROMs()
        let core = SameBoyAdapter()
        XCTAssertThrowsError(try core.setCheatCodes(["nope"]))
        try core.setCheatCodes([Self.gameShark])
        try core.loadImage(rom(), system: .gameBoy)
        XCTAssertTrue(try core.skipBootAnimation())
        XCTAssertEqual(try ramCopy(core), 0x42)

        // A state taken with cheats off loads with the cheats that are on now.
        core.setCheatsEnabled(false)
        XCTAssertEqual(try ramCopy(core), 0x11)
        let state = try core.serializeState()
        core.setCheatsEnabled(true)
        try core.deserializeState(state)
        XCTAssertEqual(try ramCopy(core), 0x42)

        try core.reset()
        XCTAssertTrue(try core.skipBootAnimation())
        XCTAssertEqual(try ramCopy(core), 0x42)

        try core.loadImage(rom(), system: .gameBoyColor)
        XCTAssertTrue(try core.skipBootAnimation())
        XCTAssertEqual(try ramCopy(core), 0x42)
        core.setCheatsEnabled(false)
        try core.loadImage(rom(), system: .gameBoy)
        XCTAssertTrue(try core.skipBootAnimation())
        XCTAssertEqual(try ramCopy(core), 0x11)
    }

    private func rom(payloadByte: UInt8 = 0) -> Data {
        TestROM.make(title: "CHEATS", payloadByte: payloadByte, program: Self.program)
    }

    private func booted(_ system: GameSystem, payloadByte: UInt8 = 0) throws -> SameBoyAdapter {
        try SameBoyAdapterTests.requireGeneratedBootROMs()
        let core = SameBoyAdapter()
        try core.loadImage(rom(payloadByte: payloadByte), system: system)
        XCTAssertTrue(try core.skipBootAnimation())
        return core
    }

    /// Runs two frames, so the program copies again, then reads its copy of C000.
    private func ramCopy(_ core: SameBoyAdapter) throws -> UInt8? {
        for _ in 0..<2 { _ = try core.runFrame(input: .init()) }
        return core.readMemory(0xc001)
    }

    private func romCopy(_ core: SameBoyAdapter) throws -> UInt8? {
        for _ in 0..<2 { _ = try core.runFrame(input: .init()) }
        return core.readMemory(0xc002)
    }
}

import EmulationCore
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import XCTest
@testable import SameBoyAdapter

final class SameBoyHardwareModelTests: XCTestCase {
    /// Each boot ROM hands off with registers that tell the hardware apart, as games read them:
    /// A is 0x01 on DMG and SGB, 0xFF on Pocket and SGB2, and 0x11 on GBC and GBA; B's lowest bit
    /// is set only on a GBA.
    func testEveryModelBootsItsOwnHardwareFromItsOwnBootROM() throws {
        try SameBoyAdapterTests.requireGeneratedBootROMs()
        let expected: [(HardwareModel, a: UInt8, gba: Bool)] = [
            (.gameBoy, 0x01, false),
            (.gameBoyPocket, 0xff, false),
            (.superGameBoy, 0x01, false),
            (.superGameBoy2, 0xff, false),
            (.gameBoyColor, 0x11, false),
            (.gameBoyAdvance, 0x11, true),
            (.gameBoyPlayer, 0x11, true),
        ]
        for (model, a, gba) in expected {
            for system in [GameSystem.gameBoy, .gameBoyColor] {
                let core = SameBoyAdapter()
                try core.setHardwareModel(model)
                try core.loadImage(TestROM.make(title: "MODEL", cgb: system == .gameBoyColor), system: system)
                XCTAssertEqual(core.runningModel, model)
                XCTAssertTrue(try core.skipBootAnimation(), "\(model) \(system)")
                let registers = try XCTUnwrap(core.registers())
                XCTAssertEqual(registers.pc, 0x100, "\(model) \(system) reached the game")
                XCTAssertEqual(registers.a, a, "\(model) \(system)")
                XCTAssertEqual(registers.b & 1 == 1, gba, "\(model) \(system)")

                let frame = try core.runFrame(input: .init())
                XCTAssertEqual(frame.width, 160, "\(model) draws no border")
                XCTAssertEqual(frame.height, 144)
                XCTAssertEqual(frame.bgra8888.count, 160 * 144 * 4)
            }
        }
    }

    func testAutomaticRunsTheGameOnItsSystem() throws {
        try SameBoyAdapterTests.requireGeneratedBootROMs()
        let core = SameBoyAdapter()
        try core.loadImage(TestROM.make(title: "AUTO"), system: .gameBoy)
        XCTAssertEqual(core.runningModel, .gameBoy)
        try core.loadImage(TestROM.make(title: "AUTO", cgb: true), system: .gameBoyColor)
        XCTAssertEqual(core.runningModel, .gameBoyColor)
        XCTAssertTrue(try core.skipBootAnimation())
        XCTAssertEqual(core.registers()?.a, 0x11)
    }

    func testSwitchingModelsRestartsTheGameOnTheNewHardwareKeepingItsSave() throws {
        try SameBoyAdapterTests.requireGeneratedBootROMs()
        let core = SameBoyAdapter()
        // MBC1 with RAM and a battery, 8 KB of RAM.
        let rom = TestROM.make(title: "SWITCH", cgb: true, cartridgeType: 0x03, ramSizeCode: 0x02)
        try core.loadImage(rom, system: .gameBoyColor)
        let battery = Data((0..<8192).map { UInt8(truncatingIfNeeded: $0 &* 7) })
        try core.loadPersistentSave(battery)
        try core.setCheatCodes(["01FFC0C0"])
        XCTAssertTrue(try core.skipBootAnimation())
        for _ in 0..<3 { _ = try core.runFrame(input: .init()) }

        try core.setHardwareModel(.gameBoy)
        XCTAssertEqual(core.runningModel, .gameBoy)
        XCTAssertEqual(try core.persistentSaveData().prefix(8192), battery, "the save comes along")
        XCTAssertEqual(core.cheatCodes, ["01FFC0C0"])
        XCTAssertTrue(try core.skipBootAnimation(), "the game starts again from its boot")
        XCTAssertEqual(core.registers()?.a, 0x01, "on a Game Boy, without the Game Boy Color's fast boot")
        XCTAssertEqual(core.readMemory(0xc0c0), 0xff, "with its cheats")

        try core.setHardwareModel(.automatic)
        XCTAssertEqual(core.runningModel, .gameBoyColor, "Automatic goes back to the game's own system")
        XCTAssertEqual(try core.persistentSaveData().prefix(8192), battery)
    }

    func testChoosingTheModelTheGameAlreadyRunsOnLeavesItRunning() throws {
        try SameBoyAdapterTests.requireGeneratedBootROMs()
        let core = SameBoyAdapter()
        try core.loadImage(TestROM.make(title: "SAME", cgb: true), system: .gameBoyColor)
        XCTAssertTrue(try core.skipBootAnimation())
        _ = try core.runFrame(input: .init())
        let state = try core.serializeState()

        try core.setHardwareModel(.gameBoyColor)
        XCTAssertEqual(core.hardwareModel, .gameBoyColor)
        XCTAssertEqual(try core.serializeState(), state, "Game Boy Color is what Automatic already runs it on")
    }

    func testAStateLoadsOnlyOnHardwareOfItsFamilyAndSaysWhichItNeeds() throws {
        try SameBoyAdapterTests.requireGeneratedBootROMs()
        let rom = TestROM.make(title: "STATES", cgb: true)
        var states: [HardwareModel: Data] = [:]
        for model in HardwareModel.allCases where model != .automatic {
            let core = SameBoyAdapter()
            try core.setHardwareModel(model)
            try core.loadImage(rom, system: .gameBoyColor)
            XCTAssertTrue(try core.skipBootAnimation())
            _ = try core.runFrame(input: .init())
            states[model] = try core.serializeState()
            XCTAssertEqual(SameBoyAdapter.stateFamily(try XCTUnwrap(states[model])), model.family, "\(model)")
        }

        for (stateModel, state) in states {
            for model in HardwareModel.allCases where model != .automatic {
                let core = SameBoyAdapter()
                try core.setHardwareModel(model)
                try core.loadImage(rom, system: .gameBoyColor)
                if stateModel.family == model.family {
                    XCTAssertNoThrow(try core.deserializeState(state), "\(stateModel) state on \(model)")
                } else {
                    XCTAssertThrowsError(try core.deserializeState(state), "\(stateModel) state on \(model)") { error in
                        XCTAssertEqual(error as? StateNeedsOtherHardware, StateNeedsOtherHardware(family: try! XCTUnwrap(stateModel.family)))
                    }
                }
            }
        }
        XCTAssertNil(SameBoyAdapter.stateFamily(Data([1, 2, 3])))
        XCTAssertEqual(
            StateNeedsOtherHardware(family: .gameBoyColor).errorDescription,
            "It was made on a Game Boy Color, Game Boy Advance or Game Boy Player. Set Model to one of those to load it."
        )
    }

    func testSuperGameBoyIgnoresTheGameBoyScreenColors() throws {
        try SameBoyAdapterTests.requireGeneratedBootROMs()
        let core = SameBoyAdapter()
        try core.setHardwareModel(.superGameBoy)
        try core.loadImage(TestROM.make(title: "SGBCOLORS"), system: .gameBoy)
        XCTAssertTrue(try core.skipBootAnimation())
        for _ in 0..<90 { _ = try core.runFrame(input: .init()) }
        let green = try XCTUnwrap(core.setDisplaySettings(colorCorrection: .balanced, dmgPalette: .dmgGreen))
        let pocket = try XCTUnwrap(core.setDisplaySettings(colorCorrection: .balanced, dmgPalette: .pocket))
        XCTAssertEqual(green.bgra8888, pocket.bgra8888)
    }
}

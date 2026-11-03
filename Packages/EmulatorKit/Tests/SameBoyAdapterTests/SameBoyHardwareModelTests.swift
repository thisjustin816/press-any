import EmulationCore
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import XCTest
@testable import SameBoyAdapter

final class SameBoyHardwareModelTests: XCTestCase {
    func testSGBModelsShareTheirDisplayPresetButKeepTheirOwnClock() throws {
        try SameBoyAdapterTests.requireGeneratedBootROMs()
        XCTAssertEqual(
            GameplayPresetValues.values(for: .accurate, hardware: .superGameBoy),
            GameplayPresetValues.values(for: .accurate, hardware: .superGameBoy2)
        )
        func frameDuration(_ model: HardwareModel) throws -> UInt64 {
            let core = SameBoyAdapter()
            try core.setHardwareModel(model)
            try core.loadImage(TestROM.make(title: "SGB CLOCK"), system: .gameBoy)
            XCTAssertTrue(try core.skipBootAnimation())
            _ = try core.runFrame(input: .init())
            return try core.runFrame(input: .init()).emulatedNanoseconds
        }
        let sgb1 = try frameDuration(.superGameBoy)
        let sgb2 = try frameDuration(.superGameBoy2)
        XCTAssertLessThan(Double(sgb1), Double(sgb2) * 0.99)
        XCTAssertEqual(Double(sgb2) / Double(sgb1), 1.0241, accuracy: 0.001)
    }

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

    func testAutomaticRunsTheGameOnTheHardwareItsHeaderSuits() throws {
        try SameBoyAdapterTests.requireGeneratedBootROMs()
        let core = SameBoyAdapter()
        try core.loadImage(TestROM.make(title: "AUTO"), system: .gameBoy)
        XCTAssertEqual(core.runningModel, .gameBoyPocket)
        try core.loadImage(TestROM.make(title: "AUTO", sgbFlag: 0x03, oldLicensee: 0x33), system: .gameBoy)
        XCTAssertEqual(core.runningModel, .superGameBoy2)
        try core.loadImage(TestROM.make(title: "AUTO", oldLicensee: 0x01), system: .gameBoy)
        XCTAssertEqual(core.runningModel, .gameBoyColor)
        try core.loadImage(TestROM.make(title: "AUTO", cgb: true, sgbFlag: 0x03, oldLicensee: 0x33), system: .gameBoyColor)
        XCTAssertEqual(core.runningModel, .gameBoyColor)
        try core.loadImage(TestROM.make(title: "AUTO", cgb: true), system: .gameBoyColor)
        XCTAssertEqual(core.runningModel, .gameBoyColor)
        XCTAssertTrue(try core.skipBootAnimation())
        XCTAssertEqual(core.registers()?.a, 0x11)
    }

    /// The Super Game Boy fixture, on Automatic, runs on a Super Game Boy 2 and colors the picture
    /// with the palette it sends. Its border isn't drawn: Scripts/tests/sameboy_sgb_border.c checks
    /// that on SameBoy directly.
    func testTheSuperGameBoyFixtureColorsThePictureWithThePaletteItSends() throws {
        try SameBoyAdapterTests.requireGeneratedBootROMs()
        let core = SameBoyAdapter()
        _ = try core.setDisplaySettings(colorCorrection: .off, dmgPalette: .dmgGreen, advanceColors: .gameBoyAdvance)
        try core.loadImage(TestROMFixtures.rom("sgb-packets.gb"), system: .gameBoy)
        XCTAssertEqual(core.runningModel, .superGameBoy2)
        var frame = try core.runFrame(input: .init())
        for _ in 0..<600 { frame = try core.runFrame(input: .init()) }
        XCTAssertEqual(frame.width, 160, "no border in the picture")
        func pixel(_ x: Int, _ y: Int) -> UInt32 {
            let offset = (y * frame.width + x) * 4
            return frame.bgra8888[offset..<offset + 4].reversed().reduce(0) { $0 << 8 | UInt32($1) } & 0xFFFFFF
        }
        func rgb555(_ r: UInt32, _ g: UInt32, _ b: UInt32) -> UInt32 {
            (r << 3 | r >> 2) << 16 | (g << 3 | g >> 2) << 8 | (b << 3 | b >> 2)
        }
        XCTAssertEqual(pixel(159, 143), rgb555(31, 29, 20), "cream color 0")
        XCTAssertEqual(pixel(7 * 8, 76), rgb555(31, 16, 4), "orange")
        XCTAssertEqual(pixel(11 * 8, 76), rgb555(2, 16, 18), "teal")
        XCTAssertEqual(pixel(15 * 8, 76), rgb555(3, 3, 10), "navy")
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
            // A Game Boy Player writes the same model as a Game Boy Advance.
            XCTAssertEqual(core.hardwareModel(ofState: try XCTUnwrap(states[model])), model == .gameBoyPlayer ? .gameBoyAdvance : model)
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
        XCTAssertNil(SameBoyAdapter().hardwareModel(ofState: Data([1, 2, 3])))
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
        let green = try XCTUnwrap(core.setDisplaySettings(colorCorrection: .balanced, dmgPalette: .dmgGreen, advanceColors: .gameBoyAdvance))
        let pocket = try XCTUnwrap(core.setDisplaySettings(colorCorrection: .balanced, dmgPalette: .pocket, advanceColors: .gameBoyAdvance))
        XCTAssertEqual(green.bgra8888, pocket.bgra8888)
    }

    /// A game that sets its background color, on each model and screen. The picture's corner shows
    /// that color.
    private static let backgroundColorROM: Data = {
        // Background palette 0, color 0: r 11, g 20, b 6, then wait.
        let color: UInt16 = 11 | 20 << 5 | 6 << 10
        let program: [UInt8] = [
            0x3e, 0x80, 0xe0, 0x68,
            0x3e, UInt8(color & 0xff), 0xe0, 0x69,
            0x3e, UInt8(color >> 8), 0xe0, 0x69,
            0x18, 0xfe,
        ]
        return TestROM.make(title: "ADVANCE", cgb: true, program: program)
    }()

    private func corner(_ model: HardwareModel, _ correction: ColorCorrection, _ colors: AdvanceColors) throws -> UInt32 {
        let core = SameBoyAdapter()
        try core.setHardwareModel(model)
        try core.loadImage(Self.backgroundColorROM, system: .gameBoyColor)
        _ = try core.setDisplaySettings(colorCorrection: correction, dmgPalette: .dmgGreen, advanceColors: colors)
        XCTAssertTrue(try core.skipBootAnimation())
        var frame = try core.runFrame(input: .init())
        for _ in 0..<4 { frame = try core.runFrame(input: .init()) }
        return frame.bgra8888.withUnsafeBytes { $0.load(as: UInt32.self) }
    }

    func testAGameBoyAdvanceCanShowItsColorsAsAGameBoyColorWould() throws {
        try SameBoyAdapterTests.requireGeneratedBootROMs()
        for correction in ColorCorrection.allCases {
            let gbc = try corner(.gameBoyColor, correction, .gameBoyAdvance)
            let gba = try corner(.gameBoyAdvance, correction, .gameBoyAdvance)
            for model in [HardwareModel.gameBoyAdvance, .gameBoyPlayer] {
                XCTAssertEqual(try corner(model, correction, .gameBoyColor), gbc, "\(model) \(correction)")
            }
            XCTAssertEqual(try corner(.gameBoyColor, correction, .gameBoyColor), gbc, "a Game Boy Color ignores it")
            if correction == .off {
                XCTAssertEqual(gba, gbc, "Original is the same on both screens")
            } else {
                XCTAssertNotEqual(gba, gbc, "the Game Boy Advance screen is darker with \(correction)")
            }
        }
    }

    func testGameBoyColorColorsOnAGameBoyAdvanceChangeWhileThePictureIsPaused() throws {
        try SameBoyAdapterTests.requireGeneratedBootROMs()
        let core = SameBoyAdapter()
        try core.setHardwareModel(.gameBoyAdvance)
        try core.loadImage(Self.backgroundColorROM, system: .gameBoyColor)
        XCTAssertTrue(try core.skipBootAnimation())
        for _ in 0..<5 { _ = try core.runFrame(input: .init()) }
        let state = try core.serializeState()
        let advance = try XCTUnwrap(core.setDisplaySettings(colorCorrection: .balanced, dmgPalette: .dmgGreen, advanceColors: .gameBoyAdvance))
        let color = try XCTUnwrap(core.setDisplaySettings(colorCorrection: .balanced, dmgPalette: .dmgGreen, advanceColors: .gameBoyColor))
        XCTAssertNotEqual(color.bgra8888, advance.bgra8888)
        XCTAssertEqual(try core.serializeState(), state, "the game doesn't move")
        try core.setHardwareModel(.gameBoyPlayer)
        XCTAssertEqual(core.advanceColors, .gameBoyColor, "the choice stays through a model change")
    }
}

import EmulationCore
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import XCTest
@testable import SameBoyAdapter

final class SameBoyDisplayTests: XCTestCase {
    func testDMGPalettesMatchSameBoyColorsForEveryPixel() throws {
        let core = try booted(.gameBoy)
        let state = try core.serializeState()
        let grey = try XCTUnwrap(core.setDisplaySettings(colorCorrection: .balanced, dmgPalette: .grey))
        let shades: [UInt32] = [0xff000000, 0xff555555, 0xffaaaaaa, 0xffffffff]
        let palettes: [(DMGPalette, [UInt32])] = [
            (.grey, shades),
            (.dmgGreen, [0xff081810, 0xff396139, 0xff84a563, 0xffc6de8c]),
            (.pocket, [0xff07100e, 0xff3a4c3a, 0xff818d66, 0xffc2ce93]),
            (.light, [0xff0a1c15, 0xff357862, 0xff56b495, 0xff7fe2c3]),
        ]
        let original = pixels(grey)
        XCTAssertGreaterThan(Set(original).count, 1)
        for (palette, colors) in palettes {
            try core.deserializeState(state)
            let frame = try XCTUnwrap(core.setDisplaySettings(colorCorrection: .balanced, dmgPalette: palette))
            let expected = try original.map { pixel in
                colors[try XCTUnwrap(shades.firstIndex(of: pixel))]
            }
            XCTAssertEqual(pixels(frame), expected, "\(palette)")
            if palette != .grey { XCTAssertNotEqual(frame.bgra8888, grey.bgra8888) }
        }
    }

    func testGBCModesChangeColorsAndBalancedIsTheDefault() throws {
        let core = try booted(.gameBoyColor)
        let state = try core.serializeState()
        let defaultFrame = try core.runFrame(input: .init())
        try core.deserializeState(state)
        let balanced = try XCTUnwrap(core.setDisplaySettings(colorCorrection: .balanced, dmgPalette: .grey))
        XCTAssertEqual(defaultFrame.bgra8888, balanced.bgra8888)
        let off = try XCTUnwrap(core.setDisplaySettings(colorCorrection: .off, dmgPalette: .grey))
        XCTAssertNotEqual(off.bgra8888, balanced.bgra8888)
        for mode in ColorCorrection.allCases where mode != .off {
            let corrected = try XCTUnwrap(core.setDisplaySettings(colorCorrection: mode, dmgPalette: .grey))
            XCTAssertNotEqual(corrected.bgra8888, off.bgra8888, "\(mode)")
        }
    }

    func testSettingsSurviveStateLoadResetAndNewImages() throws {
        for system in [GameSystem.gameBoy, .gameBoyColor] {
            let core = try booted(system)
            let state = try core.serializeState()
            let configured = try XCTUnwrap(core.setDisplaySettings(colorCorrection: .lowContrast, dmgPalette: .pocket))
            try core.deserializeState(state)
            XCTAssertEqual(try core.runFrame(input: .init()).bgra8888, configured.bgra8888)
            try core.reset()
            XCTAssertTrue(try core.skipBootAnimation())
            for _ in 0..<8 { _ = try core.runFrame(input: .init()) }
            let afterReset = try core.runFrame(input: .init())
            XCTAssertEqual(afterReset.bgra8888, configured.bgra8888)
            try core.loadImage(TestROMFixtures.rom(fixture(system)), system: system)
            XCTAssertTrue(try core.skipBootAnimation())
            for _ in 0..<8 { _ = try core.runFrame(input: .init()) }
            XCTAssertEqual(try core.runFrame(input: .init()).bgra8888, configured.bgra8888)
        }
    }

    func testPausedPreviewPreservesStateAndDoesNotProduceAudio() throws {
        for system in [GameSystem.gameBoy, .gameBoyColor] {
            let core = try booted(system)
            _ = core.drainAudio(maxFrames: 32768)
            let state = try core.serializeState()
            let preview = try XCTUnwrap(core.setDisplaySettings(colorCorrection: .accurate, dmgPalette: .light))
            XCTAssertEqual(preview.emulatedNanoseconds, 0)
            XCTAssertEqual(try core.serializeState(), state)
            XCTAssertTrue(core.drainAudio(maxFrames: 32768).isEmpty)
            XCTAssertEqual(core.consumeRumbleAmplitude(), 0)
            XCTAssertEqual(try core.runFrame(input: .init()).bgra8888, preview.bgra8888)
        }
    }

    func testSettingsAppliedBeforeLoadingAnImage() throws {
        try SameBoyAdapterTests.requireGeneratedBootROMs()
        let core = SameBoyAdapter()
        XCTAssertNil(try core.setDisplaySettings(colorCorrection: .off, dmgPalette: .dmgGreen))
        try core.loadImage(TestROMFixtures.rom(fixture(.gameBoy)), system: .gameBoy)
        XCTAssertTrue(try core.skipBootAnimation())
        for _ in 0..<8 { _ = try core.runFrame(input: .init()) }
        let frame = try core.runFrame(input: .init())
        XCTAssertTrue(Set(pixels(frame)).isSubset(of: [0xff081810, 0xff396139, 0xff84a563, 0xffc6de8c]))
    }

    private func fixture(_ system: GameSystem) -> String {
        system == .gameBoy ? "rgbds-dmg.gb" : "rgbds-gbc.gbc"
    }

    private func booted(_ system: GameSystem) throws -> SameBoyAdapter {
        try SameBoyAdapterTests.requireGeneratedBootROMs()
        let core = SameBoyAdapter()
        try core.loadImage(TestROMFixtures.rom(fixture(system)), system: system)
        XCTAssertTrue(try core.skipBootAnimation())
        for _ in 0..<8 { _ = try core.runFrame(input: .init()) }
        return core
    }

    private func pixels(_ frame: EmulatorVideoFrame) -> [UInt32] {
        frame.bgra8888.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
    }
}

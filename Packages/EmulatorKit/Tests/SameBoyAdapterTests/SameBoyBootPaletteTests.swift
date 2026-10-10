import EmulationCore
import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import XCTest
@testable import SameBoyAdapter

final class SameBoyBootPaletteTests: XCTestCase {
    private struct Palette {
        let rawValue: String
        let background: [UInt16]
        let obj0: [UInt16]
        let obj1: [UInt16]

        var bootTitle: String? {
            switch rawValue {
            case "cgbOlive": "MOGURANYA"
            case "cgbZelda": "ZELDA"
            case "cgbMarioLand": "SUPER MARIOLAND"
            case "cgbMarioLand2": "MARIOLAND2"
            case "cgbDonkeyKongLand": "DONKEYKONGLAND"
            case "cgbCamera": "POCKETCAMERA"
            default: nil
            }
        }

        var input: EmulatorInputState {
            .init(up: rawValue.hasPrefix("cgbUp"), down: rawValue.hasPrefix("cgbDown"),
                  left: rawValue.hasPrefix("cgbLeft"), right: rawValue.hasPrefix("cgbRight"),
                  a: rawValue.hasSuffix("A"), b: rawValue.hasSuffix("B"))
        }

        var setting: DMGPalette {
            get throws { try XCTUnwrap(DMGPalette(rawValue: rawValue)) }
        }
    }

    // RGB555 values from the pinned cgb_boot.asm, in BGP/OBP shade order (light to dark).
    private let palettes: [Palette] = [
        .init(rawValue: "cgbUp",
              background: [0x7fff, 0x32bf, 0x00d0, 0x0000],
              obj0: [0x7fff, 0x32bf, 0x00d0, 0x0000],
              obj1: [0x7fff, 0x32bf, 0x00d0, 0x0000]),
        .init(rawValue: "cgbUpA",
              background: [0x7fff, 0x421f, 0x1cf2, 0x0000],
              obj0: [0x7fff, 0x1bef, 0x0200, 0x0000],
              obj1: [0x7fff, 0x7e8c, 0x7c00, 0x0000]),
        .init(rawValue: "cgbUpB",
              background: [0x639f, 0x4279, 0x15b0, 0x04cb],
              obj0: [0x7fff, 0x32bf, 0x00d0, 0x0000],
              obj1: [0x7fff, 0x32bf, 0x00d0, 0x0000]),
        .init(rawValue: "cgbDown",
              background: [0x53ff, 0x4a5f, 0x7e52, 0x0000],
              obj0: [0x53ff, 0x4a5f, 0x7e52, 0x0000],
              obj1: [0x53ff, 0x4a5f, 0x7e52, 0x0000]),
        .init(rawValue: "cgbDownA",
              background: [0x7fff, 0x03ff, 0x001f, 0x0000],
              obj0: [0x7fff, 0x03ff, 0x001f, 0x0000],
              obj1: [0x7fff, 0x03ff, 0x001f, 0x0000]),
        .init(rawValue: "cgbDownB",
              background: [0x7fff, 0x03ff, 0x012f, 0x0000],
              obj0: [0x7fff, 0x7e8c, 0x7c00, 0x0000],
              obj1: [0x7fff, 0x1bef, 0x0200, 0x0000]),
        .init(rawValue: "cgbLeft",
              background: [0x7fff, 0x7e8c, 0x7c00, 0x0000],
              obj0: [0x7fff, 0x421f, 0x1cf2, 0x0000],
              obj1: [0x7fff, 0x1bef, 0x0200, 0x0000]),
        .init(rawValue: "cgbLeftA",
              background: [0x7fff, 0x6e31, 0x454a, 0x0000],
              obj0: [0x7fff, 0x421f, 0x1cf2, 0x0000],
              obj1: [0x7fff, 0x32bf, 0x00d0, 0x0000]),
        .init(rawValue: "cgbLeftB",
              background: [0x7fff, 0x5294, 0x294a, 0x0000],
              obj0: [0x7fff, 0x5294, 0x294a, 0x0000],
              obj1: [0x7fff, 0x5294, 0x294a, 0x0000]),
        .init(rawValue: "cgbRight",
              background: [0x7fff, 0x03ea, 0x011f, 0x0000],
              obj0: [0x7fff, 0x03ea, 0x011f, 0x0000],
              obj1: [0x7fff, 0x03ea, 0x011f, 0x0000]),
        .init(rawValue: "cgbRightA",
              background: [0x7fff, 0x1bef, 0x6180, 0x0000],
              obj0: [0x7fff, 0x421f, 0x1cf2, 0x0000],
              obj1: [0x7fff, 0x421f, 0x1cf2, 0x0000]),
        .init(rawValue: "cgbRightB",
              background: [0x0000, 0x4200, 0x037f, 0x7fff],
              obj0: [0x0000, 0x4200, 0x037f, 0x7fff],
              obj1: [0x0000, 0x4200, 0x037f, 0x7fff]),
        .init(rawValue: "cgbOlive",
              background: [0x7fff, 0x42b5, 0x3dc8, 0x0000],
              obj0: [0x7fff, 0x01df, 0x0112, 0x0000],
              obj1: [0x7fff, 0x01df, 0x0112, 0x0000]),
        .init(rawValue: "cgbZelda",
              background: [0x7fff, 0x421f, 0x1cf2, 0x0000],
              obj0: [0x7fff, 0x03e0, 0x0206, 0x0120],
              obj1: [0x7fff, 0x7e8c, 0x7c00, 0x0000]),
        .init(rawValue: "cgbMarioLand",
              background: [0x7ed6, 0x4bff, 0x2175, 0x0000],
              obj0: [0x0000, 0x7fff, 0x421f, 0x1cf2],
              obj1: [0x0000, 0x7fff, 0x421f, 0x1cf2]),
        .init(rawValue: "cgbMarioLand2",
              background: [0x67ff, 0x77ac, 0x1a13, 0x2d6b],
              obj0: [0x7fff, 0x01df, 0x0112, 0x0000],
              obj1: [0x7fff, 0x7e8c, 0x7c00, 0x0000]),
        .init(rawValue: "cgbDonkeyKongLand",
              background: [0x7fff, 0x6e31, 0x454a, 0x0000],
              obj0: [0x231f, 0x035f, 0x00f2, 0x0009],
              obj1: [0x7fff, 0x7eeb, 0x001f, 0x7c00]),
        .init(rawValue: "cgbCamera",
              background: [0x7fff, 0x033f, 0x0193, 0x0000],
              obj0: [0x7fff, 0x033f, 0x0193, 0x0000],
              obj1: [0x7fff, 0x033f, 0x0193, 0x0000]),
    ]

    func testEveryPaletteRendersBackgroundAndBothSpritePalettesWithAndWithoutBootSkip() throws {
        for skipBoot in [false, true] {
            for palette in palettes {
                let core = SameBoyAdapter()
                _ = try core.setDisplaySettings(colorCorrection: .off, dmgPalette: palette.setting)
                try boot(core, skipBoot: skipBoot)
                let frame = try core.runFrame(input: .init())
                assertColors(frame, palette: palette)
                for _ in 0..<3 { _ = try core.runFrame(input: .init(a: true)) }
                let remapped = try core.runFrame(input: .init(a: true))
                assertColors(remapped, palette: palette, firstSpriteShade: 0)
                XCTAssertEqual(core.readMemory(0xff4d), 0xff, "DMG hardware must stay selected")
            }
        }
    }

    func testPaletteChangesAndPausedRefreshDoNotChangeStateOrBattery() throws {
        let core = SameBoyAdapter()
        try boot(core, skipBoot: true)
        let state = try core.serializeState()
        let battery = try core.persistentSaveData()
        _ = core.drainAudio(maxFrames: 32768)
        for palette in palettes {
            let preview = try XCTUnwrap(core.setDisplaySettings(colorCorrection: .off, dmgPalette: palette.setting))
            assertColors(preview, palette: palette)
            XCTAssertEqual(preview.emulatedNanoseconds, 0)
            XCTAssertEqual(try core.serializeState(), state)
            XCTAssertEqual(try core.persistentSaveData(), battery)
            XCTAssertTrue(core.drainAudio(maxFrames: 32768).isEmpty)
            XCTAssertEqual(core.consumeRumbleAmplitude(), 0)
            try core.deserializeState(state)
            let restored = try core.runFrame(input: .init())
            assertColors(restored, palette: palette)
            try core.deserializeState(state)
            _ = core.drainAudio(maxFrames: 32768)
        }
    }

    func testStatesSavedWithBootPalettesLoadWithOtherBootAndOriginalPalettes() throws {
        let core = SameBoyAdapter()
        _ = try core.setDisplaySettings(colorCorrection: .off, dmgPalette: palettes[1].setting)
        try boot(core, skipBoot: true)
        let state = try core.serializeState()
        for palette in palettes {
            _ = try core.setDisplaySettings(colorCorrection: .off, dmgPalette: palette.setting)
            try core.deserializeState(state)
            assertColors(try core.runFrame(input: .init()), palette: palette)
        }
        _ = try core.setDisplaySettings(colorCorrection: .off, dmgPalette: .grey)
        try core.deserializeState(state)
        let grey = pixels(try core.runFrame(input: .init()))
        XCTAssertEqual(grey[0], 0xffffffff)
        XCTAssertEqual(grey[8], 0xffaaaaaa)
        XCTAssertEqual(grey[32 * 160], 0xffaaaaaa)
        XCTAssertEqual(grey[48 * 160], 0xffaaaaaa)
    }

    func testResetAndNewImagesKeepBootPalette() throws {
        let core = SameBoyAdapter()
        let palette = palettes[1]
        _ = try core.setDisplaySettings(colorCorrection: .off, dmgPalette: palette.setting)
        try boot(core, skipBoot: true)
        try core.reset()
        XCTAssertTrue(try core.skipBootAnimation())
        for _ in 0..<8 { _ = try core.runFrame(input: .init()) }
        assertColors(try core.runFrame(input: .init()), palette: palette)
        try boot(core, skipBoot: true)
        assertColors(try core.runFrame(input: .init()), palette: palette)
    }

    func testColorCorrectionAppliesToAllThreePalettes() throws {
        let core = SameBoyAdapter()
        let palette = palettes[1]
        _ = try core.setDisplaySettings(colorCorrection: .off, dmgPalette: palette.setting)
        try boot(core, skipBoot: true)
        let original = pixels(try core.runFrame(input: .init()))
        for correction in ColorCorrection.allCases where correction != .off {
            let corrected = pixels(try XCTUnwrap(core.setDisplaySettings(colorCorrection: correction, dmgPalette: palette.setting)))
            for index in [8, 32 * 160, 48 * 160] {
                XCTAssertNotEqual(corrected[index], original[index], "\(correction), pixel \(index)")
            }
        }
    }

    func testBootPaletteSettingDoesNotAffectColorOrDualModeGames() throws {
        try SameBoyAdapterTests.requireGeneratedBootROMs()
        for filename in ["rgbds-gbc.gbc", "gbdk450-dual.gbc"] {
            for skipBoot in [false, true] {
                let core = SameBoyAdapter()
                try core.loadImage(TestROMFixtures.rom(filename), system: .gameBoyColor)
                try finishBoot(core, skipBoot: skipBoot)
                let state = try core.serializeState()
                let frame = try XCTUnwrap(core.setDisplaySettings(colorCorrection: .balanced, dmgPalette: .grey))
                for palette in palettes {
                    let changed = try XCTUnwrap(core.setDisplaySettings(colorCorrection: .balanced, dmgPalette: palette.setting))
                    XCTAssertEqual(changed.bgra8888, frame.bgra8888, "\(filename), \(palette.rawValue)")
                    XCTAssertEqual(try core.serializeState(), state)
                }
            }
        }
    }

    func testColorsMatchActualCGBBootSelectionIncludingCorrection() throws {
        try SameBoyAdapterTests.requireGeneratedBootROMs()
        for palette in palettes {
            let reference = SameBoyAdapter()
            var rom = try TestROMFixtures.rom("palette-dmg.gb")
            if let title = palette.bootTitle {
                rom.replaceSubrange(0x134..<0x144, with: Array(title.utf8) + [UInt8](repeating: 0, count: 16 - title.utf8.count))
                rom[0x14b] = 1
                rom[0x14d] = rom[0x134...0x14c].reduce(UInt8(0)) { $0 &- $1 &- 1 }
            }
            try reference.loadImage(rom, system: .gameBoyColor)
            var frames = 0
            while (reference.readMemory(0xff50) ?? 0) & 1 == 0, frames < 1200 {
                _ = try reference.runFrame(input: palette.input)
                frames += 1
            }
            XCTAssertEqual((reference.readMemory(0xff50) ?? 0) & 1, 1)
            for _ in 0..<8 { _ = try reference.runFrame(input: .init()) }
            let core = SameBoyAdapter()
            _ = try core.setDisplaySettings(colorCorrection: .off, dmgPalette: palette.setting)
            try boot(core, skipBoot: true)
            for correction in ColorCorrection.allCases {
                let expected = try XCTUnwrap(reference.setDisplaySettings(colorCorrection: correction, dmgPalette: .grey))
                let actual = try XCTUnwrap(core.setDisplaySettings(colorCorrection: correction, dmgPalette: palette.setting))
                XCTAssertEqual(actual.bgra8888, expected.bgra8888, "\(palette.rawValue), \(correction)")
            }
        }
    }

    func testPaletteChangesPreserveNonemptyBatterySaveAndState() throws {
        try SameBoyAdapterTests.requireGeneratedBootROMs()
        let core = SameBoyAdapter()
        try core.loadImage(TestROMFixtures.rom("mbc5-battery.gb"), system: .gameBoy)
        XCTAssertTrue(try core.skipBootAnimation())
        for _ in 0..<8 { _ = try core.runFrame(input: .init()) }
        let state = try core.serializeState()
        let battery = try core.persistentSaveData()
        XCTAssertEqual(battery.count, 8192)
        for palette in palettes {
            _ = try core.setDisplaySettings(colorCorrection: .balanced, dmgPalette: palette.setting)
            XCTAssertEqual(try core.serializeState(), state)
            XCTAssertEqual(try core.persistentSaveData(), battery)
        }
    }

    func testEveryScopeReachesTheRunningCore() throws {
        let core = SameBoyAdapter()
        try boot(core, skipBoot: true)
        let store = InMemorySettingsStore()
        let resolver = SettingsResolver(store: store)
        let gameID = UUID(), buildID = UUID()
        let scopes: [SettingsScope] = [.app, .system(.gameBoy), .game(gameID), .build(buildID)]
        for index in scopes.indices {
            let palette = palettes[index + 1]
            try store.set(palette.setting, key: SettingKey.dmgPalette.rawValue, scope: scopes[index])
        }
        for index in scopes.indices.reversed() {
            let choice = try XCTUnwrap(resolver.decode(DMGPalette.self, key: SettingKey.dmgPalette.rawValue,
                                                      system: .gameBoy, gameID: gameID, buildID: buildID))
            let frame = try XCTUnwrap(core.setDisplaySettings(colorCorrection: .off, dmgPalette: choice))
            assertColors(frame, palette: palettes[index + 1])
            try store.removeValue(key: SettingKey.dmgPalette.rawValue, scope: scopes[index])
        }
    }

    private func boot(_ core: SameBoyAdapter, skipBoot: Bool) throws {
        try SameBoyAdapterTests.requireGeneratedBootROMs()
        try core.loadImage(TestROMFixtures.rom("palette-dmg.gb"), system: .gameBoy)
        try finishBoot(core, skipBoot: skipBoot)
    }

    private func finishBoot(_ core: SameBoyAdapter, skipBoot: Bool) throws {
        if skipBoot {
            XCTAssertTrue(try core.skipBootAnimation())
        } else {
            var frames = 0
            while (core.readMemory(0xff50) ?? 0) & 1 == 0, frames < 1200 {
                _ = try core.runFrame(input: .init())
                frames += 1
            }
            XCTAssertEqual((core.readMemory(0xff50) ?? 0) & 1, 1, "boot must finish")
        }
        for _ in 0..<8 { _ = try core.runFrame(input: .init()) }
    }

    private func assertColors(_ frame: EmulatorVideoFrame, palette: Palette, firstSpriteShade: Int = 1,
                              file: StaticString = #filePath, line: UInt = #line) {
        let values = pixels(frame)
        guard let setting = try? palette.setting else {
            XCTFail("Missing palette setting: \(palette.rawValue)", file: file, line: line)
            return
        }
        let previews = setting.previewColors
        guard previews.count == 3, previews.allSatisfy({ $0.count == 4 }) else {
            XCTFail("Palette previews must have three rows of four colors", file: file, line: line)
            return
        }
        for shade in 0..<4 {
            XCTAssertEqual(values[shade * 8], bgra(palette.background[shade]), "\(palette.rawValue) BG shade \(shade)", file: file, line: line)
            XCTAssertEqual(values[shade * 8], 0xff000000 | previews[0][shade], file: file, line: line)
        }
        for (index, entry) in [(32, palette.obj0), (48, palette.obj1)].enumerated() {
            let (y, colors) = entry
            for raw in 1..<4 {
                let shade = raw == 1 ? firstSpriteShade : raw
                XCTAssertEqual(values[y * 160 + (raw - 1) * 8], bgra(colors[shade]), "\(palette.rawValue) OBJ y=\(y) shade \(shade)", file: file, line: line)
                XCTAssertEqual(values[y * 160 + (raw - 1) * 8], 0xff000000 | previews[index + 1][shade], file: file, line: line)
            }
        }
    }

    private func bgra(_ rgb555: UInt16) -> UInt32 {
        func channel(_ shift: UInt16) -> UInt32 {
            let value = UInt32((rgb555 >> shift) & 31)
            return (value << 3) | (value >> 2)
        }
        return 0xff000000 | channel(0) << 16 | channel(5) << 8 | channel(10)
    }

    private func pixels(_ frame: EmulatorVideoFrame) -> [UInt32] {
        frame.bgra8888.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
    }
}

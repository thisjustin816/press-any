import EmulationCore
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import SameBoyBridge
import XCTest
@testable import SameBoyAdapter

final class SameBoySoftColorTests: XCTestCase {
    /// RGB555 colors, Modern Accurate's color for each on a Game Boy Color, and Soft's, from the
    /// reference implementation the look was approved with. All 0xAARRGGBB.
    private static let reference: [(rgb555: UInt16, accurate: UInt32, soft: UInt32)] = [
        (0x0000, 0xff000000, 0xff000000),
        (0x7fff, 0xffffffff, 0xffffffff),
        (0x4210, 0xffa1a1a1, 0xffa7a7a7),
        (0x001f, 0xffff0000, 0xfff44c3d),
        (0x03e0, 0xff00e000, 0xff5bdf54),
        (0x7c00, 0xff0088ff, 0xff4192f0),
        (0x1a8b, 0xff64b22d, 0xff77b554),
        (0x2a9f, 0xffffb558, 0xfff9bd78),
        (0x5088, 0xff426dca, 0xff5478c2),
        (0x2398, 0xffe8dd42, 0xffe7e070),
    ]

    func testSoftKeepsBlackAndWhite() {
        XCTAssertEqual(SBSoftenColor(0xff000000), 0xff000000)
        XCTAssertEqual(SBSoftenColor(0xffffffff), 0xffffffff)
    }

    func testSoftTakesAFifthOfTheColorAwayAndLiftsTheMiddleTones() {
        for color: UInt32 in [0xffff0000, 0xff00e000, 0xff0088ff, 0xff64b22d, 0xff426dca] {
            let accurate = OKLab(color)
            let soft = OKLab(SBSoftenColor(color))
            XCTAssertEqual(soft.chroma / accurate.chroma, 0.80, accuracy: 0.01, String(color, radix: 16))
            XCTAssertEqual(soft.lightness, pow(accurate.lightness, 0.92), accuracy: 0.002, String(color, radix: 16))
        }
        let gray = OKLab(0xffa1a1a1)
        let softGray = OKLab(SBSoftenColor(0xffa1a1a1))
        XCTAssertGreaterThan(softGray.lightness, gray.lightness + 0.015)
        XCTAssertLessThan(softGray.chroma, 0.001, "a gray stays gray")
    }

    func testSoftMatchesTheReference() {
        for sample in Self.reference {
            XCTAssertEqual(SBSoftenColor(sample.accurate), sample.soft, String(sample.rgb555, radix: 16))
        }
    }

    /// The table Soft colors frames through, end to end: a game sets its background color and the
    /// picture's corner shows Soft's color for it, and Modern Accurate's without Soft.
    func testAGameBoyColorGameShowsSoftColors() throws {
        try SameBoyAdapterTests.requireGeneratedBootROMs()
        for sample in Self.reference {
            XCTAssertEqual(try corner(.gameBoyColor, .soft, color: sample.rgb555), sample.soft, String(sample.rgb555, radix: 16))
            XCTAssertEqual(try corner(.gameBoyColor, .accurate, color: sample.rgb555), sample.accurate, String(sample.rgb555, radix: 16))
        }
    }

    func testAGameBoyAdvanceSoftensItsOwnScreenOrAGameBoyColors() throws {
        try SameBoyAdapterTests.requireGeneratedBootROMs()
        let color: UInt16 = 0x1a8b
        for model in [HardwareModel.gameBoyAdvance, .gameBoyPlayer] {
            let advance = try corner(model, .accurate, color: color, advanceColors: .gameBoyAdvance)
            XCTAssertEqual(try corner(model, .soft, color: color, advanceColors: .gameBoyAdvance), SBSoftenColor(advance), "\(model)")
            XCTAssertEqual(try corner(model, .soft, color: color, advanceColors: .gameBoyColor), 0xff77b554, "\(model)")
        }
    }

    func testSoftLeavesAGameBoysPaletteAndASuperGameBoysColors() throws {
        try SameBoyAdapterTests.requireGeneratedBootROMs()
        let gameBoy = SameBoyAdapter()
        try gameBoy.setHardwareModel(.gameBoy)
        try gameBoy.loadImage(TestROMFixtures.rom("rgbds-dmg.gb"), system: .gameBoy)
        XCTAssertTrue(try gameBoy.skipBootAnimation())
        for _ in 0..<8 { _ = try gameBoy.runFrame(input: .init()) }
        for palette in [DMGPalette.dmgGreen, .pocket, .light, .grey] {
            let accurate = try XCTUnwrap(gameBoy.setDisplaySettings(colorCorrection: .accurate, dmgPalette: palette, advanceColors: .gameBoyAdvance))
            let soft = try XCTUnwrap(gameBoy.setDisplaySettings(colorCorrection: .soft, dmgPalette: palette, advanceColors: .gameBoyAdvance))
            XCTAssertEqual(soft.bgra8888, accurate.bgra8888, "\(palette)")
        }

        let superGameBoy = SameBoyAdapter()
        try superGameBoy.setHardwareModel(.superGameBoy)
        try superGameBoy.loadImage(TestROM.make(title: "SGBCOLORS"), system: .gameBoy)
        XCTAssertTrue(try superGameBoy.skipBootAnimation())
        for _ in 0..<90 { _ = try superGameBoy.runFrame(input: .init()) }
        let accurate = try XCTUnwrap(superGameBoy.setDisplaySettings(colorCorrection: .accurate, dmgPalette: .dmgGreen, advanceColors: .gameBoyAdvance))
        let soft = try XCTUnwrap(superGameBoy.setDisplaySettings(colorCorrection: .soft, dmgPalette: .dmgGreen, advanceColors: .gameBoyAdvance))
        XCTAssertEqual(soft.bgra8888, accurate.bgra8888)
    }

    /// Soft is in the frame the core hands over, so a screenshot, artwork, a thumbnail and a save
    /// state's preview, which all start from it, show what gameplay shows.
    func testSoftColorsSurviveAPausedPreviewAndAStateLoad() throws {
        try SameBoyAdapterTests.requireGeneratedBootROMs()
        let core = SameBoyAdapter()
        try core.loadImage(TestROMFixtures.rom("rgbds-gbc.gbc"), system: .gameBoyColor)
        XCTAssertTrue(try core.skipBootAnimation())
        for _ in 0..<8 { _ = try core.runFrame(input: .init()) }
        let state = try core.serializeState()
        let accurate = try XCTUnwrap(core.setDisplaySettings(colorCorrection: .accurate, dmgPalette: .grey, advanceColors: .gameBoyAdvance))
        let soft = try XCTUnwrap(core.setDisplaySettings(colorCorrection: .soft, dmgPalette: .grey, advanceColors: .gameBoyAdvance))
        XCTAssertNotEqual(soft.bgra8888, accurate.bgra8888)
        XCTAssertEqual(pixels(soft), pixels(accurate).map(SBSoftenColor))
        XCTAssertEqual(try core.serializeState(), state, "the game doesn't move")
        try core.deserializeState(state)
        XCTAssertEqual(try core.runFrame(input: .init()).bgra8888, soft.bgra8888)
    }

    /// A game that sets background palette 0's color 0 to `color` and waits, so the whole picture
    /// shows it.
    private func colorROM(_ color: UInt16) -> Data {
        let program: [UInt8] = [
            0x3e, 0x80, 0xe0, 0x68,
            0x3e, UInt8(color & 0xff), 0xe0, 0x69,
            0x3e, UInt8(color >> 8), 0xe0, 0x69,
            0x18, 0xfe,
        ]
        return TestROM.make(title: "SOFT", cgb: true, program: program)
    }

    private func corner(
        _ model: HardwareModel,
        _ correction: ColorCorrection,
        color: UInt16,
        advanceColors: AdvanceColors = .gameBoyAdvance
    ) throws -> UInt32 {
        let core = SameBoyAdapter()
        try core.setHardwareModel(model)
        try core.loadImage(colorROM(color), system: .gameBoyColor)
        _ = try core.setDisplaySettings(colorCorrection: correction, dmgPalette: .dmgGreen, advanceColors: advanceColors)
        XCTAssertTrue(try core.skipBootAnimation())
        var frame = try core.runFrame(input: .init())
        for _ in 0..<4 { frame = try core.runFrame(input: .init()) }
        return frame.bgra8888.withUnsafeBytes { $0.load(as: UInt32.self) }
    }

    private func pixels(_ frame: EmulatorVideoFrame) -> [UInt32] {
        frame.bgra8888.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
    }
}

/// Björn Ottosson's OKLab (https://bottosson.github.io/posts/oklab/), to measure Soft's colors
/// independently of the bridge.
private struct OKLab {
    let lightness: Double
    let a: Double
    let b: Double

    var chroma: Double { (a * a + b * b).squareRoot() }

    init(_ argb: UInt32) {
        func linear(_ channel: UInt32) -> Double {
            let c = Double(channel & 0xff) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let r = linear(argb >> 16), g = linear(argb >> 8), b = linear(argb)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        self.b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    }
}

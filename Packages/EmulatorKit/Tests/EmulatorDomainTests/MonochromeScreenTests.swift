@testable import EmulatorDomain
import XCTest

final class MonochromeScreenTests: XCTestCase {
    private typealias Color = MonochromeScreen.Color

    /// BGB's measured screens after the exposure (1.4) and contrast (1.4) the owner chose, as sRGB.
    func testTheMeasuredScreensBecomeTheChosenColors() {
        let gameBoy = MonochromeScreen.colors(of: .gameBoy)
        XCTAssertEqual(gameBoy.shades.map(MonochromeScreen.rgb888), [0x89b13d, 0x64a25c, 0x3e7a64, 0x2d5e58])
        XCTAssertEqual(MonochromeScreen.rgb888(gameBoy.lcdOff), 0xaa9f05)
        let pocket = MonochromeScreen.colors(of: .pocket)
        XCTAssertEqual(pocket.shades.map(MonochromeScreen.rgb888), [0xc9deaa, 0xa5b789, 0x717c63, 0x515953])
        XCTAssertEqual(MonochromeScreen.rgb888(pocket.lcdOff), 0xe9f9cb)

        func ratio(_ shades: [Color]) -> Double {
            MonochromeScreen.luminance(shades[0]) / MonochromeScreen.luminance(shades[3])
        }
        XCTAssertEqual(ratio(gameBoy.shades), 4.0, accuracy: 0.05)
        XCTAssertEqual(ratio(pocket.shades), 7.1, accuracy: 0.05)
        let brighter = MonochromeScreen.luminance(pocket.shades[0]) / MonochromeScreen.luminance(gameBoy.shades[0])
        XCTAssertEqual(brighter, 1.8, accuracy: 0.05, "one exposure keeps the Pocket brighter")
    }

    /// The hardware's own palette shows exactly the measured screen, and its LCD-off color the
    /// screen with the LCD off.
    func testTheHardwaresOwnPaletteShowsTheMeasuredColors() {
        let cases: [(HardwareModel, DMGPalette, MonochromeScreen.Model)] = [
            (.gameBoy, .dmgGreen, .gameBoy), (.automatic, .dmgGreen, .gameBoy), (.gameBoyPocket, .pocket, .pocket),
        ]
        for (hardware, palette, model) in cases {
            XCTAssertEqual(DMGPalette.defaultValue(for: hardware), palette)
            let screen = MonochromeScreen(hardware: hardware, palette: palette)
            let target = MonochromeScreen.colors(of: model)
            for (shade, color) in palette.previewColors[0].enumerated() {
                XCTAssertEqual(
                    MonochromeScreen.rgb888(screen.toneMapped(MonochromeScreen.linear(color))),
                    MonochromeScreen.rgb888(target.shades[shade]), "\(hardware) shade \(shade)"
                )
            }
            XCTAssertEqual(
                MonochromeScreen.rgb888(screen.toneMapped(MonochromeScreen.linear(palette.lcdOffColor))),
                MonochromeScreen.rgb888(target.lcdOff)
            )
            XCTAssertEqual(screen.gapColor, target.lcdOff)
            XCTAssertEqual(screen.gapStrength, model.gapStrength)
            // A blend of two neighboring shades, as frame blending makes, lands between theirs.
            let mixed = (MonochromeScreen.linear(palette.previewColors[0][1]) + MonochromeScreen.linear(palette.previewColors[0][2])) / 2
            let expected = (target.shades[1] + target.shades[2]) / 2
            XCTAssertLessThan(abs(screen.toneMapped(mixed) - expected).max(), 1e-9)
        }
        XCTAssertLessThan(MonochromeScreen.Model.pocket.gapStrength, MonochromeScreen.Model.gameBoy.gapStrength, "the Pocket's gaps are thinner")
    }

    /// Any other palette keeps its colors and takes the screen's brightness and contrast: its
    /// lightest shade at the screen's lightest brightness and its darkest at the darkest.
    func testOtherPalettesKeepTheirColorsWithTheScreensBrightnessAndContrast() {
        for (hardware, model) in [(HardwareModel.gameBoy, MonochromeScreen.Model.gameBoy), (.gameBoyPocket, .pocket)] {
            let target = MonochromeScreen.colors(of: model).shades.map(MonochromeScreen.luminance)
            let blackAndWhite = MonochromeScreen(hardware: hardware, palette: .cgbLeftB)
            let white = blackAndWhite.toneMapped(Color(repeating: 1)), black = blackAndWhite.toneMapped(Color())
            XCTAssertEqual(white.x, white.y, "a gray palette stays gray")
            XCTAssertEqual(white.y, white.z)
            XCTAssertEqual(MonochromeScreen.luminance(white), target[0], accuracy: 1e-9)
            XCTAssertEqual(MonochromeScreen.luminance(black), target[3], accuracy: 1e-9)

            // The other model's own palette is just another palette here.
            let other: DMGPalette = model == .gameBoy ? .pocket : .dmgGreen
            let screen = MonochromeScreen(hardware: hardware, palette: other)
            let lightest = screen.toneMapped(MonochromeScreen.linear(other.previewColors[0][0]))
            XCTAssertNotEqual(MonochromeScreen.rgb888(lightest), MonochromeScreen.rgb888(MonochromeScreen.colors(of: model).shades[0]))
            XCTAssertEqual(MonochromeScreen.luminance(lightest), target[0], accuracy: 0.03)

            // Teal stays teal.
            let teal = MonochromeScreen(hardware: hardware, palette: .light)
            let lightTeal = teal.toneMapped(MonochromeScreen.linear(DMGPalette.light.previewColors[0][0]))
            XCTAssertGreaterThan(lightTeal.y, lightTeal.z)
            XCTAssertGreaterThan(lightTeal.z, lightTeal.x)
            XCTAssertGreaterThan(MonochromeScreen.luminance(teal.gapColor), MonochromeScreen.luminance(lightTeal) - 0.05, "the gaps stay light")
        }
    }

    /// Hardware that doesn't show a palette gets the original Game Boy's response, from white to
    /// black, and light gaps.
    func testOtherHardwareGetsTheOriginalGameBoysResponse() {
        let target = MonochromeScreen.colors(of: .gameBoy).shades.map(MonochromeScreen.luminance)
        for hardware in [HardwareModel.gameBoyColor, .gameBoyAdvance, .superGameBoy, .superGameBoy2, .gameBoyPlayer] {
            let screen = MonochromeScreen(hardware: hardware, palette: .dmgGreen)
            XCTAssertEqual(MonochromeScreen.luminance(screen.toneMapped(Color(repeating: 1))), target[0], accuracy: 1e-9, "\(hardware)")
            XCTAssertEqual(MonochromeScreen.luminance(screen.toneMapped(Color())), target[3], accuracy: 1e-9)
            XCTAssertEqual(screen.gapStrength, MonochromeScreen.Model.gameBoy.gapStrength)
            XCTAssertEqual(MonochromeScreen.luminance(screen.gapColor), target[0], accuracy: 1e-9)
        }
    }

    func testEveryCurvesInputsAscendInEveryChannel() {
        for hardware in HardwareModel.allCases {
            for palette in DMGPalette.allCases {
                let curve = MonochromeScreen(hardware: hardware, palette: palette).curve
                XCTAssertEqual(curve.count, 5)
                for index in 1..<curve.count {
                    for channel in 0..<3 {
                        XCTAssertGreaterThan(curve[index].input[channel], curve[index - 1].input[channel], "\(hardware) \(palette)")
                    }
                }
            }
        }
    }
}

private func abs(_ color: MonochromeScreen.Color) -> MonochromeScreen.Color {
    MonochromeScreen.Color(Swift.abs(color.x), Swift.abs(color.y), Swift.abs(color.z))
}

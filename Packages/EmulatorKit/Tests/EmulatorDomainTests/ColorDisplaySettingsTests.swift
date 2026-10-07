import EmulatorDomain
import Foundation
import XCTest

final class ColorDisplaySettingsTests: XCTestCase {
    func testStoredKeysAndChoicesAreStableStrings() throws {
        XCTAssertEqual(SettingKey.colorCorrection.rawValue, "colorCorrection")
        XCTAssertEqual(SettingKey.dmgPalette.rawValue, "dmgPalette")
        XCTAssertEqual(ColorCorrection.allCases.map(\.rawValue), [
            "off", "accurate", "balanced", "boostContrast", "reduceContrast", "lowContrast",
        ])
        XCTAssertEqual(DMGPalette.allCases.map(\.rawValue), ["grey", "dmgGreen", "pocket", "light"])
        XCTAssertEqual(String(data: try JSONEncoder().encode(ColorCorrection.accurate), encoding: .utf8), "\"accurate\"")
        XCTAssertEqual(String(data: try JSONEncoder().encode(DMGPalette.dmgGreen), encoding: .utf8), "\"dmgGreen\"")
    }

    func testDisplayDefaults() {
        XCTAssertEqual(ColorCorrection.defaultValue, .balanced)
        XCTAssertEqual(DMGPalette.defaultValue, .grey)
    }
}

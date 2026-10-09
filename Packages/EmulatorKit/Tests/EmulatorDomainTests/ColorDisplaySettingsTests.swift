import EmulatorDomain
import Foundation
import XCTest

final class ColorDisplaySettingsTests: XCTestCase {
    func testStoredKeysAndChoicesAreStableStrings() throws {
        XCTAssertEqual(SettingKey.colorCorrection.rawValue, "colorCorrection")
        XCTAssertEqual(SettingKey.dmgPalette.rawValue, "dmgPalette")
        XCTAssertEqual(ColorCorrection.allCases.map(\.rawValue), [
            "balanced", "accurate", "boostContrast", "reduceContrast", "lowContrast", "off",
        ])
        XCTAssertEqual(DMGPalette.allCases.map(\.rawValue), [
            "dmgGreen", "pocket", "light", "grey",
            "cgbUp",
            "cgbUpA",
            "cgbUpB",
            "cgbDown",
            "cgbDownA",
            "cgbDownB",
            "cgbLeft",
            "cgbLeftA",
            "cgbLeftB",
            "cgbRight",
            "cgbRightA",
            "cgbRightB",
            "cgbOlive",
        ])
        XCTAssertEqual(String(data: try JSONEncoder().encode(ColorCorrection.accurate), encoding: .utf8), "\"accurate\"")
        XCTAssertEqual(String(data: try JSONEncoder().encode(DMGPalette.dmgGreen), encoding: .utf8), "\"dmgGreen\"")
    }

    func testDisplayDefaults() {
        XCTAssertEqual(ColorCorrection.defaultValue, .balanced)
        XCTAssertEqual(DMGPalette.defaultValue, .dmgGreen)
    }

    func testLegacyGrayscaleIsDecodableButHasOnlyOneMenuChoice() throws {
        let legacy = try JSONDecoder().decode(DMGPalette.self, from: Data("\"grey\"".utf8))
        XCTAssertEqual(legacy.selectionValue, .cgbLeftB)
        XCTAssertFalse(DMGPalette.selectableCases.contains(.grey))
        XCTAssertEqual(DMGPalette.selectableCases.filter { $0.displayName.hasPrefix("Black & White") }, [.cgbLeftB])
        XCTAssertEqual(DMGPalette.cgbLeftB.displayName, "Black & White (Left + B)")
        XCTAssertEqual(DMGPalette.cgbOlive.displayName, "Olive & Orange (Mole Mania)")
    }
}

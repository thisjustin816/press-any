import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import XCTest
import ToolchainDetection

/// The ROMs in `TestROMs/` were built with known tools, so detection can be checked against
/// real images rather than planted signatures.
final class TestROMDetectionTests: XCTestCase {
    /// What each ROM is detected as, `kind:name:version`. The RGBDS ROMs are plain assembly with no
    /// runtime to recognize.
    private static let expected: [String: [String]] = [
        "gbdk450-dmg.gb": ["toolchain:GBDK:2020.4.3.0+"],
        "gbdk406-dmg.gb": ["toolchain:GBDK:2020.4.0.5 - 2020.4.0.6"],
        "rgbds-dmg.gb": [],
        "gbstudio-dmg.gb": gbStudio,
        "hugedriver-dmg.gb": ["musicDriver:hUGETracker:SuperDisk"],
        "zgb-dmg.gb": ["toolchain:GBDK:2020.4.1.0 - 2020.4.1.1", "engine:ZGB:2022.0+", "musicDriver:hUGETracker:SuperDisk"],
        "gbdk450-gbc.gbc": ["toolchain:GBDK:2020.4.3.0+"],
        "gbdk450-dual.gbc": ["toolchain:GBDK:2020.4.3.0+"],
        "rgbds-gbc.gbc": [],
        "gbstudio-gbc.gbc": gbStudio,
        "mbc5-battery.gb": ["toolchain:GBDK:2020.4.3.0+"],
        "gbdk450-rev-v1.0.gb": ["toolchain:GBDK:2020.4.3.0+"],
        "gbdk450-rev-v1.1.gb": ["toolchain:GBDK:2020.4.3.0+"],
        "gbdk450-badsum.gb": ["toolchain:GBDK:2020.4.3.0+"],
    ]

    private static let gbStudio = [
        "toolchain:GBDK:2020.4.3.0+",
        "engine:GBStudio:4.3.0+",
        "musicDriver:hUGETracker:SuperDisk",
        "soundEffectsDriver:VGM2GBSFX:-",
    ]

    func testEveryROMHasAnExpectation() throws {
        let filenames = try TestROMFixtures.manifest().roms.map(\.filename)
        XCTAssertEqual(Set(filenames), Set(Self.expected.keys))
    }

    func testEachROMIsDetectedAsTheToolsItWasBuiltWith() throws {
        for rom in try TestROMFixtures.manifest().roms {
            let image = try TestROMFixtures.rom(rom.filename)
            let system: GameSystem = rom.system == "GBC" ? .gameBoyColor : .gameBoy
            let found = ToolchainDetectorRegistry.standard.detect(image: image, system: system)
                .flatMap(\.components)
                .map { "\($0.kind.rawValue):\($0.name):\($0.version ?? "-")" }
            XCTAssertEqual(found, Self.expected[rom.filename], rom.filename)
        }
    }
}

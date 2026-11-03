import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import Importing
import XCTest

/// The headers of the ROMs in `TestROMs/` parse as their manifest records them.
final class TestROMHeaderTests: XCTestCase {
    func testHeadersMatchTheManifest() throws {
        for rom in try TestROMFixtures.manifest().roms {
            let image = try TestROMFixtures.rom(rom.filename)
            let header = try GBROMHeaderParser.parse(image)
            XCTAssertEqual(image.count, rom.size, rom.filename)
            XCTAssertEqual(header.system, rom.system == "GBC" ? .gameBoyColor : .gameBoy, rom.filename)
            XCTAssertEqual(header.cgbFlag, TestROMFixtures.byte(rom.cgbFlag), rom.filename)
            XCTAssertEqual(header.cartridgeType, TestROMFixtures.byte(rom.cartridgeType), rom.filename)
            XCTAssertEqual(header.headerChecksumValid, rom.headerChecksumOk, rom.filename)
            let hints = try XCTUnwrap(CartridgeHints(image: image), rom.filename)
            XCTAssertEqual(hints.sgbFlag, TestROMFixtures.byte(rom.sgbFlag), rom.filename)
            XCTAssertEqual(hints.oldLicensee, TestROMFixtures.byte(rom.oldLicensee), rom.filename)
            XCTAssertEqual(image[0x144..<0x146].map { String(format: "%02X", $0) }.joined(), rom.newLicensee, rom.filename)
        }
    }

    /// What Automatic picks for each ROM's header. Only the Automatic model fixtures set the Super
    /// Game Boy flag or a Nintendo licensee; every other Game Boy ROM plays on a Game Boy Pocket.
    func testAutomaticPicksTheModelEachHeaderSuits() throws {
        let fixtures: [String: HardwareModel] = [
            "sgb-packets.gb": .superGameBoy2,
            "header-sgb-cgb.gbc": .gameBoyColor,
            "header-sgb-licensee-00.gb": .gameBoyPocket,
            "header-licensee-01.gb": .gameBoyColor,
            "header-licensee-33-01.gb": .gameBoyColor,
            "header-sgb-licensee-33-01.gb": .superGameBoy2,
        ]
        for rom in try TestROMFixtures.manifest().roms {
            let image = try TestROMFixtures.rom(rom.filename)
            let expected = fixtures[rom.filename] ?? (rom.system == "GBC" ? .gameBoyColor : .gameBoyPocket)
            XCTAssertEqual(CartridgeHints(image: image)?.automaticModel, expected, rom.filename)
            XCTAssertEqual(rom.tags.contains("automatic-model"), fixtures[rom.filename] != nil, rom.filename)
            let withBorders = rom.filename == "header-sgb-cgb.gbc" ? .gameBoyPlayer : expected
            XCTAssertEqual(CartridgeHints(image: image)?.automaticModel(superGameBoyBorders: true), withBorders, rom.filename)
        }
    }

    func testTheBadChecksumROMStillParses() throws {
        let header = try GBROMHeaderParser.parse(TestROMFixtures.rom("gbdk450-badsum.gb"))
        XCTAssertFalse(header.headerChecksumValid)
        XCTAssertEqual(header.system, .gameBoy)
    }
}

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
        }
    }

    func testTheBadChecksumROMStillParses() throws {
        let header = try GBROMHeaderParser.parse(TestROMFixtures.rom("gbdk450-badsum.gb"))
        XCTAssertFalse(header.headerChecksumValid)
        XCTAssertEqual(header.system, .gameBoy)
    }
}

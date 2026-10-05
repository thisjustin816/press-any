import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import XCTest
@testable import Importing

final class ROMHeaderParserTests: XCTestCase {
    func testParsesCGBHeaderAndTitle() throws {
        let rom = TestROM.make(title: "TEST COLOR", cgb: true)

        let header = try GBROMHeaderParser.parse(rom)

        XCTAssertEqual(header.title, "TEST COLOR")
        XCTAssertEqual(header.system, .gameBoyColor)
        XCTAssertTrue(header.headerChecksumValid)
        XCTAssertEqual(header.cartridgeType, 0)
        XCTAssertEqual(header.romSizeCode, 0)
        XCTAssertEqual(header.ramSizeCode, 0)
    }

    func testParsesDMGHeader() throws {
        let header = try GBROMHeaderParser.parse(TestROM.make(title: "TEST DMG", cgb: false))
        XCTAssertEqual(header.system, .gameBoy)
        XCTAssertEqual(header.title, "TEST DMG")
    }

    func testParsesAnImageThatIsASlice() throws {
        let rom = TestROM.make(title: "SLICED", cgb: true)
        let framed = Data([0xff, 0xff]) + rom

        XCTAssertEqual(try GBROMHeaderParser.parse(framed[2...]), try GBROMHeaderParser.parse(rom))
    }

    func testRejectsFileSmallerThanHeader() {
        XCTAssertThrowsError(try GBROMHeaderParser.parse(Data(repeating: 0, count: 0x100)))
    }

    func testDetectsInvalidHeaderChecksum() throws {
        var rom = TestROM.make(title: "CHECKSUM", cgb: false)
        rom[0x14d] ^= 0xff
        XCTAssertFalse(try GBROMHeaderParser.parse(rom).headerChecksumValid)
    }

    func testValidatesGlobalChecksumAcrossWrapAround() throws {
        // 32 KiB of 0xFF sums far past UInt16.max, so this checks the wrapping sum.
        var rom = TestROM.make(title: "GLOBAL", cgb: false, payloadByte: 0xff)
        XCTAssertTrue(try GBROMHeaderParser.parse(rom).globalChecksumValid)

        rom[0x7fff] ^= 0x01
        XCTAssertFalse(try GBROMHeaderParser.parse(rom).globalChecksumValid)
    }

    func testGlobalChecksumIgnoresItsOwnBytes() throws {
        var rom = TestROM.make(title: "GLOBAL", cgb: true)
        rom[0x14f] &+= 1
        let header = try GBROMHeaderParser.parse(rom)
        XCTAssertFalse(header.globalChecksumValid)
        XCTAssertEqual(header.globalChecksum, UInt16(rom[0x14e]) << 8 | UInt16(rom[0x14f]))
    }
}

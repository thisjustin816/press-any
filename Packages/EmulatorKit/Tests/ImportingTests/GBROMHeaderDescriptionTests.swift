import EmulatorKitTestSupport
import Foundation
import XCTest
@testable import Importing

final class GBROMHeaderDescriptionTests: XCTestCase {
    private func header(
        cgbFlag: UInt8 = 0, cartridgeType: UInt8 = 0, romSizeCode: UInt8 = 0, ramSizeCode: UInt8 = 0
    ) -> GBROMHeader {
        GBROMHeader(
            title: "T", system: .gameBoy, cgbFlag: cgbFlag, cartridgeType: cartridgeType,
            romSizeCode: romSizeCode, ramSizeCode: ramSizeCode, headerChecksum: 0,
            headerChecksumValid: true, globalChecksum: 0, globalChecksumValid: true
        )
    }

    func testColorSupportFollowsTheCGBFlag() {
        XCTAssertEqual(header(cgbFlag: 0x00).colorSupport, .gameBoy)
        XCTAssertEqual(header(cgbFlag: 0x80).colorSupport, .colorCompatible)
        XCTAssertEqual(header(cgbFlag: 0xc0).colorSupport, .colorOnly)
        XCTAssertEqual(header(cgbFlag: 0x42).colorSupport, .gameBoy, "other values aren't color support")
        XCTAssertEqual(GBColorSupport.colorCompatible.displayName, "Game Boy Color compatible")
        XCTAssertEqual(GBColorSupport.colorOnly.displayName, "Game Boy Color only")
        XCTAssertEqual(GBColorSupport.gameBoy.displayName, "Game Boy")
    }

    func testColorSupportAgreesWithTheParsedSystem() throws {
        for flag: UInt8 in [0x00, 0x80, 0xc0] {
            var rom = TestROM.make(title: "FLAG", cgb: false)
            rom[0x143] = flag
            let parsed = try GBROMHeaderParser.parse(rom)
            XCTAssertEqual(parsed.colorSupport != .gameBoy, parsed.system == .gameBoyColor, "flag \(flag)")
        }
    }

    func testCartridgeTypesAreNamed() {
        XCTAssertEqual(header(cartridgeType: 0x00).cartridgeTypeName, "ROM Only")
        XCTAssertEqual(header(cartridgeType: 0x03).cartridgeTypeName, "MBC1 + RAM + Battery")
        XCTAssertEqual(header(cartridgeType: 0x10).cartridgeTypeName, "MBC3 + Timer + RAM + Battery")
        XCTAssertEqual(header(cartridgeType: 0x1b).cartridgeTypeName, "MBC5 + RAM + Battery")
        XCTAssertEqual(header(cartridgeType: 0x1e).cartridgeTypeName, "MBC5 + Rumble + RAM + Battery")
        XCTAssertEqual(header(cartridgeType: 0xfc).cartridgeTypeName, "Pocket Camera")
        XCTAssertEqual(header(cartridgeType: 0x7a).cartridgeTypeName, "Unknown (0x7A)")
    }

    func testEveryNamedCartridgeTypeIsDistinct() {
        let names = (0...255).map { GBROMHeader.cartridgeTypeName(for: UInt8($0)) }.filter { !$0.hasPrefix("Unknown") }
        XCTAssertEqual(names.count, Set(names).count)
        XCTAssertEqual(names.count, 28)
    }

    func testROMSizesFollowTheHeaderCode() {
        XCTAssertEqual(header(romSizeCode: 0x00).romSizeDescription, "32 KB")
        XCTAssertEqual(header(romSizeCode: 0x01).romSizeDescription, "64 KB")
        XCTAssertEqual(header(romSizeCode: 0x05).romSizeDescription, "1 MB")
        XCTAssertEqual(header(romSizeCode: 0x08).romSizeDescription, "8 MB")
        XCTAssertEqual(header(romSizeCode: 0x52).romSizeDescription, "1.1 MB")
        XCTAssertEqual(header(romSizeCode: 0x54).romSizeBytes, 96 * 0x4000)
        XCTAssertEqual(header(romSizeCode: 0x09).romSizeDescription, "Unknown (0x09)")
        XCTAssertNil(header(romSizeCode: 0x09).romSizeBytes)
    }

    func testRAMSizesFollowTheHeaderCode() {
        XCTAssertEqual(header(ramSizeCode: 0x00).ramSizeDescription, "None")
        XCTAssertEqual(header(ramSizeCode: 0x01).ramSizeDescription, "2 KB")
        XCTAssertEqual(header(ramSizeCode: 0x02).ramSizeDescription, "8 KB")
        XCTAssertEqual(header(ramSizeCode: 0x03).ramSizeDescription, "32 KB")
        XCTAssertEqual(header(ramSizeCode: 0x04).ramSizeDescription, "128 KB")
        XCTAssertEqual(header(ramSizeCode: 0x05).ramSizeDescription, "64 KB")
        XCTAssertEqual(header(ramSizeCode: 0x06).ramSizeDescription, "Unknown (0x06)")
    }

    func testParsingAStoredImageMatchesParsingItsBytes() throws {
        let rom = TestROM.make(title: "ON DISK", cgb: true, payloadByte: 7)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Header-\(UUID()).gbc")
        try rom.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(try GBROMHeaderParser.parse(contentsOf: url), try GBROMHeaderParser.parse(rom))
    }

    func testAnImageTooSmallForAHeaderThrows() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Short-\(UUID()).gb")
        try Data(repeating: 0, count: 0x40).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try GBROMHeaderParser.parse(contentsOf: url))
    }
}

import EmulatorDomain
import Foundation
import XCTest

/// Automatic reads the header and picks the first match: Game Boy Color game, Super Game Boy
/// game, Nintendo game, then everything else.
final class AutomaticModelTests: XCTestCase {
    private func image(cgb: UInt8 = 0, sgb: UInt8 = 0, old: UInt8 = 0, new: String = "\0\0") -> Data {
        var image = Data(count: 0x8000)
        image[0x143] = cgb
        image[0x146] = sgb
        image[0x14B] = old
        let newBytes = Array(new.utf8)
        image[0x144] = newBytes[0]
        image[0x145] = newBytes[1]
        return image
    }

    private func automatic(cgb: UInt8 = 0, sgb: UInt8 = 0, old: UInt8 = 0, new: String = "\0\0") throws -> HardwareModel {
        try XCTUnwrap(CartridgeHints(image: image(cgb: cgb, sgb: sgb, old: old, new: new))).automaticModel
    }

    func testAGameBoyColorGamePlaysOnAGameBoyColorWhateverElseItSays() throws {
        for cgb: UInt8 in [0x80, 0xC0] {
            XCTAssertEqual(try automatic(cgb: cgb), .gameBoyColor)
            XCTAssertEqual(try automatic(cgb: cgb, sgb: 0x03, old: 0x33), .gameBoyColor, "rule 1 before the Super Game Boy")
            XCTAssertEqual(try automatic(cgb: cgb, sgb: 0x03, old: 0x33, new: "01"), .gameBoyColor)
            XCTAssertEqual(try automatic(cgb: cgb, old: 0x01), .gameBoyColor)
        }
        XCTAssertEqual(try automatic(cgb: 0x40), .gameBoyPocket, "only bit 7 marks a Game Boy Color game")
    }

    /// Super Game Boy borders, hidden and off, move only Game Boy Color games that support the
    /// Super Game Boy, to the Game Boy Player.
    func testWithBordersOnAColorGameThatSupportsTheSuperGameBoyPlaysOnAGameBoyPlayer() throws {
        func automatic(_ hints: CartridgeHints, borders: Bool) -> HardwareModel {
            hints.automaticModel(superGameBoyBorders: borders)
        }
        for cgb: UInt8 in [0x80, 0xC0] {
            let both = CartridgeHints(cgbFlag: cgb, sgbFlag: 0x03, oldLicensee: 0x33)
            XCTAssertEqual(automatic(both, borders: true), .gameBoyPlayer)
            XCTAssertEqual(automatic(both, borders: false), .gameBoyColor)
            XCTAssertEqual(both.automaticModel, .gameBoyColor, "borders are off unless asked")
            XCTAssertEqual(automatic(CartridgeHints(cgbFlag: cgb), borders: true), .gameBoyColor)
            XCTAssertEqual(automatic(CartridgeHints(cgbFlag: cgb, sgbFlag: 0x03), borders: true), .gameBoyColor, "needs licensee 0x33")
            XCTAssertEqual(automatic(CartridgeHints(cgbFlag: cgb, oldLicensee: 0x01), borders: true), .gameBoyColor)
        }
        for borders in [false, true] {
            XCTAssertEqual(automatic(CartridgeHints(sgbFlag: 0x03, oldLicensee: 0x33), borders: borders), .superGameBoy2)
            XCTAssertEqual(automatic(CartridgeHints(oldLicensee: 0x01), borders: borders), .gameBoyColor)
            XCTAssertEqual(automatic(CartridgeHints(), borders: borders), .gameBoyPocket)
        }
        XCTAssertEqual(HardwareModel.automaticChoices(for: .gameBoyColor, superGameBoyBorders: true), [.gameBoyColor, .gameBoyPlayer, .gameBoyAdvance])
        XCTAssertEqual(HardwareModel.automaticChoices(for: .gameBoy, superGameBoyBorders: true), [.gameBoyPocket, .superGameBoy2, .gameBoyColor])
        XCTAssertEqual(
            HardwareModel.automatic.resolved(forImage: image(cgb: 0x80, sgb: 0x03, old: 0x33), system: .gameBoyColor, superGameBoyBorders: true),
            .gameBoyPlayer
        )
    }

    func testASuperGameBoyGamePlaysOnASuperGameBoy2() throws {
        XCTAssertEqual(try automatic(sgb: 0x03, old: 0x33), .superGameBoy2)
        XCTAssertEqual(try automatic(sgb: 0x03, old: 0x33, new: "01"), .superGameBoy2, "rule 2 before Nintendo")
        XCTAssertEqual(try automatic(sgb: 0x03, old: 0x33, new: "A4"), .superGameBoy2)
    }

    func testTheSuperGameBoyFlagNeedsLicensee33AsOnTheHardware() throws {
        XCTAssertEqual(try automatic(sgb: 0x03), .gameBoyPocket)
        XCTAssertEqual(try automatic(sgb: 0x03, old: 0x0A), .gameBoyPocket)
        XCTAssertEqual(try automatic(sgb: 0x03, old: 0x01), .gameBoyColor, "a Nintendo game without licensee 0x33 is still Nintendo's")
        XCTAssertEqual(try automatic(sgb: 0x02, old: 0x33), .gameBoyPocket, "only 0x03 marks Super Game Boy support")
    }

    func testANintendoGamePlaysOnAGameBoyColor() throws {
        XCTAssertEqual(try automatic(old: 0x01), .gameBoyColor)
        XCTAssertEqual(try automatic(old: 0x33, new: "01"), .gameBoyColor)
        XCTAssertEqual(try automatic(old: 0x00, new: "01"), .gameBoyPocket, "the new licensee counts only with 0x33")
        XCTAssertEqual(try automatic(old: 0x33, new: "00"), .gameBoyPocket)
        XCTAssertEqual(try automatic(old: 0x33, new: "10"), .gameBoyPocket)
    }

    func testEverythingElsePlaysOnAGameBoyPocket() throws {
        XCTAssertEqual(try automatic(), .gameBoyPocket)
        XCTAssertEqual(try automatic(old: 0x33), .gameBoyPocket)
        XCTAssertEqual(try automatic(old: 0x08), .gameBoyPocket)
    }

    func testWithBordersOffAutomaticPicksOnlyAPocketASuperGameBoy2OrAGameBoyColor() throws {
        var picked = Set<HardwareModel>()
        for cgb: UInt8 in [0x00, 0x80, 0xC0] {
            for sgb: UInt8 in [0x00, 0x03] {
                for old: UInt8 in [0x00, 0x01, 0x33] {
                    for new in ["00", "01"] {
                        picked.insert(try automatic(cgb: cgb, sgb: sgb, old: old, new: new))
                    }
                }
            }
        }
        XCTAssertEqual(picked, [.gameBoyPocket, .superGameBoy2, .gameBoyColor])
        XCTAssertEqual(Set(HardwareModel.automaticChoices(for: .gameBoy)), picked)
    }

    func testTheHintsReadTheHeaderBytesOfAnImageOrASliceOfOne() throws {
        let hints = try XCTUnwrap(CartridgeHints(image: image(cgb: 0x80, sgb: 0x03, old: 0x33, new: "01")))
        XCTAssertEqual(hints, CartridgeHints(cgbFlag: 0x80, sgbFlag: 0x03, oldLicensee: 0x33, newLicensee: "01"))
        var padded = Data(repeating: 0xEE, count: 16)
        padded.append(image(sgb: 0x03, old: 0x33))
        XCTAssertEqual(CartridgeHints(image: padded.dropFirst(16))?.automaticModel, .superGameBoy2)
        XCTAssertNil(CartridgeHints(image: Data(count: 0x14B)), "too short for the old licensee")
    }
}

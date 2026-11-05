import EmulationCore
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import XCTest
@testable import SameBoyAdapter

final class SameBoySaveSizeTests: XCTestCase {
    func testASaveExportedAtTheMinimumLoadsBackAtTheFullSize() throws {
        try SameBoyAdapterTests.requireGeneratedBootROMs()
        let core = SameBoyAdapter()
        // MBC5 with RAM and a battery, 128 KB of RAM.
        let rom = TestROM.make(title: "BIG RAM", cgb: true, cartridgeType: 0x1B, ramSizeCode: 0x04)
        try core.loadImage(rom, system: .gameBoyColor)
        var original = Data(repeating: 0xFF, count: 128 * 1024)
        for offset in 0..<1558 { original[offset] = UInt8(truncatingIfNeeded: offset &* 7) }

        try core.loadPersistentSave(Data(original.prefix(8 * 1024)))

        XCTAssertEqual(try core.persistentSaveData(), original, "the banks that were trimmed come back erased")
    }
}

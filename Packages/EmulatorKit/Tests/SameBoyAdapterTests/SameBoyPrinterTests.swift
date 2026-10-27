import EmulationCore
import EmulatorKitTestSupport
import XCTest
@testable import SameBoyAdapter

final class SameBoyPrinterTests: XCTestCase {
    func testAttachmentSurvivesImageResetAndHardwareReplacement() throws {
        try SameBoyAdapterTests.requireGeneratedBootROMs()
        let core = SameBoyAdapter()
        let opaque: any EmulatorCore = core
        let printer = try XCTUnwrap(opaque as? any PrinterCapability)
        XCTAssertFalse(printer.printerConnected)
        printer.setPrinterConnected(true)
        try core.loadImage(TestROM.make(title: "PRINTER TEST"), system: .gameBoy)
        XCTAssertTrue(printer.printerConnected)
        XCTAssertEqual(try printer.drainPrinterOutput(), [])
        try core.reset()
        XCTAssertTrue(printer.printerConnected)
        try core.setHardwareModel(.gameBoyColor)
        XCTAssertTrue(printer.printerConnected)
        printer.setPrinterConnected(false)
        XCTAssertFalse(printer.printerConnected)
        XCTAssertEqual(try printer.drainPrinterOutput(), [])
    }
}

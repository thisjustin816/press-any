import EmulationCore
import XCTest

final class PrinterEventTests: XCTestCase {
    func testAPacketNamesItsCommandSizeAndStatusFlags() {
        let event = PrinterEvent(time: 1, kind: .packet, command: 4, compressed: true, length: 640, status: 0x0E)
        XCTAssertEqual(event.summary, "Data, 640 bytes, compressed → 0x0E busy, image full, unprocessed data")
        XCTAssertNil(event.problem, "busy and full are the printer working, not an error")
        XCTAssertEqual(PrinterEvent(time: 1, kind: .packet, command: 15, compressed: false, length: 0, status: 0).summary,
                       "Status → 0x00 ready")
    }

    func testProblemsSayWhatTheGameDidWrong() {
        let ignored = PrinterEvent(time: 1, kind: .packet, command: 4, compressed: false, length: 640, status: 0x06,
                                   ignoredWhilePrinting: true)
        XCTAssertEqual(ignored.problem, "Data sent while printing was ignored.")
        let refused = PrinterEvent(time: 1, kind: .packet, command: 2, compressed: false, length: 4, status: 0x14)
        XCTAssertEqual(refused.problem, "The printer refused the Print packet (packet error).")
        let checksum = PrinterEvent(time: 1, kind: .packet, command: 4, compressed: false, length: 640, status: 0,
                                    checksumMatched: false)
        XCTAssertEqual(checksum.problem, "The Data packet’s checksum didn’t match.")
        XCTAssertEqual(PrinterEvent(time: 1, kind: .timeout, command: 4, compressed: false, length: 0, status: 0).problem,
                       "A Data packet was dropped: its bytes came more than 5 ms apart.")
        XCTAssertEqual(PrinterEvent(time: 1, kind: .syncLost, command: 0x12, compressed: false, length: 0, status: 0).problem,
                       "A packet began with 0x12 instead of 0x88; the printer answers 0xFF until the line goes quiet.")
    }
}

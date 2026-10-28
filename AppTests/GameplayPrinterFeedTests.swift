import EmulationCore
import Foundation
import XCTest
@testable import PressAny

final class GameplayPrinterFeedTests: XCTestCase {
    func testOverlongPaperKeepsLaterPrintsInTheSameDelivery() throws {
        let feed = GameplayPrinterFeed()
        let section = try PrinterOutput(height: 200, luminance: Data(count: 32000), topMargin: 0, bottomMargin: 0, exposure: 64)
        try feed.receive(Array(repeating: section, count: 10))
        let next = try PrinterOutput(height: 1, luminance: Data(repeating: 170, count: 160), topMargin: 1, bottomMargin: 3, exposure: 64)
        XCTAssertThrowsError(try feed.receive([section, next]))
        XCTAssertEqual(feed.slips.count, 2)
        XCTAssertEqual(feed.slips[0].feedHeight, 2000)
        XCTAssertEqual(feed.slips.last?.sections, [next])
    }

    func testEndingARollPreservesItsPaperAndSeparatesTheNextDelivery() throws {
        let feed = GameplayPrinterFeed()
        let section = try PrinterOutput(height: 16, luminance: Data(count: 2560), topMargin: 0, bottomMargin: 0, exposure: 64)
        try feed.receive([section])
        let first = try XCTUnwrap(feed.slips.first)
        feed.endRoll()
        try feed.receive([section])
        XCTAssertEqual(feed.slips.count, 2)
        XCTAssertEqual(feed.slips[0], first)
        XCTAssertNotEqual(feed.slips[1].id, first.id)
    }
}

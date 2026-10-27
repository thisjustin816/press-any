import EmulationCore
import UIKit
import XCTest
@testable import PressAny

@MainActor
final class PrinterStatusViewTests: XCTestCase {
    func testActivityTransitionsToADirectViewActionThatSurvivesIdle() {
        let status = PrinterStatusView()
        XCTAssertTrue(status.isHidden)
        status.showActivity(.receiving)
        XCTAssertFalse(status.isHidden)
        XCTAssertTrue(status.spinner.isAnimating)
        XCTAssertTrue(status.viewPrint.isHidden)
        XCTAssertEqual(status.message.text, "Receiving print...")
        status.showActivity(.printing)
        XCTAssertEqual(status.message.text, "Printing...")
        status.showReadyPrint()
        status.showActivity(.idle)
        XCTAssertFalse(status.isHidden)
        XCTAssertFalse(status.viewPrint.isHidden)
        XCTAssertFalse(status.spinner.isAnimating)
        var viewed = false
        status.onViewPrint = { viewed = true }
        status.viewPrint.sendActions(for: .touchUpInside)
        XCTAssertTrue(viewed)
        status.dismissButton.sendActions(for: .touchUpInside)
        XCTAssertTrue(status.isHidden)
    }

    func testANewJobReplacesTheReadyActionAndIdleClearsProgress() {
        let status = PrinterStatusView()
        status.showReadyPrint()
        status.showActivity(.printing)
        XCTAssertTrue(status.viewPrint.isHidden)
        XCTAssertTrue(status.spinner.isAnimating)
        status.showActivity(.idle)
        XCTAssertTrue(status.isHidden)
    }
}

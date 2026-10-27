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

    func testReadyWaitsOutTheIdleGapBetweenPages() async throws {
        let status = PrinterStatusView()
        status.settleDelay = .milliseconds(50)
        status.showActivity(.printing)
        status.showActivity(.idle)
        status.printReceived()
        status.showActivity(.receiving)
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertTrue(status.viewPrint.isHidden)
        XCTAssertEqual(status.message.text, "Receiving page 2...")
        status.printReceived()
        status.showActivity(.printing)
        XCTAssertEqual(status.message.text, "Printing page 3...")
        status.showActivity(.idle)
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertFalse(status.viewPrint.isHidden)
        XCTAssertEqual(status.message.text, "2 pages ready")
        status.showActivity(.receiving)
        XCTAssertEqual(status.message.text, "Receiving print...")
    }

    func testOpeningThePrintsCancelsAPendingReadyBanner() async throws {
        let status = PrinterStatusView()
        status.settleDelay = .milliseconds(50)
        status.printReceived()
        status.dismissReadyPrint()
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertTrue(status.isHidden)
    }
}

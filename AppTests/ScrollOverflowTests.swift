import Foundation
import XCTest
@testable import PressAny

final class ScrollOverflowTests: XCTestCase {
    func testEmptyAndFittingContentNeedNoCue() {
        XCTAssertFalse(more(content: 0))
        XCTAssertFalse(more(content: 400))
        XCTAssertFalse(more(content: 600))
        XCTAssertFalse(more(content: 600.5))
        XCTAssertFalse(more(content: 900, viewport: 0))
    }

    func testCueDisappearsAtTheEndAndReturnsWhenScrollingUp() {
        XCTAssertTrue(more(content: 1_000))
        XCTAssertTrue(more(content: 1_000, offset: 350))
        XCTAssertFalse(more(content: 1_000, offset: 400))
        XCTAssertFalse(more(content: 1_000, offset: 440))
        XCTAssertTrue(more(content: 1_000, offset: 300))
    }

    func testInsetsKeepContentAboveBottomBarsAndKeyboardReachable() {
        XCTAssertTrue(more(content: 600, inset: 80))
        XCTAssertFalse(more(content: 600, offset: 80, inset: 80))
        XCTAssertTrue(more(content: 600, inset: 300))
        XCTAssertFalse(more(content: 600, offset: 300, inset: 300))
        XCTAssertFalse(more(content: 480, offset: -80, topInset: 80, inset: 40))
        XCTAssertTrue(more(content: 600, offset: -80, topInset: 80))
    }

    func testPullingDownDoesNotAddACueToFittingContent() {
        XCTAssertFalse(more(content: 600, offset: -100))
        XCTAssertFalse(more(content: 480, offset: -180, topInset: 80, inset: 40))
    }

    func testContentAndViewportChangesRecalculateOverflow() {
        XCTAssertFalse(more(content: 500))
        XCTAssertTrue(more(content: 800))
        XCTAssertFalse(more(content: 400))
        XCTAssertTrue(more(content: 500, viewport: 300))
        XCTAssertFalse(more(content: 500, viewport: 700))
    }

    private func more(content: CGFloat, viewport: CGFloat = 600, offset: CGFloat = 0,
                      topInset: CGFloat = 0, inset: CGFloat = 0) -> Bool {
        ScrollOverflow.hasMoreBelow(
            contentHeight: content, viewportHeight: viewport, offsetY: offset,
            topInset: topInset, bottomInset: inset
        )
    }
}

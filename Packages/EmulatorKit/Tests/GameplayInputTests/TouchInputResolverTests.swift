import EmulationCore
import GameplayInput
import XCTest

final class TouchInputResolverTests: XCTestCase {
    func testSlidingDPadMovesFromLeftToUpWithoutLift() {
        let resolver = TouchInputResolver(layout: .testLayout)
        resolver.touchBegan(id: 1, point: .init(x: 20, y: 50))
        XCTAssertTrue(resolver.input.left)
        XCTAssertFalse(resolver.input.up)

        resolver.touchMoved(id: 1, point: .init(x: 50, y: 20))
        XCTAssertFalse(resolver.input.left)
        XCTAssertTrue(resolver.input.up)
    }

    func testDPadSupportsDiagonalInput() {
        let resolver = TouchInputResolver(layout: .testLayout)
        resolver.touchBegan(id: 1, point: .init(x: 20, y: 20))
        XCTAssertTrue(resolver.input.left)
        XCTAssertTrue(resolver.input.up)
        XCTAssertFalse(resolver.input.right)
        XCTAssertFalse(resolver.input.down)
    }

    func testSlidingBetweenAAndBChangesButtonWithoutLift() {
        let resolver = TouchInputResolver(layout: .testLayout)
        resolver.touchBegan(id: 1, point: .init(x: 260, y: 60))
        XCTAssertTrue(resolver.input.a)
        XCTAssertFalse(resolver.input.b)

        resolver.touchMoved(id: 1, point: .init(x: 210, y: 60))
        XCTAssertFalse(resolver.input.a)
        XCTAssertTrue(resolver.input.b)
    }

    func testMultitouchAllowsAAndBAtSameTime() {
        let resolver = TouchInputResolver(layout: .testLayout)
        resolver.touchBegan(id: 1, point: .init(x: 260, y: 60))
        resolver.touchBegan(id: 2, point: .init(x: 210, y: 60))
        XCTAssertTrue(resolver.input.a)
        XCTAssertTrue(resolver.input.b)
    }

    func testEndingOneTouchDoesNotClearOtherTouch() {
        let resolver = TouchInputResolver(layout: .testLayout)
        resolver.touchBegan(id: 1, point: .init(x: 20, y: 50))
        resolver.touchBegan(id: 2, point: .init(x: 260, y: 60))
        resolver.touchEnded(id: 1)
        XCTAssertFalse(resolver.input.left)
        XCTAssertTrue(resolver.input.a)
    }

    func testCanceledTouchesClearAllInput() {
        let resolver = TouchInputResolver(layout: .testLayout)
        resolver.touchBegan(id: 1, point: .init(x: 20, y: 50))
        resolver.touchBegan(id: 2, point: .init(x: 260, y: 60))
        resolver.cancelAllTouches()
        XCTAssertEqual(resolver.input, EmulatorInputState())
    }

    func testStandardLayoutControlsDoNotOverlapOnCommonScreens() {
        func overlaps(_ lhs: TouchRect, _ rhs: TouchRect) -> Bool {
            lhs.x < rhs.x + rhs.width && rhs.x < lhs.x + lhs.width &&
                lhs.y < rhs.y + rhs.height && rhs.y < lhs.y + lhs.height
        }
        // iPhone SE, 8, 15/16, 16 Pro Max portrait sizes in points.
        for (width, height) in [(320.0, 568.0), (375.0, 667.0), (393.0, 852.0), (440.0, 956.0)] {
            let layout = TouchControlLayout.standard(width: width, height: height)
            let controls = [
                ("D-pad", layout.dpad), ("A", layout.a), ("B", layout.b),
                ("Start", layout.start), ("Select", layout.select),
            ]
            for (index, (name, rect)) in controls.enumerated() {
                XCTAssertTrue(rect.x >= 0 && rect.y >= 0 && rect.x + rect.width <= width && rect.y + rect.height <= height,
                              "\(name) is on screen at \(width)x\(height)")
                for (otherName, other) in controls[(index + 1)...] {
                    XCTAssertFalse(overlaps(rect, other), "\(name) overlaps \(otherName) at \(width)x\(height)")
                }
            }
        }
    }
}

private extension TouchControlLayout {
    static let testLayout = TouchControlLayout(
        dpad: .init(x: 0, y: 0, width: 100, height: 100),
        a: .init(x: 235, y: 35, width: 50, height: 50),
        b: .init(x: 195, y: 35, width: 50, height: 50),
        start: .init(x: 145, y: 110, width: 50, height: 24),
        select: .init(x: 85, y: 110, width: 50, height: 24)
    )
}

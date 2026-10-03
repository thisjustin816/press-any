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

    func testBuiltInLayoutsKeepControlsApartAndOffTheGame() {
        func overlaps(_ lhs: TouchRect, _ rhs: TouchRect) -> Bool {
            lhs.x < rhs.x + rhs.width && rhs.x < lhs.x + lhs.width &&
                lhs.y < rhs.y + rhs.height && rhs.y < lhs.y + lhs.height
        }
        // iPhone SE, 8, 15/16 and 16 Pro Max portrait sizes and safe-area insets, in points.
        let screens: [(Double, Double, Double, Double)] = [
            (320, 568, 20, 0), (375, 667, 20, 0), (393, 852, 59, 34), (440, 956, 62, 34),
        ]
        for style in TouchControlStyle.allCases {
            for (width, height, top, bottom) in screens {
                let layout = TouchControlLayout.make(style, width: width, height: height, safeTop: top, safeBottom: bottom)
                let size = "\(style) at \(width)x\(height)"
                let controls = [
                    ("D-pad", layout.dpadHitArea), ("A", layout.a), ("B", layout.b),
                    ("Start", layout.start), ("Select", layout.select),
                ] + layout.actions.filter { $0.key != .toggleFastForward }.map { ("\($0.key)", $0.value) }
                let pictureBottom = layout.screen.y + layout.screen.height

                XCTAssertGreaterThan(layout.screen.height, 0, size)
                XCTAssertLessThanOrEqual(layout.select.x + layout.select.width, layout.start.x, "SELECT is left of START, \(size)")
                for (index, (name, rect)) in controls.enumerated() {
                    XCTAssertTrue(rect.x >= 0 && rect.y >= 0 && rect.x + rect.width <= width && rect.y + rect.height <= height,
                                  "\(name) is on screen, \(size)")
                    XCTAssertGreaterThanOrEqual(rect.y, pictureBottom, "\(name) covers the game picture, \(size)")
                    for (otherName, other) in controls[(index + 1)...] {
                        XCTAssertFalse(overlaps(rect, other), "\(name) overlaps \(otherName), \(size)")
                    }
                }
            }
        }
    }

    func testGameBoyLayoutFollowsTheHardware() {
        let layout = TouchControlLayout.make(.gameBoy, width: 393, height: 852, safeTop: 59, safeBottom: 34)
        XCTAssertLessThan(layout.dpad.x + layout.dpad.width, layout.b.x, "the D-pad is left of the buttons")
        XCTAssertGreaterThan(layout.a.x, layout.b.x, "A is right of B")
        XCTAssertLessThan(layout.a.y, layout.b.y, "A is above B")
        XCTAssertGreaterThan(layout.select.y, layout.dpad.y + layout.dpad.height - 1, "SELECT and START sit below")
        XCTAssertGreaterThanOrEqual(layout.screen.y, 59, "the picture clears the status bar")
    }

    func testPlaytilesLayoutUsesTheSkinFramesWithStartAndSelectSwapped() {
        let layout = TouchControlLayout.make(.playtiles, width: 1080, height: 2340)
        XCTAssertEqual(layout.a, TouchRect(x: 800, y: 1469, width: 184, height: 184))
        XCTAssertEqual(layout.b, TouchRect(x: 662, y: 1269, width: 184, height: 184))
        XCTAssertEqual(layout.select, TouchRect(x: 702, y: 1901, width: 108, height: 108))
        XCTAssertEqual(layout.start, TouchRect(x: 863, y: 1900, width: 108, height: 108))
        XCTAssertEqual(layout.dpadHitArea, TouchRect(x: 44, y: 1223, width: 462, height: 496))

        XCTAssertEqual(layout.action(at: TouchPoint(x: 540, y: 650)), .toggleFastForward)
        XCTAssertEqual(layout.action(at: TouchPoint(x: 148, y: 1953)), .menu)
        XCTAssertNil(layout.action(at: TouchPoint(x: 892, y: 1561)), "A is a Game Boy control")

        let resolver = TouchInputResolver(layout: layout)
        resolver.touchBegan(id: 1, point: TouchPoint(x: 60, y: 1471))
        XCTAssertTrue(resolver.input.left, "the extended edge still reads as the D-pad")
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

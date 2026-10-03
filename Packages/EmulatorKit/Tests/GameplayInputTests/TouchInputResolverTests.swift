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
        // iPhone SE, 16, 16 Pro and 16 Pro Max: points, safe-area top and display scale. iOS 17
        // runs on nothing narrower than 375 points.
        let screens: [(Double, Double, Double, Double)] = [
            (375, 667, 20, 2), (393, 852, 59, 3), (402, 874, 62, 3), (440, 956, 62, 3),
        ]
        for style in TouchControlStyle.allCases {
            for (width, height, top, displayScale) in screens {
                let layout = TouchControlLayout.make(style, width: width, height: height, safeTop: top, displayScale: displayScale)
                let size = "\(style) at \(width)x\(height)"
                let controls = [
                    ("D-pad", layout.dpadHitArea), ("A", layout.a), ("B", layout.b),
                    ("Start", layout.start), ("Select", layout.select),
                ] + layout.actions.filter { $0.key != .toggleFastForward }.map { ("\($0.key)", $0.value) }
                let pictureBottom = layout.screen.y + layout.screen.height

                XCTAssertGreaterThanOrEqual(layout.screen.y, top, "the picture clears the status bar, \(size)")
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

    func testControllerLayoutRawValuesAreStable() {
        // Stored in settings, so renaming a case must not change them.
        XCTAssertEqual(TouchControlStyle.allCases.map(\.rawValue), ["gameBoy", "playtiles"])
    }

    func testGameBoyLayoutIsSameBoysVerticalLayout() {
        // SameBoy's GBVerticalLayout on a 393x852-point, 3x iPhone, worked through by hand.
        let layout = TouchControlLayout.make(.gameBoy, width: 393, height: 852, safeTop: 59, displayScale: 3)
        func center(_ rect: TouchRect) -> (Double, Double) { (rect.center.x, rect.center.y) }

        XCTAssertEqual(layout.screen.width, 1120.0 / 3, accuracy: 0.001, "a whole number of pixels per Game Boy pixel")
        XCTAssertEqual(layout.screen.y, 59 + 2 * (1120.0 / 3 / 40), accuracy: 0.001)
        XCTAssertEqual(center(layout.select).0, 98.25, accuracy: 0.001)
        XCTAssertEqual(center(layout.select).1, 747.08, accuracy: 0.01)
        XCTAssertEqual(center(layout.start).0, 294.75, accuracy: 0.001)
        XCTAssertEqual(center(layout.dpad).1, 607.08, accuracy: 0.01)
        XCTAssertEqual(center(layout.a).0, 339.75, accuracy: 0.001)
        XCTAssertEqual(center(layout.a).1, 584.58, accuracy: 0.01)
        XCTAssertEqual(center(layout.b).0, 249.75, accuracy: 0.001)
        XCTAssertEqual(center(layout.b).1, 629.58, accuracy: 0.01)
        XCTAssertEqual(layout.a.width, 72)
        XCTAssertEqual(layout.dpad.width, 150)
    }

    func testPlaytilesLayoutFollowsTheSkinWithStartAndSelectSwapped() {
        let layout = TouchControlLayout.make(.playtiles, width: 1080, height: 2340)
        XCTAssertGreaterThan(layout.drawnRect(.a)!.width, layout.drawnRect(.b)!.width, "A is the bigger button")
        XCTAssertLessThan(layout.select.x, layout.start.x, "SELECT is on the left")
        XCTAssertEqual(layout.drawnRect(.select), TouchRect(x: 691, y: 1924, width: 134, height: 53))
        XCTAssertEqual(layout.dpadHitArea, TouchRect(x: 44, y: 1223, width: 462, height: 496))
        XCTAssertEqual(Set(layout.actions.keys), [.menu, .toggleFastForward], "no Quick Save or Quick Load")
        let guide = try! XCTUnwrap(layout.alignmentGuide)
        XCTAssertEqual(guide.tab.center.x, 540, accuracy: 0.5, "the U is centered under the screen")
        XCTAssertGreaterThanOrEqual(guide.bar.y, layout.screen.y + layout.screen.height, "the guide is below the picture")
        XCTAssertNil(TouchControlLayout.make(.gameBoy, width: 393, height: 852).alignmentGuide)

        XCTAssertEqual(layout.action(at: TouchPoint(x: 540, y: 650)), .toggleFastForward)
        XCTAssertEqual(layout.action(at: TouchPoint(x: 148, y: 1950)), .menu)
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

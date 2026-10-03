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

    func testBuiltInLayoutsKeepControlsApartAndOffTheGame() throws {
        func overlaps(_ lhs: TouchRect, _ rhs: TouchRect) -> Bool {
            lhs.x < rhs.x + rhs.width && rhs.x < lhs.x + lhs.width &&
                lhs.y < rhs.y + rhs.height && rhs.y < lhs.y + lhs.height
        }
        // iPhone SE, 16, 16 Pro and 16 Pro Max: points, safe-area top and bottom, and display
        // scale. iOS 17 runs on nothing narrower than 375 points.
        let screens: [(Double, Double, Double, Double, Double)] = [
            (375, 667, 20, 0, 2), (393, 852, 59, 34, 3), (402, 874, 62, 34, 3), (440, 956, 62, 34, 3),
        ]
        for style in TouchControlStyle.allCases {
            for (width, height, top, bottom, displayScale) in screens {
                let layout = TouchControlLayout.make(
                    style, width: width, height: height, safeTop: top, safeBottom: bottom, displayScale: displayScale
                )
                let size = "\(style) at \(width)x\(height)"
                let controls = [
                    ("D-pad", layout.dpadHitArea), ("A", layout.a), ("B", layout.b),
                    ("Start", layout.start), ("Select", layout.select),
                ]
                let pictureBottom = layout.screen.y + layout.screen.height
                let logo = try XCTUnwrap(layout.logo)
                let logoArea = try XCTUnwrap(layout.menuAreas.first)
                XCTAssertLessThanOrEqual(logoArea.height, 44.0 + 0.001)
                XCTAssertGreaterThanOrEqual(logoArea.height, 44.0 - 0.001, "the logo's tap area is 44 points tall, \(size)")
                XCTAssertLessThanOrEqual(logo.y + logo.height, height - max(bottom, 12), "the logo clears the home indicator, \(size)")

                XCTAssertGreaterThanOrEqual(layout.screen.y, top, "the picture clears the status bar, \(size)")
                XCTAssertLessThanOrEqual(layout.select.x + layout.select.width, layout.start.x, "SELECT is left of START, \(size)")
                for (index, (name, rect)) in controls.enumerated() {
                    XCTAssertTrue(rect.x >= 0 && rect.y >= 0 && rect.x + rect.width <= width && rect.y + rect.height <= height,
                                  "\(name) is on screen, \(size)")
                    XCTAssertGreaterThanOrEqual(rect.y, pictureBottom, "\(name) covers the game picture, \(size)")
                    if style == .gameBoy {
                        XCTAssertLessThanOrEqual(rect.y + rect.height, logo.y, "\(name) runs into the logo, \(size)")
                    }
                    XCTAssertFalse(overlaps(rect, logoArea), "\(name) overlaps the logo's tap area, \(size)")
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
        XCTAssertEqual(ControllerTheme.allCases.map(\.rawValue), ["matchSystem", "classic", "dark"])
        XCTAssertEqual(ScreenScaling.allCases.map(\.rawValue), ["integer", "fill"])
    }

    func testGameBoyLayoutFollowsTheHardware() {
        let mm = 6.1 // points per millimeter, as the layout draws
        for (width, height, top, bottom, displayScale) in [(375.0, 667.0, 20.0, 0.0, 2.0), (393, 852, 59, 34, 3), (440, 956, 62, 34, 3)] {
            let layout = TouchControlLayout.make(
                .gameBoy, width: width, height: height, safeTop: top, safeBottom: bottom, displayScale: displayScale
            )
            let size = "\(width)x\(height)"
            let pixelsAcross = layout.screen.width * displayScale / 160
            XCTAssertEqual(pixelsAcross, pixelsAcross.rounded(), accuracy: 0.001, "whole device pixels per Game Boy pixel, \(size)")
            XCTAssertEqual(layout.drawnRect(.dpad)!.width, 22.9 * mm, accuracy: 0.01, "the D-pad is life-size, \(size)")
            XCTAssertEqual(layout.drawnRect(.a)!.width, 10.8 * mm, accuracy: 0.01, "A is life-size, \(size)")

            let a = layout.drawnRect(.a)!.center, b = layout.drawnRect(.b)!.center
            let tilt = atan2(b.y - a.y, a.x - b.x) * 180 / .pi
            XCTAssertEqual(tilt, 24.6, accuracy: 0.5, "A and B sit on the Game Boy's angle, \(size)")
            XCTAssertEqual(hypot(a.x - b.x, a.y - b.y), 16.8 * mm, accuracy: 1, "A and B keep the Game Boy's spacing, \(size)")
            XCTAssertLessThan(a.y, layout.dpad.center.y, "A sits higher than the D-pad's center, \(size)")
            XCTAssertEqual(layout.select.center.y, layout.start.center.y, "SELECT and START sit side by side, \(size)")
            XCTAssertEqual((layout.select.center.x + layout.start.center.x) / 2, layout.logo!.center.x, accuracy: 0.001, "centered under the logo, \(size)")

            let bezel = layout.bezel!, logo = layout.logo!
            let above = layout.dpad.y - (bezel.y + bezel.height)
            let below = logo.y - (layout.select.center.y + 26)
            XCTAssertEqual(above, below, accuracy: 1, "the controls are centered between the bezel and the logo, \(size)")
        }
    }

    func testIntegerScalingUsesWholeDevicePixelsAndFillUsesTheFrame() {
        // The Playtiles frame on a 393-point, 3x phone: 385 x 346.4 points.
        let frame = TouchRect(x: 4, y: 60.77, width: 385, height: 346.38)
        let integer = ScreenScaling.integer.picture(sourceWidth: 160, sourceHeight: 144, in: frame, pixelsPerPoint: 3)
        XCTAssertEqual(integer.width * 3, 1120, accuracy: 0.001, "7 device pixels per Game Boy pixel")
        XCTAssertEqual(integer.height * 3, 1008, accuracy: 0.001)
        XCTAssertEqual(integer.x * 3, (integer.x * 3).rounded(), accuracy: 0.001, "starts on a device pixel")
        XCTAssertEqual(integer.y * 3, (integer.y * 3).rounded(), accuracy: 0.001)
        XCTAssertEqual(integer.center.x, frame.center.x, accuracy: 0.34, "centered")

        let fill = ScreenScaling.fill.picture(sourceWidth: 160, sourceHeight: 144, in: frame, pixelsPerPoint: 3)
        XCTAssertEqual(fill.height, frame.height, accuracy: 0.01, "as tall as the frame, which limits it")
        XCTAssertEqual(fill.width, frame.height / 0.9, accuracy: 0.01, "at the Game Boy's shape")

        let tiny = ScreenScaling.integer.picture(sourceWidth: 160, sourceHeight: 144, in: TouchRect(x: 0, y: 0, width: 100, height: 90), pixelsPerPoint: 1)
        XCTAssertEqual(tiny.width, 100, accuracy: 0.001, "too small for a whole multiple, so it fills")

        for (width, displayScale) in [(393.0, 3.0), (440, 3)] {
            let integerLayout = TouchControlLayout.make(.gameBoy, width: width, height: 900, safeTop: 59, displayScale: displayScale)
            let fillLayout = TouchControlLayout.make(.gameBoy, width: width, height: 900, safeTop: 59, displayScale: displayScale, scaling: .fill)
            XCTAssertEqual(fillLayout.screen.width, width - 16, accuracy: 0.001, "Fill uses the width, \(width)")
            XCTAssertLessThanOrEqual(integerLayout.screen.width, fillLayout.screen.width)
        }
    }

    func testPlaytilesLayoutFollowsTheSkinWithStartAndSelectSwapped() {
        let layout = TouchControlLayout.make(.playtiles, width: 1080, height: 2340)
        XCTAssertGreaterThan(layout.drawnRect(.a)!.width, layout.drawnRect(.b)!.width, "A is the bigger button")
        XCTAssertLessThan(layout.select.x, layout.start.x, "SELECT is on the left")
        XCTAssertEqual(layout.drawnRect(.select), TouchRect(x: 691, y: 1924, width: 134, height: 53))
        XCTAssertEqual(layout.dpadHitArea, TouchRect(x: 44, y: 1223, width: 462, height: 496))
        let guide = try! XCTUnwrap(layout.alignmentGuide)
        XCTAssertEqual(guide.tab.center.x, 540, accuracy: 0.5, "the U is centered under the screen")
        XCTAssertGreaterThanOrEqual(guide.bar.y, layout.screen.y + layout.screen.height, "the guide is below the picture")
        XCTAssertNil(TouchControlLayout.make(.gameBoy, width: 393, height: 852).alignmentGuide)

        XCTAssertFalse(layout.opensMenu(at: TouchPoint(x: 148, y: 1950)), "the skin's Menu button is left out")
        XCTAssertFalse(layout.opensMenu(at: TouchPoint(x: 892, y: 1561)), "A is a Game Boy control")

        let resolver = TouchInputResolver(layout: layout)
        resolver.touchBegan(id: 1, point: TouchPoint(x: 60, y: 1471))
        XCTAssertTrue(resolver.input.left, "the extended edge still reads as the D-pad")
    }

    func testTheLogoOpensTheMenuAndThePictureOnlyWhenTurnedOn() throws {
        for style in TouchControlStyle.allCases {
            func layout(pictureOpensMenu: Bool) -> TouchControlLayout {
                .make(style, width: 393, height: 852, safeTop: 59, safeBottom: 34, displayScale: 3, pictureOpensMenu: pictureOpensMenu)
            }
            let standard = layout(pictureOpensMenu: false)
            let logo = try XCTUnwrap(standard.logo)
            XCTAssertTrue(standard.opensMenu(at: logo.center), "the logo, \(style)")
            XCTAssertTrue(standard.opensMenu(at: TouchPoint(x: logo.center.x, y: logo.y - 14)), "just above the logo, \(style)")
            XCTAssertFalse(standard.opensMenu(at: standard.screen.center), "the picture by default, \(style)")
            XCTAssertFalse(standard.opensMenu(at: standard.start.center), "START, \(style)")
            XCTAssertFalse(standard.opensMenu(at: TouchPoint(x: 196.5, y: standard.select.center.y)), "between SELECT and START, \(style)")
            XCTAssertTrue(layout(pictureOpensMenu: true).opensMenu(at: standard.screen.center), "the picture when on, \(style)")
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

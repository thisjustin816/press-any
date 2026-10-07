import GameplayInput
import XCTest

final class LandscapeLayoutTests: XCTestCase {
    private let phones: [(width: Double, height: Double, side: Double, bottom: Double, scale: Double)] = [
        (667, 375, 0, 0, 2), (852, 393, 59, 21, 3),
        (874, 402, 62, 21, 3), (956, 440, 62, 21, 3),
    ]

    func testLandscapeControlsPictureAndMenuFitSafeAreasWithoutOverlapping() throws {
        for phone in phones {
            for scaling in ScreenScaling.allCases {
                for (left, right) in [(phone.side, phone.side), (phone.side, 0), (0, phone.side)] {
                    let layout = TouchControlLayout.make(
                        .gameBoy, width: phone.width, height: phone.height, safeBottom: phone.bottom,
                        safeLeft: left, safeRight: right, displayScale: phone.scale, scaling: scaling
                    )
                    let bezel = try XCTUnwrap(layout.bezel)
                    let logo = try XCTUnwrap(layout.logo)
                    let touches = [layout.dpadHitArea, layout.a, layout.b, layout.start, layout.select] + layout.menuAreas
                    let rects = touches + Array(layout.artwork.values) + [layout.screen, bezel, logo]
                    for rect in rects {
                        XCTAssertGreaterThan(rect.width, 0)
                        XCTAssertGreaterThan(rect.height, 0)
                        XCTAssertGreaterThanOrEqual(rect.x, left - 0.001)
                        XCTAssertGreaterThanOrEqual(rect.y, 0)
                        XCTAssertLessThanOrEqual(rect.x + rect.width, phone.width - right + 0.001)
                        XCTAssertLessThanOrEqual(rect.y + rect.height, phone.height - phone.bottom + 0.001)
                    }
                    for (index, rect) in touches.enumerated() {
                        XCTAssertFalse(overlaps(rect, layout.screen))
                        for other in touches.dropFirst(index + 1) { XCTAssertFalse(overlaps(rect, other)) }
                    }
                    XCTAssertEqual(layout.screen.center.x, phone.width / 2, accuracy: 1 / phone.scale)
                    XCTAssertEqual(bezel.center.x, layout.screen.center.x, accuracy: 0.001)
                    XCTAssertEqual(logo.center.x, phone.width / 2, accuracy: 0.001)
                    XCTAssertLessThan(layout.screen.center.y, phone.height / 2)
                    XCTAssertLessThan(layout.dpad.center.y, phone.height / 2)
                    XCTAssertLessThan(layout.dpadHitArea.x + layout.dpadHitArea.width, bezel.x)
                    XCTAssertGreaterThan(layout.b.x, bezel.x + bezel.width)
                    XCTAssertGreaterThan(layout.a.x, layout.b.x)
                    XCTAssertLessThan(layout.a.center.y, layout.b.center.y)
                    XCTAssertLessThan(layout.start.center.y, layout.select.center.y)
                    XCTAssertGreaterThan(layout.start.y, layout.dpadHitArea.y + layout.dpadHitArea.height)
                    // As on a Game Boy Advance: right of the D-pad's center, short of the bezel, and
                    // START directly above SELECT, each with a name plate to its left.
                    let startButton = try XCTUnwrap(layout.drawnRect(.start))
                    let selectButton = try XCTUnwrap(layout.drawnRect(.select))
                    XCTAssertGreaterThan(startButton.center.x, layout.dpad.center.x)
                    XCTAssertLessThan(startButton.x + startButton.width, bezel.x)
                    XCTAssertEqual(startButton.center.x, selectButton.center.x, accuracy: 0.001)
                    XCTAssertLessThan(startButton.width, layout.drawnRect(.a)!.width)
                    for (control, button) in [(TouchControl.start, startButton), (.select, selectButton)] {
                        let plate = try XCTUnwrap(layout.labelPlates[control])
                        XCTAssertLessThan(plate.center.x, button.center.x)
                    }
                    XCTAssertGreaterThan(layout.labelPlateTilt, 0)
                    XCTAssertEqual(layout.selectStartTilt, 0)
                    XCTAssertNil(layout.alignmentGuide)
                    for control in [TouchControl.dpad, .a, .b, .start, .select] {
                        let art = try XCTUnwrap(layout.drawnRect(control))
                        let hit = control == .dpad ? layout.dpadHitArea : control == .a ? layout.a
                            : control == .b ? layout.b : control == .start ? layout.start : layout.select
                        XCTAssertLessThanOrEqual(hit.x, art.x + 0.001)
                        XCTAssertGreaterThanOrEqual(hit.x + hit.width, art.x + art.width - 0.001)
                        XCTAssertLessThan(hit.y, art.y)
                        XCTAssertGreaterThan(hit.y + hit.height, art.y + art.height)
                    }
                    if scaling == .integer {
                        let multiple = layout.screen.width * phone.scale / 160
                        XCTAssertEqual(multiple, multiple.rounded(), accuracy: 0.001)
                        XCTAssertEqual(layout.screen.height * phone.scale / 144, multiple, accuracy: 0.001)
                        XCTAssertEqual(layout.screen.x * phone.scale, (layout.screen.x * phone.scale).rounded(), accuracy: 0.001)
                        XCTAssertEqual(layout.screen.y * phone.scale, (layout.screen.y * phone.scale).rounded(), accuracy: 0.001)
                    }
                }
            }
        }
    }

    func testLandscapeReusesPortraitDPadAndButtonSizesAndAngle() throws {
        for phone in phones {
            let portrait = TouchControlLayout.make(.gameBoy, width: phone.height, height: phone.width)
            let landscape = TouchControlLayout.make(.gameBoy, width: phone.width, height: phone.height,
                                                    safeBottom: phone.bottom, safeLeft: phone.side, safeRight: phone.side)
            // START and SELECT become the Game Boy Advance's small round buttons instead.
            for control in [TouchControl.dpad, .a, .b] {
                let old = try XCTUnwrap(portrait.drawnRect(control)), new = try XCTUnwrap(landscape.drawnRect(control))
                XCTAssertEqual(new.width, old.width)
                XCTAssertEqual(new.height, old.height)
            }
            let a = landscape.a.center, b = landscape.b.center
            XCTAssertEqual(atan2(b.y - a.y, a.x - b.x) * 180 / .pi, 24.6, accuracy: 0.5)
        }
    }

    func testLandscapeUsesTheSameLayoutRegardlessOfPortraitStyleAndKeepsMenuTargets() throws {
        let gameBoy = TouchControlLayout.make(.gameBoy, width: 874, height: 402, safeLeft: 62, safeRight: 62)
        XCTAssertEqual(gameBoy, .make(.playtiles, width: 874, height: 402, safeLeft: 62, safeRight: 62))
        XCTAssertTrue(gameBoy.opensMenu(at: try XCTUnwrap(gameBoy.logo).center))
        XCTAssertFalse(gameBoy.opensMenu(at: gameBoy.screen.center))
        let pictureMenu = TouchControlLayout.make(.gameBoy, width: 874, height: 402, pictureOpensMenu: true)
        XCTAssertTrue(pictureMenu.opensMenu(at: pictureMenu.screen.center))
        XCTAssertFalse(pictureMenu.opensMenu(at: pictureMenu.a.center))
    }

    func testSideInsetsDoNotChangePortraitLayouts() {
        for style in TouchControlStyle.allCases {
            for phone in phones {
                let original = TouchControlLayout.make(style, width: phone.height, height: phone.width)
                let withSides = TouchControlLayout.make(style, width: phone.height, height: phone.width, safeLeft: 62, safeRight: 62)
                XCTAssertEqual(original, withSides)
            }
        }
    }

    private func overlaps(_ lhs: TouchRect, _ rhs: TouchRect) -> Bool {
        lhs.x < rhs.x + rhs.width && rhs.x < lhs.x + lhs.width
            && lhs.y < rhs.y + rhs.height && rhs.y < lhs.y + lhs.height
    }
}

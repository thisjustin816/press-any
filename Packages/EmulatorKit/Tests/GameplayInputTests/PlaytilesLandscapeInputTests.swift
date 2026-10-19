import EmulationCore
import GameplayInput
import XCTest

final class PlaytilesLandscapeInputTests: XCTestCase {
    func testRightPadHasAAboveAndRightAndBLeftAndBelow() throws {
        let layout = TouchControlLayout.make(.playtiles, width: 874, height: 402)
        let up = try XCTUnwrap(layout.additionalButtons.first { $0.control == .a }).artwork
        let left = try XCTUnwrap(layout.additionalButtons.first { $0.control == .b }).artwork
        let right = try XCTUnwrap(layout.drawnRect(.a))
        let down = try XCTUnwrap(layout.drawnRect(.b))
        XCTAssertEqual(up.center.x, down.center.x, accuracy: 0.001)
        XCTAssertEqual(left.center.y, right.center.y, accuracy: 0.001)
        XCTAssertLessThan(up.center.y, left.center.y)
        XCTAssertLessThan(left.center.y, down.center.y)
        XCTAssertLessThan(left.center.x, up.center.x)
        XCTAssertLessThan(up.center.x, right.center.x)
    }

    func testRightDPadSendsFaceButtonsAndBothTilesSendStartAndSelect() throws {
        let layout = TouchControlLayout.make(.playtiles, width: 852, height: 393, safeBottom: 21, safeLeft: 59)
        XCTAssertEqual(layout.additionalButtons.count, 4)
        let resolver = TouchInputResolver(layout: layout)
        for (rect, expected) in [
            (layout.a, EmulatorInputState(a: true)),
            (layout.b, EmulatorInputState(b: true)),
            (layout.start, EmulatorInputState(start: true)),
            (layout.select, EmulatorInputState(select: true)),
        ] {
            resolver.touchBegan(id: 1, point: rect.center)
            XCTAssertEqual(resolver.input, expected)
            resolver.touchEnded(id: 1)
        }
        for button in layout.additionalButtons {
            let expected: EmulatorInputState
            switch button.control {
            case .a: expected = .init(a: true)
            case .b: expected = .init(b: true)
            case .start: expected = .init(start: true)
            case .select: expected = .init(select: true)
            case .dpad: XCTFail("the right D-pad sends buttons, not directions"); continue
            }
            resolver.touchBegan(id: 1, point: button.area.center)
            XCTAssertEqual(resolver.input, expected)
            resolver.touchEnded(id: 1)
        }
        let duplicateA = try XCTUnwrap(layout.additionalButtons.first { $0.control == .a })
        let duplicateB = try XCTUnwrap(layout.additionalButtons.first { $0.control == .b })
        XCTAssertLessThan(duplicateA.area.center.y, layout.a.center.y, "Up duplicates Right's A")
        XCTAssertLessThan(duplicateB.area.center.x, layout.b.center.x, "Left duplicates Down's B")
    }

    func testDuplicateButtonsCombineWithDirectionsAndReleaseIndependently() throws {
        let layout = TouchControlLayout.make(.playtiles, width: 852, height: 393)
        let duplicateA = try XCTUnwrap(layout.additionalButtons.first { $0.control == .a })
        let duplicateB = try XCTUnwrap(layout.additionalButtons.first { $0.control == .b })
        let resolver = TouchInputResolver(layout: layout)
        resolver.touchBegan(id: 1, point: .init(x: layout.dpad.center.x, y: layout.dpad.y))
        resolver.touchBegan(id: 2, point: layout.a.center)
        resolver.touchBegan(id: 3, point: duplicateA.area.center)
        XCTAssertEqual(resolver.input, .init(up: true, a: true))
        resolver.touchEnded(id: 2)
        XCTAssertEqual(resolver.input, .init(up: true, a: true))
        resolver.touchMoved(id: 3, point: duplicateB.area.center)
        XCTAssertEqual(resolver.input, .init(up: true, b: true))
        resolver.touchBegan(id: 4, point: duplicateA.area.center)
        XCTAssertEqual(resolver.input, .init(up: true, a: true, b: true))
        resolver.cancelAllTouches()
        XCTAssertEqual(resolver.input, .init())
    }
}

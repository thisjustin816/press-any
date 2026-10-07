import EmulationCore
import Foundation
import GameplayInput
import XCTest

final class GamepadInputMappingTests: XCTestCase {
    func testRadialDeadZone() {
        for (x, y) in [(0, 0), (0.25, 0), (-0.25, 0), (0, 0.25), (0, -0.25), (0.17, 0.17)] {
            XCTAssertEqual(GamepadInputMapping.directions(x: Float(x), y: Float(y)), .init())
        }
        XCTAssertEqual(GamepadInputMapping.directions(x: 0.18, y: 0.18), .init(up: true, right: true))
        XCTAssertEqual(GamepadInputMapping.directions(x: 0.251, y: 0), .init(right: true))
    }

    func testEightEqualSectorsIncludingTheirEdges() {
        let directions: [EmulatorInputState] = [
            .init(right: true), .init(up: true, right: true), .init(up: true),
            .init(up: true, left: true), .init(left: true), .init(down: true, left: true),
            .init(down: true), .init(down: true, right: true)
        ]
        for (sector, expected) in directions.enumerated() {
            for offset in [-22.49, 0, 22.49] {
                let angle = (Double(sector) * 45 + offset) * .pi / 180
                XCTAssertEqual(
                    GamepadInputMapping.directions(x: Float(cos(angle)), y: Float(sin(angle))),
                    expected, "sector \(sector), offset \(offset)"
                )
            }
        }
    }

    func testDpadAndStickBothDriveDirections() {
        XCTAssertEqual(
            GamepadInputMapping.input(dpad: .init(up: true), leftStickX: -1),
            .init(up: true, left: true)
        )
        XCTAssertEqual(GamepadInputMapping.input(dpad: .init(down: true)), .init(down: true))
        XCTAssertEqual(GamepadInputMapping.input(leftStickY: -1), .init(down: true))
        XCTAssertEqual(GamepadInputMapping.input(), .init())
    }

    func testFaceButtonsFollowTheirLetters() {
        XCTAssertEqual(GamepadInputMapping.input(buttonA: true), .init(a: true))
        XCTAssertEqual(GamepadInputMapping.input(buttonB: true), .init(b: true))
        XCTAssertEqual(GamepadInputMapping.input(buttonA: true, buttonB: true), .init(a: true, b: true))
    }

    func testMenuIsStartAndEitherOptionsOrLeftShoulderIsSelect() {
        XCTAssertEqual(GamepadInputMapping.input(menu: true), .init(start: true))
        XCTAssertEqual(GamepadInputMapping.input(options: true), .init(select: true))
        XCTAssertEqual(GamepadInputMapping.input(leftShoulder: true), .init(select: true))
        XCTAssertEqual(GamepadInputMapping.input(menu: true, options: true, leftShoulder: true), .init(start: true, select: true))
    }
}

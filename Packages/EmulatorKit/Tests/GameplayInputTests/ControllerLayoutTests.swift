import GameplayInput
import XCTest

final class ControllerLayoutTests: XCTestCase {
    func testAControllerUsesGameBoyWithoutChangingTheChosenLayout() {
        for chosen in TouchControlStyle.allCases {
            XCTAssertEqual(chosen.forGameplay(controllerConnected: false), chosen)
            XCTAssertEqual(chosen.forGameplay(controllerConnected: true), .gameBoy)
            XCTAssertEqual(chosen.forGameplay(controllerConnected: false), chosen)
        }
    }
}

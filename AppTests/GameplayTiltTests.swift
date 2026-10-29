import XCTest
@testable import PressAny

final class GameplayTiltTests: XCTestCase {
    func testGravityTurnsWithTheScreen() {
        // Right edge down in portrait: gravity along the phone's +x.
        let portrait = GameplayTilt.reading(gravityX: 0.5, gravityY: -0.8, orientation: .portrait)
        XCTAssertEqual(portrait.x, -0.5, accuracy: 1e-9)
        XCTAssertEqual(portrait.y, -0.8, accuracy: 1e-9)
        // The same tilt toward the screen's right edge, held in each landscape orientation.
        let right = GameplayTilt.reading(gravityX: -0.8, gravityY: -0.5, orientation: .landscapeRight)
        XCTAssertEqual(right.x, -0.5, accuracy: 1e-9)
        XCTAssertEqual(right.y, -0.8, accuracy: 1e-9)
        let left = GameplayTilt.reading(gravityX: 0.8, gravityY: 0.5, orientation: .landscapeLeft)
        XCTAssertEqual(left.x, -0.5, accuracy: 1e-9)
        XCTAssertEqual(left.y, -0.8, accuracy: 1e-9)
    }
}

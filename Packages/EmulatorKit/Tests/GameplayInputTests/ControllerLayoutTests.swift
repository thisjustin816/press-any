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

    func testAnIncompatiblePhoneUsesGameBoyWithoutChangingTheChosenLayout() {
        for chosen in TouchControlStyle.allCases {
            XCTAssertEqual(chosen.forGameplay(controllerConnected: false, playtilesSupported: false), .gameBoy)
            XCTAssertEqual(chosen.forGameplay(controllerConnected: true, playtilesSupported: false), .gameBoy)
            XCTAssertEqual(chosen.forGameplay(controllerConnected: false, playtilesSupported: true), chosen)
        }
    }

    func testScreensNarrowerThanThePhysicalTileCannotChoosePlaytilesInEitherOrientation() {
        // SE, mini, XS/11 Pro, 12/13, 14/15 Pro, and 16 Pro display classes.
        for (width, height) in [(750.0, 1334.0), (1080, 2340), (1125, 2436),
                                (1170, 2532), (1179, 2556), (1206, 2622)] {
            for (w, h) in [(width, height), (height, width)] {
                XCTAssertFalse(TouchControlStyle.playtiles.isAvailable(nativeWidth: w, nativeHeight: h))
                XCTAssertTrue(TouchControlStyle.gameBoy.isAvailable(nativeWidth: w, nativeHeight: h))
            }
        }
    }

    func testScreensWideEnoughForThePhysicalTileCanChoosePlaytilesInEitherOrientation() {
        // XS/11 Pro Max, 12/13 Pro Max and 14 Plus, 14/15 Pro Max, and 16 Pro Max.
        for (width, height) in [(1242.0, 2688.0), (1284, 2778), (1290, 2796), (1320, 2868)] {
            for (w, h) in [(width, height), (height, width)] {
                XCTAssertTrue(TouchControlStyle.playtiles.isAvailable(nativeWidth: w, nativeHeight: h))
                XCTAssertTrue(TouchControlStyle.gameBoy.isAvailable(nativeWidth: w, nativeHeight: h))
            }
        }
    }
}

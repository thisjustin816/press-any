import XCTest
@testable import PressAny

final class PressAnyAppTests: XCTestCase {
    /// The tests run hosted in the app, so this reads the app's own Info.plist.
    func testDisplayNameComesFromTheBundle() {
        XCTAssertEqual(AppBrand.displayName, "Press Any")
    }
}

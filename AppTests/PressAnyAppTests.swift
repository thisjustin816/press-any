import XCTest
@testable import PressAny

final class PressAnyAppTests: XCTestCase {
    /// The tests run hosted in the app, so this reads the app's own Info.plist.
    func testDisplayNameComesFromTheBundle() {
        XCTAssertEqual(AppBrand.displayName, "Press Any")
    }

    func testWordmarkAccentsTheFirstLetterOfTheLastWord() {
        XCTAssertTrue(AppBrand.Wordmark.parts == ("Press ", "A", "ny"))
        XCTAssertTrue(AppBrand.Wordmark.split("Pocket") == ("", "P", "ocket"))
        XCTAssertTrue(AppBrand.Wordmark.split("") == ("", "", ""))
    }
}

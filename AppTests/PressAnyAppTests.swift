import XCTest
@testable import PressAny

final class PressAnyAppTests: XCTestCase {
    /// The tests run hosted in the app, so this reads the app's own Info.plist.
    func testDisplayNameComesFromTheBundle() {
        XCTAssertEqual(AppBrand.displayName, "Press Any")
    }

    /// SameBoy's and GRDB's licenses ask for their notices to ship with the app.
    func testThirdPartyLicensesShipWithTheApp() throws {
        for (file, holder) in [("SameBoy-LICENSE", "Lior Halphon"), ("GRDB-LICENSE", "Gwendal Rou")] {
            let url = try XCTUnwrap(Bundle.main.url(forResource: file, withExtension: "txt"), file)
            XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains(holder), file)
        }
    }

    func testWordmarkAccentsTheFirstLetterOfTheLastWord() {
        XCTAssertTrue(AppBrand.Wordmark.parts == ("Press ", "A", "ny"))
        XCTAssertTrue(AppBrand.Wordmark.split("Pocket") == ("", "P", "ocket"))
        XCTAssertTrue(AppBrand.Wordmark.split("") == ("", "", ""))
    }
}

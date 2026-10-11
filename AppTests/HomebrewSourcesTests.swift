import XCTest
@testable import PressAny

/// The empty library's links go to the sites over HTTPS and nowhere else.
final class HomebrewSourcesTests: XCTestCase {
    func testTheLinksAreHTTPSPagesOnTheirOwnSites() {
        XCTAssertEqual(HomebrewSources.homebrewHub.scheme, "https")
        XCTAssertEqual(HomebrewSources.homebrewHub.host, "hh.gbdev.io")
        XCTAssertEqual(HomebrewSources.itch.scheme, "https")
        XCTAssertEqual(HomebrewSources.itch.host, "itch.io")
        XCTAssertEqual(HomebrewSources.itch.path, "/games/tag-gameboy-rom")
    }
}

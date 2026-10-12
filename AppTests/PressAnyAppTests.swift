import XCTest
import UIKit
@testable import PressAny

final class PressAnyAppTests: XCTestCase {
    /// The tests run hosted in the app, so this reads the app's own Info.plist.
    func testDisplayNameComesFromTheBundle() {
        XCTAssertEqual(AppBrand.displayName, "Press Any")
    }

    func testThirdPartyLicensesShipWithTheApp() throws {
        for (file, holder) in [
            ("SameBoy-LICENSE", "Lior Halphon"),
            ("GRDB-LICENSE", "Gwendal Rou"),
            ("Corporatus-LICENSE", "Alex Rosario"),
        ] {
            let url = try XCTUnwrap(Bundle.main.url(forResource: file, withExtension: "txt"), file)
            XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains(holder), file)
        }
    }

    func testWordmarkArtworkShipsInBothAppearances() throws {
        for appearance in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: appearance)
            for name in ["Wordmark", "WordmarkRecess", "WordmarkPlaque"] {
                let image = try XCTUnwrap(UIImage(named: name, in: .main, compatibleWith: traits), name)
                XCTAssertGreaterThan(image.size.width, 0, name)
                XCTAssertGreaterThan(image.size.height, 0, name)
            }
            let artwork = AppBrand.Wordmark.artwork(size: 28, appearance: appearance)
            XCTAssertEqual(artwork.size.height, 28)
            XCTAssertGreaterThan(artwork.size.width, artwork.size.height)
        }
    }
}

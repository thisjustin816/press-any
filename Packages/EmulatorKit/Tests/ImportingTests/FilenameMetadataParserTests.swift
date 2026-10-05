import Foundation
import XCTest
@testable import Importing

final class FilenameMetadataParserTests: XCTestCase {
    func testRecognizedTagsBecomeSeparateFieldsWithoutLosingOriginalGroups() {
        let parsed = FilenameMetadataParser.parse(filename: "Example (USA, Europe) (En,Fr,De) (Rev A) [v1.10.2] [Unknown].gbc")
        XCTAssertEqual(parsed.suggestedTitle, "Example")
        XCTAssertEqual(parsed.buildMetadata, BuildImportMetadata(region: "USA, Europe", language: "En, Fr, De", revision: "A", versionString: "1.10.2"))
        XCTAssertEqual(parsed.bracketGroups, ["v1.10.2", "Unknown"])
        XCTAssertEqual(parsed.originalBaseName, "Example (USA, Europe) (En,Fr,De) (Rev A) [v1.10.2] [Unknown]")
    }

    func testExplicitHomebrewVersionSuffixDoesNotClutterTheSuggestedTitle() {
        let parsed = FilenameMetadataParser.parse(filename: "Example v1.2.0 (World).gb")
        XCTAssertEqual(parsed.suggestedTitle, "Example")
        XCTAssertEqual(parsed.buildMetadata.versionString, "1.2.0")
        XCTAssertEqual(parsed.buildMetadata.region, "World")
    }

    func testUnknownOrMixedTagsDoNotInventMetadata() {
        let parsed = FilenameMetadataParser.parse(filename: "Example 2 (USA, Unknown) [En,Author] [beta] [v1.2beta].gb")
        XCTAssertEqual(parsed.suggestedTitle, "Example 2")
        XCTAssertEqual(parsed.buildMetadata, BuildImportMetadata())
    }

    func testNumericVersionKeysOrderNumericallyAndNormalizeTrailingZeroes() throws {
        let key = { (version: String) in BuildImportMetadata(versionString: version).versionSortKey }
        XCTAssertLessThan(try XCTUnwrap(key("1.2")), try XCTUnwrap(key("1.10")))
        XCTAssertEqual(key("1.2"), key("1.2.0"))
        XCTAssertEqual(key("01.02"), key("1.2"))
        for invalid in ["beta", "1..2", "1.2-beta", "1.2.3.4.5", "99999999999", "١.٢"] {
            XCTAssertNil(key(invalid), invalid)
        }
    }

    func testEmptyReviewFieldsBecomeAbsentMetadata() {
        XCTAssertEqual(BuildImportMetadata(region: "  ", language: "\n", revision: "", versionString: " "), BuildImportMetadata())
    }
}

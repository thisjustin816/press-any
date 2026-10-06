import Foundation
import XCTest
@testable import Importing

final class FilenameMetadataParserTests: XCTestCase {
    func testRecognizedTagsBecomeSeparateFieldsWithoutLosingOriginalGroups() {
        let parsed = FilenameMetadataParser.parse(filename: "Example (USA, Europe) (En,Fr,De) (Rev A) [v1.10.2] [Unknown].gbc")
        XCTAssertEqual(parsed.suggestedTitle, "Example")
        XCTAssertEqual(parsed.buildMetadata, BuildImportMetadata(region: "USA, Europe", language: "En, Fr, De", revision: "A", versionString: "1.10.2"))
        XCTAssertEqual(parsed.bracketGroups, ["v1.10.2", "Unknown"])
        XCTAssertEqual(parsed.unknownGroups, ["Unknown"])
        XCTAssertEqual(parsed.originalBaseName, "Example (USA, Europe) (En,Fr,De) (Rev A) [v1.10.2] [Unknown]")
        XCTAssertEqual(parsed.suggestedBuildName, "v1.10.2 · Rev A")
        XCTAssertEqual(parsed.normalizedFilename, "Example (USA, Europe) (En, Fr, De) (Rev A) [v1.10.2] [Unknown].gbc")
        XCTAssertEqual(parsed.releaseKind, .development)
        XCTAssertEqual(parsed.confidence, .high)
    }

    func testExplicitHomebrewVersionSuffixDoesNotClutterTheSuggestedTitle() {
        let parsed = FilenameMetadataParser.parse(filename: "Example v1.2.0 (World).gb")
        XCTAssertEqual(parsed.suggestedTitle, "Example")
        XCTAssertEqual(parsed.buildMetadata.versionString, "1.2.0")
        XCTAssertEqual(parsed.buildMetadata.region, "World")
        XCTAssertEqual(parsed.suggestedBuildName, "v1.2.0")
    }

    func testUnknownOrMixedTagsDoNotInventMetadata() {
        let parsed = FilenameMetadataParser.parse(filename: "Example 2 (USA, Unknown) [En,Author] [candidate] [v1.2beta].gb")
        XCTAssertEqual(parsed.suggestedTitle, "Example 2")
        XCTAssertEqual(parsed.buildMetadata, BuildImportMetadata())
        XCTAssertEqual(parsed.unknownGroups, ["USA, Unknown", "En,Author", "candidate", "v1.2beta"])
        XCTAssertEqual(parsed.releaseKind, .standard)
        XCTAssertEqual(parsed.confidence, .low)
    }

    func testExplicitHackConventionProducesLineageAndConciseNames() {
        let parsed = FilenameMetadataParser.parse(
            filename: "Pokemon Red - PureRed [Hack] [by Vortyne] [v4.7.0] [Beta].gb"
        )

        XCTAssertEqual(parsed.suggestedTitle, "PureRed")
        XCTAssertEqual(parsed.suggestedBuildName, "v4.7.0 · Beta")
        XCTAssertEqual(parsed.releaseKind, .romHack)
        XCTAssertEqual(parsed.confidence, .high)
        XCTAssertEqual(parsed.buildMetadata.baseTitle, "Pokemon Red")
        XCTAssertEqual(parsed.buildMetadata.hackTitle, "PureRed")
        XCTAssertEqual(parsed.buildMetadata.author, "Vortyne")
        XCTAssertEqual(parsed.buildMetadata.status, "Beta")
        XCTAssertEqual(parsed.normalizedFilename, "Pokemon Red - PureRed [v4.7.0] [by Vortyne] [Beta].gb")
    }

    func testLabeledHackMetadataAndTranslationNormalizeWithoutInventingUnknownFields() {
        let parsed = FilenameMetadataParser.parse(
            filename: "Crystal Clear [Base: Pokemon Crystal] [Hack: Crystal Clear] [Translation: Spanish] [Author: ShockSlayer] [v2.5.10].GBC"
        )

        XCTAssertEqual(parsed.suggestedTitle, "Crystal Clear")
        XCTAssertEqual(parsed.buildMetadata.baseTitle, "Pokemon Crystal")
        XCTAssertEqual(parsed.buildMetadata.hackTitle, "Crystal Clear")
        XCTAssertEqual(parsed.buildMetadata.translation, "Spanish")
        XCTAssertEqual(parsed.buildMetadata.author, "ShockSlayer")
        XCTAssertEqual(parsed.normalizedFilename, "Pokemon Crystal - Crystal Clear [v2.5.10] [by ShockSlayer] [Spanish Translation].gbc")
        XCTAssertEqual(parsed.unknownGroups, [])
    }

    func testAuthorTagDoesNotTurnAHomebrewVersionIntoAROMHack() {
        let parsed = FilenameMetadataParser.parse(filename: "Tiny Homebrew v1.4 [by Jane].gb")

        XCTAssertEqual(parsed.releaseKind, .development)
        XCTAssertEqual(parsed.buildMetadata.author, "Jane")
        XCTAssertNil(parsed.buildMetadata.baseTitle)
        XCTAssertNil(parsed.buildMetadata.hackTitle)
    }

    func testSquareBracketHackAndTranslationShorthandIsRecognizedConservatively() {
        let parsed = FilenameMetadataParser.parse(
            filename: "Base Game [Hack: Nueva] [h1] [T+Spa] [v1.0].gb"
        )

        XCTAssertEqual(parsed.releaseKind, .romHack)
        XCTAssertEqual(parsed.suggestedTitle, "Nueva")
        XCTAssertEqual(parsed.buildMetadata.baseTitle, "Base Game")
        XCTAssertEqual(parsed.buildMetadata.hackTitle, "Nueva")
        XCTAssertEqual(parsed.buildMetadata.translation, "Spa")
        XCTAssertEqual(parsed.unknownGroups, [])
        XCTAssertEqual(parsed.normalizedFilename, "Base Game - Nueva [v1.0] [Spa Translation].gb")
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

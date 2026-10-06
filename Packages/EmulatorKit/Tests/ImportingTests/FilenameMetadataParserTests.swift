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

    func testPercentEncodedDescriptiveHackNameIsDecodedAndSplitIntoFields() {
        let parsed = FilenameMetadataParser.parse(
            filename: "Bubble%20Bobble%20Part%202%20(USA,%20Europe)%20[Tearing%20fix%20&%20save%20patch%20by%20thisJUSTin816%20v1.1].gb"
        )

        XCTAssertEqual(parsed.releaseKind, .romHack)
        XCTAssertEqual(parsed.suggestedTitle, "Tearing fix & save patch")
        XCTAssertEqual(parsed.suggestedBuildName, "v1.1")
        XCTAssertEqual(parsed.buildMetadata.baseTitle, "Bubble Bobble Part 2")
        XCTAssertEqual(parsed.buildMetadata.hackTitle, "Tearing fix & save patch")
        XCTAssertEqual(parsed.buildMetadata.author, "thisJUSTin816")
        XCTAssertEqual(parsed.buildMetadata.versionString, "1.1")
        XCTAssertEqual(
            parsed.normalizedFilename,
            "Bubble Bobble Part 2 - Tearing fix & save patch (USA, Europe) [v1.1] [by thisJUSTin816].gb"
        )
    }

    func testNumericVersionKeysOrderNumericallyAndNormalizeTrailingZeroes() throws {
        let key = { (version: String) in BuildImportMetadata(versionString: version).versionSortKey }
        XCTAssertLessThan(try XCTUnwrap(key("1.2")), try XCTUnwrap(key("1.10")))
        XCTAssertEqual(key("1.2"), key("1.2.0"))
        XCTAssertEqual(key("01.02"), key("1.2"))
        for invalid in ["beta", "1..2", "1.2.3.4.5", "99999999999", "١.٢"] {
            XCTAssertNil(key(invalid), invalid)
        }
    }

    func testEmptyReviewFieldsBecomeAbsentMetadata() {
        XCTAssertEqual(BuildImportMetadata(region: "  ", language: "\n", revision: "", versionString: " "), BuildImportMetadata())
    }

    func testADottedRevIsTheHomebrewVersionWithItsBuildSuffix() {
        let parsed = FilenameMetadataParser.parse(filename: "Match%20Land%20%28World%29%20%28En%29%20%28Rev%200.2.0%2Bdeferred6%29.gb")
        XCTAssertEqual(parsed.suggestedTitle, "Match Land")
        XCTAssertEqual(parsed.buildMetadata, BuildImportMetadata(region: "World", language: "En", versionString: "0.2.0+deferred6"))
        XCTAssertEqual(parsed.unknownGroups, [])
        XCTAssertEqual(parsed.suggestedBuildName, "v0.2.0+deferred6")
    }

    func testRetailRevisionsStayRevisions() {
        XCTAssertEqual(FilenameMetadataParser.parse(filename: "Example (USA) (Rev 1).gb").buildMetadata,
                       BuildImportMetadata(region: "USA", revision: "1"))
        XCTAssertEqual(FilenameMetadataParser.parse(filename: "Example (Europe) (Rev A).gb").suggestedBuildName, "Rev A")
    }

    func testSemverPrereleaseAndBuildSuffixesStayInTheVersion() {
        XCTAssertEqual(FilenameMetadataParser.parse(filename: "Example (v1.2.0-beta.3).gbc").buildMetadata.versionString, "1.2.0-beta.3")
        let suffixed = FilenameMetadataParser.parse(filename: "Example v0.9+build5.gb")
        XCTAssertEqual(suffixed.suggestedTitle, "Example")
        XCTAssertEqual(suffixed.buildMetadata.versionString, "0.9+build5")
    }

    func testTitlesThatLookLikeVersionsAreLeftAlone() {
        for (filename, title) in [("R-Type (USA, Europe).gb", "R-Type"), ("Mega Man 2 (USA).gb", "Mega Man 2")] {
            let parsed = FilenameMetadataParser.parse(filename: filename)
            XCTAssertEqual(parsed.suggestedTitle, title)
            XCTAssertNil(parsed.buildMetadata.versionString)
        }
    }

    func testSuffixedVersionsSortWithTheirNumericVersion() {
        let plain = BuildImportMetadata(versionString: "0.2.0").versionSortKey
        let suffixed = BuildImportMetadata(versionString: "0.2.0+deferred6").versionSortKey
        XCTAssertEqual(suffixed, plain.map { $0 + "+deferred6" })
        XCTAssertLessThan(suffixed!, BuildImportMetadata(versionString: "0.3").versionSortKey!)
    }

    func testPrereleasesSortBeforeTheirReleaseAndNumericPartsSortNumerically() throws {
        let key = { (version: String) in try XCTUnwrap(BuildImportMetadata(versionString: version).versionSortKey) }
        XCTAssertLessThan(try key("1.0-beta"), try key("1.0"))
        XCTAssertLessThan(try key("1.0-beta.9"), try key("1.0-beta.10"))
        XCTAssertLessThan(try key("1.0-alpha"), try key("1.0-beta"))
        XCTAssertLessThan(try key("1.0"), try key("1.0.1-rc.1"))
    }
}

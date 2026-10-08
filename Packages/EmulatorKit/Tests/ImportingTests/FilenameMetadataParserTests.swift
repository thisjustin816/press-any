import Foundation
import XCTest
@testable import Importing

final class FilenameMetadataParserTests: XCTestCase {
    func testNumberedDevelopmentFlagsPreserveTheirNumbersAndCanonicalStatus() {
        for (flag, status) in [
            ("Alpha 1", "Alpha 1"), ("Beta 2", "Beta 2"), ("Demo 2", "Demo 2"),
            ("Proto 1", "Prototype 1"), ("Prototype 3", "Prototype 3"),
            ("Preview 4", "Preview 4"), ("RC 2", "RC 2"),
            ("Release Candidate 3", "RC 3"), ("Final 1", "Final 1"),
            ("Beta", "Beta"), ("Proto", "Prototype"),
        ] {
            for spelling in [flag, flag.lowercased(), flag.uppercased()] {
                let parsed = FilenameMetadataParser.parse(filename: "Example (\(spelling)).gb")
                XCTAssertEqual(parsed.suggestedTitle, "Example", spelling)
                XCTAssertEqual(parsed.buildMetadata, BuildImportMetadata(status: status), spelling)
                XCTAssertEqual(parsed.suggestedBuildName, status, spelling)
                XCTAssertEqual(
                    parsed.normalizedFilename,
                    "Example (\(status.replacingOccurrences(of: "Prototype", with: "Proto"))).gb",
                    spelling
                )
                XCTAssertEqual(parsed.releaseKind, .development, spelling)
                XCTAssertEqual(parsed.unknownGroups, [], spelling)
            }
        }
    }

    func testOtherNoIntroDevelopmentFlagsBecomeStatuses() {
        for status in ["Sample", "Kiosk", "Debug"] {
            for spelling in [status, status.lowercased(), status.uppercased()] {
                let parsed = FilenameMetadataParser.parse(filename: "Example (\(spelling)).gb")
                XCTAssertEqual(parsed.suggestedTitle, "Example", spelling)
                XCTAssertEqual(parsed.buildMetadata, BuildImportMetadata(status: status), spelling)
                XCTAssertEqual(parsed.suggestedBuildName, status, spelling)
                XCTAssertEqual(parsed.normalizedFilename, "Example (\(status)).gb", spelling)
                XCTAssertEqual(parsed.releaseKind, .development, spelling)
                XCTAssertEqual(parsed.unknownGroups, [], spelling)
            }
        }
    }

    func testAftermarketAndUnlicensedFlagsAreDroppedWithoutChangingReleaseKindOrConfidence() {
        for flags in ["(Aftermarket)", "(Unl)", "(Aftermarket) (Unl)", "(aftermarket) (unl)", "(AFTERMARKET) (UNL)"] {
            let parsed = FilenameMetadataParser.parse(filename: "Example \(flags).gb")
            XCTAssertEqual(parsed.suggestedTitle, "Example", flags)
            XCTAssertEqual(parsed.buildMetadata, BuildImportMetadata(), flags)
            XCTAssertEqual(parsed.suggestedBuildName, "Original", flags)
            XCTAssertEqual(parsed.normalizedFilename, "Example.gb", flags)
            XCTAssertEqual(parsed.releaseKind, .standard, flags)
            XCTAssertEqual(parsed.confidence, .low, flags)
            XCTAssertEqual(parsed.unknownGroups, [], flags)
        }

        let parsed = FilenameMetadataParser.parse(filename: "Moon Garden (World) (v1.1) (Aftermarket) (Unl).gb")
        XCTAssertEqual(parsed.suggestedTitle, "Moon Garden")
        XCTAssertEqual(parsed.buildMetadata, BuildImportMetadata(region: "World", versionString: "1.1"))
        XCTAssertEqual(parsed.suggestedBuildName, "v1.1")
        XCTAssertEqual(parsed.normalizedFilename, "Moon Garden (World) (v1.1).gb")
        XCTAssertEqual(parsed.releaseKind, .development)
        XCTAssertEqual(parsed.confidence, .high)
        XCTAssertEqual(parsed.unknownGroups, [])
    }

    func testFirstNoIntroStatusWinsAndLaterStatusesAreRecognized() {
        let parsed = FilenameMetadataParser.parse(filename: "Pocket Critters (USA) (Beta 2) (Kiosk).gb")
        XCTAssertEqual(parsed.suggestedTitle, "Pocket Critters")
        XCTAssertEqual(parsed.buildMetadata, BuildImportMetadata(region: "USA", status: "Beta 2"))
        XCTAssertEqual(parsed.suggestedBuildName, "Beta 2")
        XCTAssertEqual(parsed.normalizedFilename, "Pocket Critters (USA) (Beta 2).gb")
        XCTAssertEqual(parsed.releaseKind, .development)
        XCTAssertEqual(parsed.unknownGroups, [])
    }

    func testPirateAndVirtualConsoleStayUnknownWithoutChangingReleaseKind() {
        for groups in [["Pirate"], ["Virtual Console"], ["Pirate", "Virtual Console"], ["pirate", "virtual console"]] {
            let flags = groups.map { "(\($0))" }.joined(separator: " ")
            let normalizedFlags = groups.map { "[\($0)]" }.joined(separator: " ")
            let parsed = FilenameMetadataParser.parse(filename: "Example \(flags).gb")
            XCTAssertEqual(parsed.suggestedTitle, "Example", flags)
            XCTAssertEqual(parsed.buildMetadata, BuildImportMetadata(), flags)
            XCTAssertEqual(parsed.suggestedBuildName, "Original", flags)
            XCTAssertEqual(parsed.normalizedFilename, "Example \(normalizedFlags).gb", flags)
            XCTAssertEqual(parsed.releaseKind, .standard, flags)
            XCTAssertEqual(parsed.confidence, .low, flags)
            XCTAssertEqual(parsed.unknownGroups, groups, flags)
        }
    }

    func testRecognizedTagsBecomeSeparateFieldsWithoutLosingOriginalGroups() {
        let parsed = FilenameMetadataParser.parse(filename: "Example (USA, Europe) (En,Fr,De) (Rev A) [v1.10.2] [Unknown].gbc")
        XCTAssertEqual(parsed.suggestedTitle, "Example")
        XCTAssertEqual(parsed.buildMetadata, BuildImportMetadata(region: "USA, Europe", language: "En, Fr, De", revision: "A", versionString: "1.10.2"))
        XCTAssertEqual(parsed.bracketGroups, ["v1.10.2", "Unknown"])
        XCTAssertEqual(parsed.unknownGroups, ["Unknown"])
        XCTAssertEqual(parsed.originalBaseName, "Example (USA, Europe) (En,Fr,De) (Rev A) [v1.10.2] [Unknown]")
        XCTAssertEqual(parsed.suggestedBuildName, "v1.10.2 · Rev A")
        XCTAssertEqual(parsed.normalizedFilename, "Example (USA, Europe) (En,Fr,De) (Rev A) (v1.10.2) [Unknown].gbc")
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
        XCTAssertEqual(parsed.normalizedFilename, "Pokemon Red [PureRed by Vortyne v4.7.0] [Beta].gb")
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
        XCTAssertEqual(parsed.normalizedFilename, "Pokemon Crystal [Crystal Clear by ShockSlayer v2.5.10] [T+Spa].gbc")
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
        XCTAssertEqual(parsed.normalizedFilename, "Base Game [Nueva v1.0] [T+Spa].gb")
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
            "Bubble Bobble Part 2 (USA, Europe) [Tearing fix & save patch by thisJUSTin816 v1.1].gb"
        )
    }

    func testAHackReleasedUnderItsOwnNamingKeepsThatNameAndReadsBackTheSame() {
        let filename = "Moon Garden (USA) [Night patch by Jane v0.3].gbc"
        let parsed = FilenameMetadataParser.parse(filename: filename)

        XCTAssertEqual(parsed.normalizedFilename, filename)
        XCTAssertEqual(FilenameMetadataParser.parse(filename: parsed.normalizedFilename).buildMetadata, parsed.buildMetadata)
    }

    func testTranslationsAsReleasedAreReadAndWrittenTheSameWay() {
        let released = FilenameMetadataParser.parse(filename: "Moon Garden (Japan) [T-En by Jane v1.0].gb")
        XCTAssertEqual(released.releaseKind, .romHack)
        XCTAssertEqual(released.buildMetadata.translation, "En")
        XCTAssertEqual(released.buildMetadata.author, "Jane")
        XCTAssertEqual(released.buildMetadata.versionString, "1.0")
        XCTAssertEqual(released.unknownGroups, [])
        XCTAssertEqual(released.normalizedFilename, "Moon Garden (Japan) [T+Eng1.0_Jane].gb")

        let goodTools = FilenameMetadataParser.parse(filename: "Moon Garden (Japan) [T+Eng1.03_Jane Doe].gb")
        XCTAssertEqual(goodTools.buildMetadata.translation, "Eng")
        XCTAssertEqual(goodTools.buildMetadata.author, "Jane Doe")
        XCTAssertEqual(goodTools.buildMetadata.versionString, "1.03")
        XCTAssertEqual(goodTools.unknownGroups, [])
        XCTAssertEqual(goodTools.normalizedFilename, "Moon Garden (Japan) [T+Eng1.03_Jane Doe].gb")
    }

    func testGoodToolsRegionsVersionsAndDumpFlagsAreReadAsNoIntroFields() {
        let parsed = FilenameMetadataParser.parse(filename: "Moon Garden (UE) (V1.1) (M3) [C][!].gbc")
        XCTAssertEqual(parsed.buildMetadata, BuildImportMetadata(region: "USA, Europe", versionString: "1.1"))
        XCTAssertEqual(parsed.unknownGroups, [])
        XCTAssertEqual(parsed.suggestedTitle, "Moon Garden")
        XCTAssertEqual(parsed.normalizedFilename, "Moon Garden (USA, Europe) (v1.1).gbc")

        for (code, region) in [("U", "USA"), ("J", "Japan"), ("E", "Europe"), ("JU", "Japan, USA"), ("JUE", "World"), ("W", "World"), ("G", "Germany")] {
            XCTAssertEqual(FilenameMetadataParser.parse(filename: "Moon Garden (\(code)).gb").buildMetadata.region, region, code)
        }
        for flags in ["[a1]", "[b1]", "[o2]", "[p1]", "[!p]", "[x]", "[S]"] {
            let copy = FilenameMetadataParser.parse(filename: "Moon Garden (U) \(flags).gb")
            XCTAssertEqual(copy.unknownGroups, [], flags)
            XCTAssertEqual(copy.releaseKind, .standard, flags)
        }
        for flags in ["[h1]", "[h1C]", "[hI]", "[hM04]", "[t1]", "[f2]"] {
            let modified = FilenameMetadataParser.parse(filename: "Moon Garden (U) \(flags).gb")
            XCTAssertEqual(modified.unknownGroups, [], flags)
            XCTAssertEqual(modified.releaseKind, .romHack, flags)
        }
    }

    func testAGoodToolsTranslationWithoutAVersionKeepsItsTranslator() {
        let parsed = FilenameMetadataParser.parse(filename: "Moon Garden (J) [T+Spa_Jane].gb")
        XCTAssertEqual(parsed.buildMetadata.translation, "Spa")
        XCTAssertEqual(parsed.buildMetadata.author, "Jane")
        XCTAssertEqual(parsed.normalizedFilename, "Moon Garden (Japan) [T+Spa_Jane].gb")
    }

    func testAHackTitleNeedsNoKeywordWhenItNamesItsAuthor() {
        let filename = "Moon Garden (USA) [Lunar Remix by Jane v2.1].gb"
        let parsed = FilenameMetadataParser.parse(filename: filename)

        XCTAssertEqual(parsed.releaseKind, .romHack)
        XCTAssertEqual(parsed.buildMetadata.hackTitle, "Lunar Remix")
        XCTAssertEqual(parsed.normalizedFilename, filename)
    }

    func testTitlesFollowNoIntro() {
        XCTAssertEqual(FilenameMetadataParser.noIntroTitle("The Moon Garden: Night Tales"), "Moon Garden, The - Night Tales")
        XCTAssertEqual(FilenameMetadataParser.noIntroTitle("A Moon Garden"), "Moon Garden, A")
        XCTAssertEqual(FilenameMetadataParser.noIntroTitle("Pokémon Moon"), "Pokemon Moon")
        XCTAssertEqual(FilenameMetadataParser.noIntroTitle("Moon Garden, The - A Night"), "Moon Garden, The - A Night")
        XCTAssertEqual(FilenameMetadataParser.noIntroTitle("Theatre"), "Theatre")
    }

    func testAHackWithoutItsOwnTitleIsNamedForItsAuthor() {
        let metadata = BuildImportMetadata(versionString: "1.3", baseTitle: "Moon Garden", hackTitle: "Moon Garden", author: "Jane")

        XCTAssertEqual(
            FilenameMetadataParser.canonicalFilename(fileExtension: "gb", title: "Moon Garden", metadata: metadata, unknownGroups: []),
            "Moon Garden [Hack by Jane v1.3].gb"
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

    func testADateStampBecomesTheVersionAndTheWordsAfterItTheVariant() {
        let classic = FilenameMetadataParser.parse(filename: "AeonMetalFighters_20261006_classic.gbc")
        XCTAssertEqual(classic.suggestedTitle, "Aeon Metal Fighters")
        XCTAssertEqual(classic.buildMetadata.versionString, "2026.10.06")
        XCTAssertEqual(classic.buildMetadata.status, "classic")
        XCTAssertEqual(classic.suggestedBuildName, "2026-10-06 · classic")

        let plain = FilenameMetadataParser.parse(filename: "AeonMetalFighters_20261004.gbc")
        XCTAssertEqual(plain.suggestedBuildName, "2026-10-04")
        XCTAssertLessThan(plain.buildMetadata.versionSortKey!, classic.buildMetadata.versionSortKey!)

        XCTAssertEqual(FilenameMetadataParser.parse(filename: "Game Jam Entry 2026-10-04.gb").suggestedBuildName, "2026-10-04")
    }

    func testAVersionWordMidNameBecomesTheVersionAndTheWordsAfterItTheVariant() {
        let hyphenated = FilenameMetadataParser.parse(filename: "Serve-Sisters-Coop-v5-Stability.gbc")
        XCTAssertEqual(hyphenated.suggestedTitle, "Serve Sisters Coop")
        XCTAssertEqual(hyphenated.buildMetadata.versionString, "5")
        XCTAssertEqual(hyphenated.buildMetadata.status, "Stability")
        XCTAssertEqual(hyphenated.suggestedBuildName, "v5 · Stability")
        XCTAssertEqual(hyphenated.releaseKind, .development)

        let underscored = FilenameMetadataParser.parse(filename: "Match_Land_v1.2_beta.gb")
        XCTAssertEqual(underscored.suggestedTitle, "Match Land")
        XCTAssertEqual(underscored.buildMetadata.versionString, "1.2")
        XCTAssertEqual(underscored.buildMetadata.status, "Beta")

        // With spaces in the name, hyphens belong to the title.
        let spaced = FilenameMetadataParser.parse(filename: "R-Type DX v2 demo.gb")
        XCTAssertEqual(spaced.suggestedTitle, "R-Type DX")
        XCTAssertEqual(spaced.buildMetadata.versionString, "2")
        XCTAssertEqual(spaced.buildMetadata.status, "Demo")

        // The shared-file UI tests' ROM.
        XCTAssertEqual(FilenameMetadataParser.parse(filename: "gbdk450-rev-v1.0.gb").suggestedBuildName, "v1.0")

        // A dotted version needs no "v"; an all-lowercase name is capitalized.
        let bare = FilenameMetadataParser.parse(filename: "match-land-live-0.3.0+live1.gb")
        XCTAssertEqual(bare.suggestedTitle, "Match Land Live")
        XCTAssertEqual(bare.buildMetadata.versionString, "0.3.0+live1")
        XCTAssertNil(bare.buildMetadata.status)
        XCTAssertEqual(bare.suggestedBuildName, "v0.3.0+live1")

        for filename in ["Pac-Man.gb", "Serve-Sisters-Coop.gbc", "v2.gb", "Movie-vs-Book.gb", "Mega-Man-2.gb", "1.5.gb"] {
            XCTAssertNil(FilenameMetadataParser.parse(filename: filename).buildMetadata.versionString, filename)
        }
        XCTAssertEqual(FilenameMetadataParser.parse(filename: "Pac-Man.gb").suggestedTitle, "Pac-Man")
    }

    func testANameWithoutSpacesIsSpacedOut() {
        let expected = [
            "MoonGarden.gb": "Moon Garden",
            "GBStudioDemo.gbc": "GB Studio Demo",
            "moon_garden_dx.gb": "Moon Garden DX",
            "Moon_Garden.gb": "Moon Garden",
            "garden.gb": "Garden",
            "MoonGarden_v2.gb": "Moon Garden",
            "iPocket.gb": "iPocket",
            "Pac-Man.gb": "Pac-Man",
            "TETRIS.gb": "TETRIS",
            "Moon Garden.gb": "Moon Garden",
            "Kid Icarus.gb": "Kid Icarus",
        ]
        for (filename, title) in expected {
            XCTAssertEqual(FilenameMetadataParser.parse(filename: filename).suggestedTitle, title, filename)
        }
        XCTAssertEqual(FilenameMetadataParser.parse(filename: "MoonGarden.gb").normalizedFilename, "Moon Garden.gb")
    }

    func testNumbersThatAreNotDatesStayInTheTitle() {
        for filename in ["20261006.gb", "Tetris 19891399.gb", "Score_12345678.gb"] {
            XCTAssertNil(FilenameMetadataParser.parse(filename: filename).buildMetadata.versionString, filename)
        }
    }
}

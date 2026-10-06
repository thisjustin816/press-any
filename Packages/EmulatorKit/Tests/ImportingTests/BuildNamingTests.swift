import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import Importing
import XCTest

final class BuildNamingTests: XCTestCase {
    private let locale = Locale(identifier: "en_US")
    private let utc = TimeZone(identifier: "UTC")!
    /// 2026-10-06 12:00 UTC.
    private let october6 = Date(timeIntervalSince1970: 1_791_288_000)

    func testAFreeNameIsKept() {
        XCTAssertEqual(name("Original", existing: ["Rev 1"]), "Original")
    }

    func testADuplicateNameGainsTheDayItWasAdded() {
        XCTAssertEqual(name("Original", existing: ["original"]), "Original · Oct 6")
    }

    func testTheTimeAndThenANumberSeparateBuildsAddedTheSameDay() {
        let timed = name("Original", existing: ["Original", "Original · Oct 6"])
        // The locale words the date and time; both are there.
        XCTAssertTrue(timed.hasPrefix("Original · Oct 6") && timed.contains("12:00"), timed)
        XCTAssertEqual(name("Original", existing: ["Original", "Original · Oct 6", timed]), "\(timed) (2)")
    }

    func testSuggestionsCoverEscapedFilenameAndDuplicateNamesOnly() throws {
        let games = InMemoryGameRepository()
        let builds = InMemoryBuildRepository()
        let assets = InMemoryAssetRepository()
        let game = Game(id: UUID(), primaryTitle: "Match Land", systemFamily: "gb", createdAt: october6, modifiedAt: october6)
        try games.insertGame(game)

        func add(_ name: String, filename: String?, daysAfter days: Double) throws -> Build {
            let asset = ManagedAsset(
                id: UUID(), kind: .sourceImage, storageClass: .source, contentSHA256: UUID().uuidString,
                byteLength: 1, relativePath: UUID().uuidString, originalFilename: filename, createdAt: october6
            )
            try assets.insertAsset(asset)
            let added = october6.addingTimeInterval(days * 86_400)
            let build = Build(
                id: UUID(), gameID: game.id, system: .gameBoy, displayName: name, imageAssetID: asset.id,
                imageSHA256: asset.contentSHA256, sourceKind: .importedImage, createdAt: added, modifiedAt: added
            )
            try builds.insertBuild(build)
            return build
        }

        let escaped = try add(
            "Match%20Land%20%28World%29%20%28Rev%200.2.0%29",
            filename: "Match%20Land%20%28World%29%20%28Rev%200.2.0%29.gb",
            daysAfter: 0
        )
        _ = try add("Original", filename: "match-land.gb", daysAfter: 1)
        let duplicate = try add("Original", filename: "match_land_final.gb", daysAfter: 2)
        _ = try add("My favorite", filename: "match-land-v2.gb", daysAfter: 3)

        let suggestions = try BuildNameSuggester(games: games, builds: builds, assets: assets)
            .suggestions(locale: locale, timeZone: utc)

        XCTAssertEqual(suggestions.map(\.buildID), [escaped.id, duplicate.id])
        // A dotted "Rev" is the homebrew version.
        XCTAssertEqual(suggestions.map(\.suggestedName), ["v0.2.0", "Original · Oct 8"])
        XCTAssertEqual(suggestions.first?.currentName, escaped.displayName)
    }

    private func name(_ name: String, existing: [String]) -> String {
        BuildNaming.distinctName(name, existing: existing, addedAt: october6, locale: locale, timeZone: utc)
    }
}

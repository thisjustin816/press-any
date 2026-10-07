import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import GameIdentity
import XCTest

final class GameTitleSuggesterTests: XCTestCase {
    func testRegionalSuggestionsIncludeProtectedTitlesAndExcludeHomebrewAndBestTitles() throws {
        let games = InMemoryGameRepository()
        let builds = InMemoryBuildRepository()
        let usa = KnownDump(name: "Crystal (USA)", system: .gameBoy, title: "Crystal", region: "USA", languages: "En",
            files: [.init(sha1: "usa", size: 1)])
        let japan = KnownDump(name: "Pocket Monsters Crystal (Japan)", system: .gameBoy, title: "Pocket Monsters Crystal",
            region: "Japan", languages: "Ja", parent: usa.name, files: [.init(sha1: "japan", size: 1)])
        let index = try KnownDumpIndex(catalog: .init(source: "synthetic", generated: "", systems: [], games: [usa, japan]))

        func addGame(_ title: String, releases: [KnownDump]) throws -> Game {
            let game = Game(id: UUID(), primaryTitle: title, systemFamily: "gameboy", hasPlayerTitle: true,
                createdAt: .now, modifiedAt: .now)
            try games.insertGame(game)
            for dump in releases {
                try builds.insertBuild(Build(id: UUID(), gameID: game.id, system: dump.system, displayName: "Retail",
                    imageAssetID: UUID(), imageSHA256: UUID().uuidString, imageSHA1: dump.files[0].sha1,
                    sourceKind: .importedImage, region: dump.region, language: dump.languages, createdAt: .now, modifiedAt: .now))
            }
            return game
        }

        let regional = try addGame(japan.title, releases: [japan, usa])
        var olderBuild = try XCTUnwrap(builds.fetchBuilds(gameID: regional.id).first { $0.imageSHA1 == "usa" })
        olderBuild.region = nil
        olderBuild.language = nil
        try builds.updateBuildMetadata(olderBuild)
        let homebrew = try addGame("Homebrew", releases: [])
        try builds.insertBuild(Build(id: UUID(), gameID: homebrew.id, system: .gameBoy, displayName: "v1.0",
            imageAssetID: UUID(), imageSHA256: "homebrew", sourceKind: .importedImage,
            baseGameReference: index.reference(to: usa), createdAt: .now, modifiedAt: .now))
        let alreadyBest = try addGame(usa.title, releases: [japan, usa])
        let before = try games.fetchGames()
        let suggestions = try GameTitleSuggester(games: games, builds: builds, index: index, preference: ReleasePreference()).suggestions()
        XCTAssertEqual(suggestions.map(\.gameID), [regional.id])
        XCTAssertEqual(suggestions.first?.currentTitle, japan.title)
        XCTAssertEqual(suggestions.first?.proposedTitle, usa.title)
        XCTAssertEqual(suggestions.first?.region, "USA")
        XCTAssertEqual(try games.fetchGames(), before, "opening suggestions writes nothing")

        let reordered = try GameTitleSuggester(games: games, builds: builds, index: index,
            preference: ReleasePreference(regions: ["Japan", "USA", "Europe"])).suggestions()
        XCTAssertEqual(reordered.map(\.gameID), [alreadyBest.id])
        XCTAssertEqual(reordered.first?.proposedTitle, japan.title)
    }
}

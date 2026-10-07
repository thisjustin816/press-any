import AssetStorage
import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import GameIdentity
import XCTest
@testable import Importing

final class IdentityFollowUpTests: XCTestCase {
    func testAliasesMatchWholeTitlesWithoutAttachingAmbiguousGames() {
        var game = Game(id: UUID(), primaryTitle: "Pokémon Crystal", systemFamily: "gameboy", createdAt: .now, modifiedAt: .now)
        game.aliases = ["Pocket Monsters Crystal"]
        let naming = FilenameMetadataParser.parse(filename: "Pocket Monsters Crystal.gb")
        XCTAssertEqual(GameMatcher.matchingGameID(for: naming, headerTitle: "", in: [game]), game.id)
        let other = Game(id: UUID(), primaryTitle: game.primaryTitle, systemFamily: "gameboy", aliases: game.aliases, createdAt: .now, modifiedAt: .now)
        XCTAssertNil(GameMatcher.matchingGameID(for: naming, headerTitle: "", in: [game, other]))
        XCTAssertNil(GameMatcher.matchingGameID(for: FilenameMetadataParser.parse(filename: "Pocket Monsters.gb"), headerTitle: "", in: [game]))
    }

    func testRegionAndLanguageRankingUsesWholeTagsAndStableTies() {
        let order = ReleasePreference()
        XCTAssertTrue(order.prefers(region: "USA, Europe", language: "En", overRegion: "Japan", overLanguage: "Ja"))
        XCTAssertFalse(order.prefers(region: "Japan", language: "Ja", overRegion: "USA", overLanguage: "En"))
        XCTAssertFalse(order.prefers(region: "USA", language: "En", overRegion: "USA", overLanguage: "En"))
        XCTAssertTrue(ReleasePreference(regions: ["Japan", "USA", "Europe"], languages: ["Ja", "En"]).prefers(region: "Japan", language: "Ja", overRegion: "USA", overLanguage: "En"))
        XCTAssertTrue(order.prefers(region: "Europe", language: "En, Fr", overRegion: "Europe", overLanguage: "De"))
        XCTAssertFalse(order.prefers(region: "US", language: nil, overRegion: "Europe", overLanguage: nil))
    }
}

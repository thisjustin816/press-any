import EmulatorDomain
import Foundation
import XCTest

final class GameIdentityFieldsTests: XCTestCase {
    func testAliasesDeduplicateAndSearchAcrossCaseAndAccents() {
        var game = Game(id: UUID(), primaryTitle: "Pokémon Crystal", systemFamily: "gameboy", createdAt: .now, modifiedAt: .now)
        game.addAliases([" Pocket Monsters Crystal ", "pocket monsters crystal", "", "Pokémon Crystal"])
        XCTAssertEqual(game.aliases, ["Pocket Monsters Crystal", "Pokémon Crystal"])
        XCTAssertTrue(game.matchesSearch("pocket monsters"))
        XCTAssertTrue(game.matchesSearch("pokemon"))
        XCTAssertFalse(game.matchesSearch("Gold"))
    }

    func testOldGameEncodingKeepsItsTitleAndCurrentEncodingRoundTrips() throws {
        var game = Game(id: UUID(), primaryTitle: "Player's Game", systemFamily: "gameboy", createdAt: .now, modifiedAt: .now)
        game.addAliases(["Regional Game"])
        let encoded = try JSONEncoder().encode(game)
        XCTAssertEqual(try JSONDecoder().decode(Game.self, from: encoded), game)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "aliases")
        legacy.removeValue(forKey: "hasPlayerTitle")
        let decoded = try JSONDecoder().decode(Game.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(decoded.primaryTitle, game.primaryTitle)
        XCTAssertTrue(decoded.hasPlayerTitle)
        XCTAssertTrue(decoded.aliases.isEmpty)
    }
}

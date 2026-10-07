import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import GameIdentity
import XCTest

final class FamilyGameSuggesterTests: XCTestCase {
    func testFamiliesStayWithinTheirSystemAndUnknownLineageIsNotImageEvidence() throws {
        let games = InMemoryGameRepository()
        let builds = InMemoryBuildRepository()
        let root = "Shared Title (USA)"
        let gb = KnownDump(name: root, system: .gameBoy, title: "Shared Title", files: [.init(sha1: "gb", size: 1)])
        let gbc = KnownDump(name: root, system: .gameBoyColor, title: "Shared Title", files: [.init(sha1: "gbc", size: 1)])
        let index = try KnownDumpIndex(catalog: .init(source: "synthetic", generated: "", systems: [], games: [gb, gbc]))
        var gbIDs = Set<UUID>()
        for (number, system, sha1) in [(0, GameSystem.gameBoy, "gb"), (1, .gameBoy, "gb"), (2, .gameBoyColor, "gbc")] {
            let game = Game(id: UUID(), primaryTitle: "Game \(number)", systemFamily: "gameboy", createdAt: .now, modifiedAt: .now)
            try games.insertGame(game)
            try builds.insertBuild(Build(id: UUID(), gameID: game.id, system: system, displayName: "Original", imageAssetID: UUID(),
                imageSHA256: "image\(number)", imageSHA1: sha1, sourceKind: .importedImage, createdAt: .now, modifiedAt: .now))
            if system == .gameBoy { gbIDs.insert(game.id) }
        }
        let unknown = Game(id: UUID(), primaryTitle: "Unknown", systemFamily: "gameboy", createdAt: .now, modifiedAt: .now)
        try games.insertGame(unknown)
        try builds.insertBuild(Build(id: UUID(), gameID: unknown.id, system: .gameBoy, displayName: "Hack", imageAssetID: UUID(),
            imageSHA256: "unknown", sourceKind: .importedImage, baseGameReference: index.reference(to: gb), createdAt: .now, modifiedAt: .now))
        let groups = try FamilyGameSuggester(games: games, builds: builds, index: index).suggestions()
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].system, .gameBoy)
        XCTAssertEqual(Set(groups[0].games.map(\.id)), gbIDs)
        XCTAssertEqual(try games.fetchGames().count, 4)
    }
}

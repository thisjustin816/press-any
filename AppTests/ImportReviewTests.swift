import EmulatorDomain
import Foundation
import Importing
import UIKit
import XCTest
@testable import PressAny

@MainActor
final class ImportReviewTests: XCTestCase {
    func testReviewEditsSurviveReopeningTheLibrary() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try AppContainer(rootURL: root)
        let file = root.appendingPathComponent("Example (Europe) (En,Fr) (Rev A) [v1.10].gb")
        // A generated header is enough for import; no core execution is needed.
        try Data(repeating: 0, count: 0x8000).write(to: file)
        let coordinator = ImportCoordinator(analyzer: container.importAnalyzer, committer: container.importCommitter, assetStore: container.fileStore)
        let review = ImportReviewViewModel(analysis: try coordinator.analyzeROM(at: file), games: [], coordinator: coordinator)
        XCTAssertEqual(review.gameTitle, "Example")
        XCTAssertEqual(review.region, "Europe")
        XCTAssertEqual(review.language, "En, Fr")
        XCTAssertEqual(review.revision, "A")
        XCTAssertEqual(review.version, "1.10")
        XCTAssertEqual(review.normalizedFilename, "Example (Europe) (En, Fr) (Rev A) [v1.10].gb")
        review.region = " Japan "
        review.language = " "
        review.revision = ""
        review.version = "2.0"
        XCTAssertEqual(review.normalizedFilename, "Example (Japan) [v2.0].gb")
        let result = try review.commit()
        let reopened = try AppContainer(rootURL: root)
        let build = try XCTUnwrap(reopened.repositories.builds.fetchBuild(id: result.build.id))
        XCTAssertEqual(build.region, "Japan")
        XCTAssertNil(build.language)
        XCTAssertNil(build.revision)
        XCTAssertEqual(build.versionString, "2.0")
        XCTAssertEqual(build.versionSortKey, BuildImportMetadata(versionString: "2.0").versionSortKey)
    }

    func testArtworkChosenInReviewIsSetOnTheNewGame() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try AppContainer(rootURL: root)
        let file = root.appendingPathComponent("Artwork Example.gb")
        try Data(repeating: 0, count: 0x8000).write(to: file)
        let coordinator = ImportCoordinator(analyzer: container.importAnalyzer, committer: container.importCommitter, assetStore: container.fileStore)
        let review = ImportReviewViewModel(
            analysis: try coordinator.analyzeROM(at: file),
            games: [],
            coordinator: coordinator,
            setArtwork: { _ = try container.gameArtwork.set(gameID: $0, imageData: $1, fileExtension: $2) }
        )
        XCTAssertTrue(review.canChooseArtwork)

        review.chooseArtwork(Data("not an image".utf8), fileExtension: "png")
        XCTAssertNil(review.artwork, "an unreadable image is refused in review")
        XCTAssertNotNil(review.errorMessage)

        let png = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { context in
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        review.chooseArtwork(png, fileExtension: "png")
        XCTAssertNotNil(review.artwork)
        XCTAssertNil(review.errorMessage)

        let result = try review.commit()
        XCTAssertNil(review.artworkFailure)
        let game = try XCTUnwrap(container.repositories.games.fetchGame(id: result.build.gameID))
        XCTAssertNotNil(game.artworkAssetID)

        // The same ROM again changes nothing, so review doesn't offer artwork for it.
        let duplicate = ImportReviewViewModel(
            analysis: try coordinator.analyzeROM(at: file),
            games: [game],
            coordinator: coordinator,
            setArtwork: { _ = try container.gameArtwork.set(gameID: $0, imageData: $1, fileExtension: $2) }
        )
        XCTAssertFalse(duplicate.canChooseArtwork)
    }

    func testDevelopmentAndHackNamesSuggestDifferentBaseRolesAndBothPreferTheNewBuild() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try AppContainer(rootURL: root)
        let coordinator = ImportCoordinator(
            analyzer: container.importAnalyzer,
            committer: container.importCommitter,
            assetStore: container.fileStore
        )

        var developmentBytes = Data(repeating: 0, count: 0x8000)
        developmentBytes[0x200] = 1
        let developmentFile = root.appendingPathComponent("Example v2.0.gb")
        try developmentBytes.write(to: developmentFile)
        let development = ImportReviewViewModel(
            analysis: try coordinator.analyzeROM(at: developmentFile),
            games: [],
            coordinator: coordinator
        )
        XCTAssertEqual(development.buildDisplayName, "v2.0")
        XCTAssertTrue(development.markAsBase)
        XCTAssertTrue(development.markAsPreferred)

        let original = try development.commit()
        var hackBytes = developmentBytes
        hackBytes[0x201] = 2
        let hackFile = root.appendingPathComponent("Example - Better [Hack] [by Jane] [v1.3] [Beta].gb")
        try hackBytes.write(to: hackFile)
        let hack = ImportReviewViewModel(
            analysis: try container.importAnalyzer.analyzeROM(at: hackFile, targetGameID: original.game.id),
            games: [original.game],
            coordinator: coordinator
        )

        XCTAssertEqual(hack.destination, .existing(original.game.id))
        XCTAssertEqual(hack.gameTitle, "Better")
        XCTAssertEqual(hack.buildDisplayName, "v1.3 · Beta")
        XCTAssertFalse(hack.markAsBase)
        XCTAssertTrue(hack.markAsPreferred)
        XCTAssertEqual(hack.baseTitle, "Example")
        XCTAssertEqual(hack.hackTitle, "Better")
        XCTAssertEqual(hack.author, "Jane")
        XCTAssertEqual(hack.status, "Beta")

        let result = try hack.commit()
        XCTAssertFalse(result.build.isBase)
        XCTAssertEqual(result.game.preferredBuildID, result.build.id)
    }

    func testANewHomebrewBuildJoinsTheMatchingGameAsBaseAndPreferred() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try AppContainer(rootURL: root)
        let coordinator = ImportCoordinator(
            analyzer: container.importAnalyzer,
            committer: container.importCommitter,
            assetStore: container.fileStore
        )

        var firstBytes = Data(repeating: 0, count: 0x8000)
        firstBytes[0x200] = 1
        let firstFile = root.appendingPathComponent("match-land.gb")
        try firstBytes.write(to: firstFile)
        let first = try ImportReviewViewModel(
            analysis: coordinator.analyzeROM(at: firstFile),
            games: [],
            coordinator: coordinator
        ).commit()

        var updateBytes = firstBytes
        updateBytes[0x201] = 2
        let updateFile = root.appendingPathComponent("Match Land (World) (Rev 0.2.0).gb")
        try updateBytes.write(to: updateFile)
        let update = ImportReviewViewModel(
            analysis: try coordinator.analyzeROM(at: updateFile),
            games: [first.game],
            coordinator: coordinator
        )

        XCTAssertEqual(update.destination, .existing(first.game.id))
        XCTAssertTrue(update.markAsBase)
        XCTAssertTrue(update.markAsPreferred)
        let result = try update.commit()
        XCTAssertTrue(result.build.isBase)
        XCTAssertEqual(try container.repositories.builds.fetchBuild(id: first.build.id)?.isBase, false)
    }

    func testRolesThePlayerSetSurviveChangingTheDestination() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try AppContainer(rootURL: root)
        let coordinator = ImportCoordinator(
            analyzer: container.importAnalyzer,
            committer: container.importCommitter,
            assetStore: container.fileStore
        )
        let file = root.appendingPathComponent("Example v1.0.gb")
        try Data(repeating: 0, count: 0x8000).write(to: file)
        let review = ImportReviewViewModel(analysis: try coordinator.analyzeROM(at: file), games: [], coordinator: coordinator)
        XCTAssertTrue(review.markAsBase)
        review.markAsBase = false
        review.destination = .existing(UUID())
        review.destinationChanged()
        review.destination = .newGame
        review.destinationChanged()
        XCTAssertFalse(review.markAsBase, "the player turned Base off")
        XCTAssertTrue(review.markAsPreferred)
    }

    func testAnExistingBaseIsReplacedOnlyByANewerHomebrewRelease() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try AppContainer(rootURL: root)
        let coordinator = ImportCoordinator(
            analyzer: container.importAnalyzer,
            committer: container.importCommitter,
            assetStore: container.fileStore
        )
        var byte: UInt8 = 0
        func review(_ filename: String, games: [Game]) throws -> ImportReviewViewModel {
            byte += 1
            var bytes = Data(repeating: 0, count: 0x8000)
            bytes[0x200] = byte
            let file = root.appendingPathComponent(filename)
            try bytes.write(to: file)
            return ImportReviewViewModel(
                analysis: try coordinator.analyzeROM(at: file),
                games: games,
                coordinator: coordinator,
                existingBuilds: { container.builds(in: $0) }
            )
        }

        let retail = try review("Example (USA).gb", games: []).commit()
        XCTAssertTrue(retail.build.isBase, "a new Game's first Build is its Base")
        for filename in ["Example (USA) (Rev 1).gb", "Example (USA) (Beta).gb"] {
            let other = try review(filename, games: [retail.game])
            XCTAssertEqual(other.destination, .existing(retail.game.id))
            XCTAssertFalse(other.markAsBase, "\(filename) leaves the clean Base alone")
            XCTAssertTrue(other.markAsPreferred)
        }

        let homebrew = try review("Homebrew v1.2.gb", games: []).commit()
        XCTAssertFalse(try review("Homebrew v1.1.gb", games: [homebrew.game]).markAsBase, "an older release")
        XCTAssertTrue(try review("Homebrew v1.10.gb", games: [homebrew.game]).markAsBase, "a newer release")
        XCTAssertTrue(try review("Homebrew 2026-10-06.gb", games: [homebrew.game]).markAsBase, "a dated release sorts after v1")
    }
}

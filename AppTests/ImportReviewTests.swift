import EmulatorApplication
import EmulatorDomain
import Foundation
import GameIdentity
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
        XCTAssertEqual(review.normalizedFilename, "Example (Europe) (En,Fr) (Rev A) (v1.10).gb")
        review.region = " Japan "
        review.language = " "
        review.revision = ""
        review.version = "2.0"
        XCTAssertEqual(review.normalizedFilename, "Example (Japan) (v2.0).gb")
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
        var artworkLookups = 0
        let review = ImportReviewViewModel(
            analysis: try coordinator.analyzeROM(at: file),
            games: [],
            coordinator: coordinator,
            setArtwork: { _ = try container.gameArtwork.set(gameID: $0, imageData: $1, fileExtension: $2) },
            fetchArtwork: { _ in artworkLookups += 1 }
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
        XCTAssertEqual(artworkLookups, 0, "a manual choice skips automatic lookup")

        // The same ROM again changes nothing, so review doesn't offer artwork for it.
        let duplicate = ImportReviewViewModel(
            analysis: try coordinator.analyzeROM(at: file),
            games: [game],
            coordinator: coordinator,
            setArtwork: { _ = try container.gameArtwork.set(gameID: $0, imageData: $1, fileExtension: $2) },
            fetchArtwork: { _ in artworkLookups += 1 }
        )
        XCTAssertFalse(duplicate.canChooseArtwork)
        _ = try duplicate.commit()
        XCTAssertEqual(artworkLookups, 0, "an exact duplicate skips automatic lookup")
    }

    func testImportWithoutChosenArtworkStartsALookupAfterCommit() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try AppContainer(rootURL: root)
        let file = root.appendingPathComponent("Example.gb")
        try Data(repeating: 0, count: 0x8000).write(to: file)
        let coordinator = ImportCoordinator(analyzer: container.importAnalyzer, committer: container.importCommitter, assetStore: container.fileStore)
        var lookedUp: [UUID] = []
        let review = ImportReviewViewModel(analysis: try coordinator.analyzeROM(at: file), games: [], coordinator: coordinator,
            fetchArtwork: { build in
                XCTAssertNotNil(try? container.repositories.builds.fetchBuild(id: build.id))
                lookedUp.append(build.id)
            })
        let result = try review.commit()
        XCTAssertEqual(lookedUp, [result.build.id])
    }

    func testFailedImportDoesNotStartArtworkLookup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try AppContainer(rootURL: root)
        let file = root.appendingPathComponent("Example.gb")
        try Data(repeating: 0, count: 0x8000).write(to: file)
        let coordinator = ImportCoordinator(analyzer: container.importAnalyzer, committer: container.importCommitter, assetStore: container.fileStore)
        let review = ImportReviewViewModel(analysis: try coordinator.analyzeROM(at: file), games: [], coordinator: coordinator,
            fetchArtwork: { _ in XCTFail("A failed import must not request artwork") })
        review.cancel()
        XCTAssertThrowsError(try review.commit(), "the staged ROM has been discarded")
        XCTAssertNotNil(review.errorMessage)
    }

    func testASecondImportedBuildCanFindArtworkWhileTheFirstLookupIsPending() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let index = try KnownDumpIndex.bundled()
        let dumps = Array(index.catalog.games.filter { $0.system == .gameBoy && $0.files.contains { !$0.bad } }.prefix(2))
        XCTAssertEqual(dumps.count, 2)
        let firstRequest = expectation(description: "First lookup starts")
        let secondRequest = expectation(description: "Second lookup starts before the first completes")
        let provider = PendingArtworkProvider { lookup in
            if lookup.releaseNames.first == dumps[0].name { firstRequest.fulfill() }
            if lookup.releaseNames.first == dumps[1].name { secondRequest.fulfill() }
        }
        let container = try AppContainer(rootURL: root, artworkProvider: provider)
        var game = Game(id: UUID(), primaryTitle: "Example", systemFamily: "gameboy", createdAt: .distantPast, modifiedAt: .distantPast)
        try container.repositories.games.insertGame(game)
        func makeBuild(_ dump: KnownDump, marker: UInt8) throws -> Build {
            let hash = container.fileStore.hashData(Data([marker]))
            let asset = ManagedAsset(id: UUID(), kind: .sourceImage, storageClass: .source,
                contentSHA256: hash, byteLength: 1, relativePath: "Source/\(hash).gb", createdAt: .distantPast)
            try container.repositories.assets.insertAsset(asset)
            let build = Build(id: UUID(), gameID: game.id, system: .gameBoy, displayName: dump.name,
                imageAssetID: asset.id, imageSHA256: hash, imageSHA1: dump.files.first { !$0.bad }?.sha1,
                sourceKind: .importedImage, createdAt: .distantPast, modifiedAt: .distantPast)
            try container.repositories.builds.insertBuild(build)
            return build
        }
        let first = try makeBuild(dumps[0], marker: 1)
        let second = try makeBuild(dumps[1], marker: 2)
        game.preferredBuildID = first.id
        try container.repositories.games.updateGame(game)
        container.fetchArtworkAfterImport(first)
        await fulfillment(of: [firstRequest], timeout: 2)
        game.preferredBuildID = second.id
        try container.repositories.games.updateGame(game)
        container.fetchArtworkAfterImport(second)
        await fulfillment(of: [secondRequest], timeout: 2)

        let stored = expectation(description: "Current Preferred Build's artwork is stored")
        let games = container.repositories.games
        let gameID = game.id
        let observer = NotificationCenter.default.addObserver(forName: .libraryDidChange, object: nil, queue: nil) { _ in
            if (try? games.fetchGame(id: gameID))?.artworkAssetID != nil { stored.fulfill() }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        let png = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { context in
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        await provider.finish(with: ProvidedArtwork(data: png, fileExtension: "png", provenance: .init(provider: "test",
            sourceURL: URL(string: "https://example.com/art.png")!, fetchedAt: .distantPast, rights: "Synthetic test data")))
        await fulfillment(of: [stored], timeout: 2)
        XCTAssertNotNil(try games.fetchGame(id: gameID)?.artworkAssetID)
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
        XCTAssertEqual(hack.buildDisplayName, "Better v1.3 · Beta", "the Game keeps its title, so the Build carries the hack's")
        XCTAssertFalse(hack.markAsBase)
        XCTAssertTrue(hack.markAsPreferred)
        XCTAssertEqual(hack.baseTitle, "Example")
        XCTAssertEqual(hack.hackTitle, "Better")
        XCTAssertEqual(hack.author, "Jane")
        XCTAssertEqual(hack.status, "Beta")
        // "Better" doesn't continue Example's title, so it names the Build and leaves the Game alone.
        XCTAssertNil(hack.offeredGameTitle)

        let result = try hack.commit()
        XCTAssertFalse(result.build.isBase)
        XCTAssertEqual(result.game.preferredBuildID, result.build.id)
        XCTAssertEqual(result.game.primaryTitle, "Example")
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

    func testANoIntroBaseStaysAndAHomebrewBaseMovesToTheNewestBuild() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try AppContainer(rootURL: root)
        var byte: UInt8 = 0
        func image() -> Data {
            byte += 1
            var bytes = Data(repeating: 0, count: 0x8000)
            bytes[0x200] = byte
            return bytes
        }
        let retailImages = [image(), image()]
        let dumps = zip(["Example (USA)", "Example (USA) (Rev 1)"], retailImages).map { name, bytes in
            KnownDump(name: name, system: .gameBoy, title: "Example", region: "USA", languages: "En",
                parent: name == "Example (USA)" ? nil : "Example (USA)",
                files: [KnownDumpFile(sha1: SHA1Digest.data(bytes), size: Int64(bytes.count))])
        }
        let index = try KnownDumpIndex(catalog: KnownDumpCatalog(source: "synthetic", generated: "", systems: [], games: dumps))
        let coordinator = ImportCoordinator(
            analyzer: ROMImportAnalyzer(builds: container.repositories.builds, games: container.repositories.games,
                fingerprints: container.repositories.fingerprints,
                toolchainReports: container.repositories.toolchainReports,
                assetStore: container.fileStore, knownDumps: index),
            committer: container.importCommitter,
            assetStore: container.fileStore
        )
        func review(_ filename: String, _ bytes: Data, games: [Game]) throws -> ImportReviewViewModel {
            let file = root.appendingPathComponent(filename)
            try bytes.write(to: file)
            return ImportReviewViewModel(
                analysis: try coordinator.analyzeROM(at: file),
                games: games,
                coordinator: coordinator,
                existingBuilds: { container.builds(in: $0) },
                knownDumps: index
            )
        }

        let retail = try review("Example (USA).gb", retailImages[0], games: []).commit()
        XCTAssertTrue(retail.build.isBase, "a new Game's first Build is its Base")
        let revision = try review("Example (USA) (Rev 1).gb", retailImages[1], games: [retail.game])
        XCTAssertEqual(revision.destination, .existing(retail.game.id))
        XCTAssertEqual(revision.normalizedFilename, "Example (USA) (Rev 1) [!].gb", "the name Export ROM gives it")
        XCTAssertFalse(revision.markAsBase, "a No-Intro revision leaves the clean Base alone")
        let unknown = try review("Example v9.gb", image(), games: [retail.game])
        unknown.destination = .existing(retail.game.id)
        unknown.destinationChanged()
        XCTAssertFalse(unknown.markAsBase, "an unknown file doesn't replace a No-Intro Base")

        let homebrew = try review("Homebrew v1.2.gb", image(), games: []).commit()
        let games = [retail.game, homebrew.game]
        XCTAssertFalse(try review("Homebrew v1.1.gb", image(), games: games).markAsBase, "an older release")
        XCTAssertTrue(try review("Homebrew v1.10.gb", image(), games: games).markAsBase, "a newer release")
        XCTAssertTrue(try review("Homebrew 2026-10-06.gb", image(), games: games).markAsBase, "a dated release sorts after v1")
        XCTAssertTrue(try review("Homebrew (Beta).gb", image(), games: games).markAsBase, "an unversioned build is the newest")
    }
}

private actor PendingArtworkProvider: ArtworkProvider {
    private let onRequest: @Sendable (ArtworkLookup) -> Void
    private var pending: [CheckedContinuation<ProvidedArtwork?, any Error>] = []

    init(onRequest: @escaping @Sendable (ArtworkLookup) -> Void) { self.onRequest = onRequest }

    func artwork(for lookup: ArtworkLookup) async throws -> ProvidedArtwork? {
        try await withCheckedThrowingContinuation { continuation in
            pending.append(continuation)
            onRequest(lookup)
        }
    }

    func finish(with artwork: ProvidedArtwork) {
        let continuations = pending
        pending.removeAll()
        for continuation in continuations { continuation.resume(returning: artwork) }
    }
}

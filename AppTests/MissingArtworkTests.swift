import EmulatorApplication
import EmulatorDomain
import XCTest
@testable import PressAny

@MainActor
final class MissingArtworkTests: XCTestCase {
    func testSearchChecksTheWholeLibraryAndPreservesExistingAndRemovedArtwork() async throws {
        let png = ArtworkTestLibrary.png()
        let provider = RecordingArtworkProvider(result: ArtworkTestLibrary.download(data: png))
        let library = try ArtworkTestLibrary(provider: provider)
        defer { library.removeFiles() }
        let container = library.container
        let first = try library.addGame(dump: library.dumps[0], marker: 1)
        let second = try library.addGame(dump: library.dumps[1], marker: 2)
        let manual = try library.addGame(dump: library.dumps[0], marker: 3)
        let removed = try library.addGame(dump: library.dumps[0], marker: 4)
        let unknown = try library.addGame(dump: nil, marker: 5)
        let existing = try container.gameArtwork.set(gameID: manual.id, imageData: png, fileExtension: "png").artworkAssetID
        try container.gameArtwork.set(gameID: removed.id, imageData: png, fileExtension: "png")
        try container.gameArtwork.remove(gameID: removed.id)
        try AutomaticArtworkSetting(store: container.repositories.settings).save(false)
        var progress: [AppContainer.MissingArtworkProgress] = []

        let result = try await container.findMissingArtwork { progress.append($0) }

        XCTAssertEqual(result.total, 4)
        XCTAssertEqual(result.checked, 4)
        XCTAssertEqual(result.added, 2)
        XCTAssertEqual(result.failed, 0)
        XCTAssertEqual(progress.map(\.checked), [0, 1, 2, 3, 4])
        for game in [first, second] {
            XCTAssertNotNil(try container.repositories.games.fetchGame(id: game.id)?.artworkAssetID)
        }
        XCTAssertEqual(try container.repositories.games.fetchGame(id: manual.id)?.artworkAssetID, existing)
        XCTAssertNil(try container.repositories.games.fetchGame(id: removed.id)?.artworkAssetID)
        XCTAssertNil(try container.repositories.games.fetchGame(id: unknown.id)?.artworkAssetID)
        let requests = await provider.requests
        XCTAssertEqual(Set(requests.compactMap { $0.releaseNames.first }), Set(library.dumps.map(\.name)))
        XCTAssertEqual(requests.count, 2)
        XCTAssertFalse(try AutomaticArtworkSetting(store: container.repositories.settings).load())
    }

    func testCancellationStopsTheBatchAndDiscardsALateDownload() async throws {
        let requested = expectation(description: "First download starts")
        let provider = PendingArtworkProvider { _, _ in requested.fulfill() }
        let library = try ArtworkTestLibrary(provider: provider)
        defer { library.removeFiles() }
        let first = try library.addGame(dump: library.dumps[0], marker: 1)
        let second = try library.addGame(dump: library.dumps[1], marker: 2)
        let task = Task { try await library.container.findMissingArtwork() }
        await fulfillment(of: [requested], timeout: 3)
        task.cancel()
        await provider.finish(with: ArtworkTestLibrary.download(data: ArtworkTestLibrary.png()))
        do {
            _ = try await task.value
            XCTFail("A canceled search must not finish normally")
        } catch is CancellationError {}
        let requests = await provider.requests
        XCTAssertEqual(requests.count, 1)
        for game in [first, second] {
            XCTAssertNil(try library.container.repositories.games.fetchGame(id: game.id)?.artworkAssetID)
        }
    }

    func testAnUnreadableImageDoesNotStopTheRestOfTheBatch() async throws {
        let provider = RecordingArtworkProvider(result: ArtworkTestLibrary.download(data: Data([1, 2])))
        let library = try ArtworkTestLibrary(provider: provider)
        defer { library.removeFiles() }
        _ = try library.addGame(dump: library.dumps[0], marker: 1)
        _ = try library.addGame(dump: library.dumps[1], marker: 2)
        let result = try await library.container.findMissingArtwork()
        XCTAssertEqual(result.checked, 2)
        XCTAssertEqual(result.added, 0)
        XCTAssertEqual(result.failed, 2)
        let requests = await provider.requests
        XCTAssertEqual(requests.count, 2)
    }
}

private actor RecordingArtworkProvider: ArtworkProvider {
    let result: ProvidedArtwork
    private(set) var requests: [ArtworkLookup] = []

    init(result: ProvidedArtwork) { self.result = result }

    func artwork(for lookup: ArtworkLookup) async throws -> ProvidedArtwork? {
        requests.append(lookup)
        return result
    }
}

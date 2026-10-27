import EmulatorApplication
import EmulatorDomain
import XCTest
@testable import PressAny

@MainActor
final class MissingArtworkTests: XCTestCase {
    func testSearchDoesNotStoreArtworkBeforeApproval() async throws {
        let provider = RecordingArtworkProvider(result: ArtworkTestLibrary.download(data: ArtworkTestLibrary.png()))
        let library = try await ArtworkTestLibrary(provider: provider)
        defer { library.removeFiles() }
        let game = try library.addGame(dump: library.dumps[0], marker: 1)

        _ = try await library.container.findMissingArtwork(proposalDirectory: library.root.appendingPathComponent("Proposals"))

        XCTAssertNil(try library.container.repositories.games.fetchGame(id: game.id)?.artworkAssetID)
        XCTAssertTrue(try library.container.repositories.assets.fetchAssets().filter { $0.kind == .artwork }.isEmpty)
    }

    func testSearchChecksTheWholeLibraryAndProposesPreviouslyRemovedArtworkWithoutSaving() async throws {
        let png = ArtworkTestLibrary.png()
        let provider = RecordingArtworkProvider(result: ArtworkTestLibrary.download(data: png))
        let library = try await ArtworkTestLibrary(provider: provider)
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

        let result = try await container.findMissingArtwork(proposalDirectory: library.root.appendingPathComponent("Proposals")) { progress.append($0) }

        XCTAssertEqual(result.progress.total, 4)
        XCTAssertEqual(result.progress.checked, 4)
        XCTAssertEqual(result.progress.found, 3)
        XCTAssertEqual(result.progress.failed, 0)
        XCTAssertEqual(progress.map(\.checked), [0, 1, 2, 3, 4])
        XCTAssertEqual(Set(result.proposals.map(\.id)), Set([first.id, second.id, removed.id]))
        XCTAssertTrue(result.proposals.allSatisfy { FileManager.default.fileExists(atPath: $0.imageURL.path) })
        for game in [first, second] {
            XCTAssertNil(try container.repositories.games.fetchGame(id: game.id)?.artworkAssetID)
        }
        XCTAssertEqual(try container.repositories.games.fetchGame(id: manual.id)?.artworkAssetID, existing)
        XCTAssertNil(try container.repositories.games.fetchGame(id: removed.id)?.artworkAssetID)
        XCTAssertNil(try container.repositories.games.fetchGame(id: unknown.id)?.artworkAssetID)
        let requests = await provider.requests
        XCTAssertEqual(Set(requests.compactMap { $0.releaseNames.first }), Set(library.dumps.map(\.name)))
        XCTAssertEqual(requests.count, 3)
        XCTAssertFalse(try AutomaticArtworkSetting(store: container.repositories.settings).load())
    }

    func testCancellationStopsTheBatchAndDiscardsALateDownload() async throws {
        let requested = expectation(description: "First download starts")
        let provider = PendingArtworkProvider { _, _ in requested.fulfill() }
        let library = try await ArtworkTestLibrary(provider: provider)
        defer { library.removeFiles() }
        let first = try library.addGame(dump: library.dumps[0], marker: 1)
        let second = try library.addGame(dump: library.dumps[1], marker: 2)
        let task = Task { try await library.container.findMissingArtwork(proposalDirectory: library.root.appendingPathComponent("Proposals")) }
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
        let library = try await ArtworkTestLibrary(provider: provider)
        defer { library.removeFiles() }
        _ = try library.addGame(dump: library.dumps[0], marker: 1)
        _ = try library.addGame(dump: library.dumps[1], marker: 2)
        let result = try await library.container.findMissingArtwork(proposalDirectory: library.root.appendingPathComponent("Proposals"))
        XCTAssertEqual(result.progress.checked, 2)
        XCTAssertEqual(result.progress.found, 0)
        XCTAssertEqual(result.progress.failed, 2)
        let requests = await provider.requests
        XCTAssertEqual(requests.count, 2)
    }

    func testReviewSavesOnlyAcceptedImagesAndTheirProvenance() async throws {
        let provider = RecordingArtworkProvider(result: ArtworkTestLibrary.download(data: ArtworkTestLibrary.png()))
        let library = try await ArtworkTestLibrary(provider: provider)
        defer { library.removeFiles() }
        let accepted = try library.addGame(dump: library.dumps[0], marker: 1)
        let denied = try library.addGame(dump: library.dumps[1], marker: 2)
        let model = MissingArtworkReviewViewModel(container: library.container)
        defer { model.discard() }
        await model.search()
        let deniedIndex = try XCTUnwrap(model.items.firstIndex { $0.id == denied.id })
        model.items[deniedIndex].accepted = false

        XCTAssertEqual(model.acceptedCount, 1)
        XCTAssertTrue(model.apply())

        let game = try XCTUnwrap(library.container.repositories.games.fetchGame(id: accepted.id))
        let asset = try XCTUnwrap(library.container.repositories.assets.fetchAsset(id: XCTUnwrap(game.artworkAssetID)))
        let provenance = try JSONDecoder().decode(ArtworkProvenance.self, from: Data(XCTUnwrap(asset.provenanceJSON).utf8))
        XCTAssertEqual(provenance.rights, "Synthetic test data")
        XCTAssertNil(try library.container.repositories.games.fetchGame(id: denied.id)?.artworkAssetID)
        XCTAssertNil(try library.container.repositories.settings.valueJSON(key: "artwork.chosen", scope: .game(denied.id)))
        XCTAssertEqual(model.items.map(\.id), [denied.id])
    }

    func testCancelingReviewDiscardsEarlierProposalsAndALateDownload() async throws {
        let firstRequest = expectation(description: "First proposal download")
        let secondRequest = expectation(description: "Second proposal download")
        let provider = PendingArtworkProvider { _, number in
            if number == 1 { firstRequest.fulfill() }
            if number == 2 { secondRequest.fulfill() }
        }
        let library = try await ArtworkTestLibrary(provider: provider)
        defer { library.removeFiles() }
        let first = try library.addGame(dump: library.dumps[0], marker: 1)
        let second = try library.addGame(dump: library.dumps[1], marker: 2)
        let model = MissingArtworkReviewViewModel(container: library.container)
        let task = Task { await model.search() }
        await fulfillment(of: [firstRequest], timeout: 3)
        await provider.finish(with: ArtworkTestLibrary.download(data: ArtworkTestLibrary.png()))
        await fulfillment(of: [secondRequest], timeout: 3)
        XCTAssertEqual(model.progress?.found, 1)

        task.cancel()
        await provider.finish(with: ArtworkTestLibrary.download(data: ArtworkTestLibrary.png()))
        await task.value

        XCTAssertTrue(model.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: model.proposalDirectory.path))
        for game in [first, second] {
            XCTAssertNil(try library.container.repositories.games.fetchGame(id: game.id)?.artworkAssetID)
        }
    }

    func testDiscardingReviewDeletesPreviewsAndLeavesTheLibraryUnchanged() async throws {
        let provider = RecordingArtworkProvider(result: ArtworkTestLibrary.download(data: ArtworkTestLibrary.png()))
        let library = try await ArtworkTestLibrary(provider: provider)
        defer { library.removeFiles() }
        let game = try library.addGame(dump: library.dumps[0], marker: 1)
        let model = MissingArtworkReviewViewModel(container: library.container)
        await model.search()
        XCTAssertEqual(model.items.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: model.proposalDirectory.path))

        model.discard()

        XCTAssertTrue(model.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: model.proposalDirectory.path))
        XCTAssertNil(try library.container.repositories.games.fetchGame(id: game.id)?.artworkAssetID)
        XCTAssertNil(try library.container.repositories.settings.valueJSON(key: "artwork.chosen", scope: .game(game.id)))
    }

    func testReviewPreservesArtworkRemovedAfterSearchAndReportsTheChange() async throws {
        let provider = RecordingArtworkProvider(result: ArtworkTestLibrary.download(data: ArtworkTestLibrary.png()))
        let library = try await ArtworkTestLibrary(provider: provider)
        defer { library.removeFiles() }
        let game = try library.addGame(dump: library.dumps[0], marker: 1)
        let model = MissingArtworkReviewViewModel(container: library.container)
        defer { model.discard() }
        await model.search()
        try library.container.gameArtwork.remove(gameID: game.id)

        XCTAssertFalse(model.apply())

        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertNil(try library.container.repositories.games.fetchGame(id: game.id)?.artworkAssetID)
    }

    func testReviewCanRestoreArtworkRemovedBeforeSearch() async throws {
        let provider = RecordingArtworkProvider(result: ArtworkTestLibrary.download(data: ArtworkTestLibrary.png()))
        let library = try await ArtworkTestLibrary(provider: provider)
        defer { library.removeFiles() }
        let game = try library.addGame(dump: library.dumps[0], marker: 1)
        try library.container.gameArtwork.remove(gameID: game.id)
        let model = MissingArtworkReviewViewModel(container: library.container)
        defer { model.discard() }
        await model.search()

        XCTAssertEqual(model.items.map(\.id), [game.id])
        XCTAssertNil(try library.container.repositories.games.fetchGame(id: game.id)?.artworkAssetID)
        XCTAssertTrue(model.apply())
        XCTAssertNotNil(try library.container.repositories.games.fetchGame(id: game.id)?.artworkAssetID)
    }

    func testReviewPreservesARemovalRepeatedWhileTheProposalIsOpen() async throws {
        let provider = RecordingArtworkProvider(result: ArtworkTestLibrary.download(data: ArtworkTestLibrary.png()))
        let library = try await ArtworkTestLibrary(provider: provider)
        defer { library.removeFiles() }
        let game = try library.addGame(dump: library.dumps[0], marker: 1)
        try library.container.gameArtwork.remove(gameID: game.id)
        let model = MissingArtworkReviewViewModel(container: library.container)
        defer { model.discard() }
        await model.search()
        XCTAssertEqual(model.items.count, 1)
        try library.container.gameArtwork.remove(gameID: game.id)

        XCTAssertFalse(model.apply())
        XCTAssertNil(try library.container.repositories.games.fetchGame(id: game.id)?.artworkAssetID)
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

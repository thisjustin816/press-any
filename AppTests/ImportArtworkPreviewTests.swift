import EmulatorApplication
import EmulatorDomain
import Foundation
import GameIdentity
import Importing
import XCTest
@testable import PressAny

@MainActor
final class ImportArtworkPreviewTests: XCTestCase {
    func testPreviewIsNotStoredUntilImportAndKeepsItsProvenance() async throws {
        let provider = PreviewArtworkProvider(data: ArtworkTestLibrary.png())
        let fixture = try await PreviewFixture(provider: provider)
        defer { fixture.library.removeFiles() }

        await fixture.review.loadAutomaticArtwork()

        let preview = try XCTUnwrap(fixture.review.proposedAutomaticArtwork)
        XCTAssertTrue(try fixture.library.container.repositories.games.fetchGames().isEmpty)
        let result = try fixture.review.commit()
        let game = try XCTUnwrap(fixture.library.container.repositories.games.fetchGame(id: result.build.gameID))
        let asset = try XCTUnwrap(fixture.library.container.repositories.assets.fetchAsset(id: XCTUnwrap(game.artworkAssetID)))
        let provenance = try JSONDecoder().decode(ArtworkProvenance.self, from: Data(XCTUnwrap(asset.provenanceJSON).utf8))
        XCTAssertEqual(provenance, preview.provenance)
        let requests = await provider.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.releaseNames.first, fixture.library.dumps[0].name)
        XCTAssertEqual(requests.first?.inherited, true)
    }

    func testManualArtworkWinsOverALateAutomaticProposal() async throws {
        let requested = expectation(description: "Preview download begins")
        let provider = PendingArtworkProvider { _, _ in requested.fulfill() }
        let fixture = try await PreviewFixture(provider: provider)
        defer { fixture.library.removeFiles() }
        let task = Task { await fixture.review.loadAutomaticArtwork() }
        await fulfillment(of: [requested], timeout: 3)
        fixture.review.chooseArtwork(ArtworkTestLibrary.png(), fileExtension: "png")
        await provider.finish(with: ArtworkTestLibrary.download(data: ArtworkTestLibrary.png()))
        await task.value

        XCTAssertNotNil(fixture.review.artwork)
        XCTAssertNil(fixture.review.proposedAutomaticArtwork)
        let result = try fixture.review.commit()
        let game = try XCTUnwrap(fixture.library.container.repositories.games.fetchGame(id: result.game.id))
        let asset = try XCTUnwrap(fixture.library.container.repositories.assets.fetchAsset(id: XCTUnwrap(game.artworkAssetID)))
        XCTAssertNil(asset.provenanceJSON)
    }

    func testRemovingTheAutomaticPreviewImportsWithoutArtworkOrAnotherLookup() async throws {
        let provider = PreviewArtworkProvider(data: ArtworkTestLibrary.png())
        let fixture = try await PreviewFixture(provider: provider)
        defer { fixture.library.removeFiles() }
        await fixture.review.loadAutomaticArtwork()
        XCTAssertNotNil(fixture.review.artworkPreview)

        fixture.review.removeArtwork()
        let result = try fixture.review.commit()

        XCTAssertFalse(fixture.review.useAutomaticArtwork)
        XCTAssertNil(try fixture.library.container.repositories.games.fetchGame(id: result.game.id)?.artworkAssetID)
        let requests = await provider.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testImportSettingOffDoesNotDownloadAPreview() async throws {
        let provider = PreviewArtworkProvider(data: ArtworkTestLibrary.png())
        let fixture = try await PreviewFixture(provider: provider)
        defer { fixture.library.removeFiles() }
        try AutomaticArtworkSetting(store: fixture.library.container.repositories.settings).save(false)

        await fixture.review.loadAutomaticArtwork()

        XCTAssertNil(fixture.review.proposedAutomaticArtwork)
        let requests = await provider.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testChangingTheRequestDiscardsALateProposal() async throws {
        let requested = expectation(description: "Preview download begins")
        let provider = PendingArtworkProvider { _, _ in requested.fulfill() }
        let fixture = try await PreviewFixture(provider: provider)
        defer { fixture.library.removeFiles() }
        let task = Task { await fixture.review.loadAutomaticArtwork() }
        await fulfillment(of: [requested], timeout: 3)
        fixture.review.matchGame(fixture.library.dumps[1])
        await provider.finish(with: ArtworkTestLibrary.download(data: ArtworkTestLibrary.png()))
        await task.value

        XCTAssertNil(fixture.review.proposedAutomaticArtwork)
        XCTAssertNil(fixture.review.artworkPreview)
    }

    func testCancelDiscardsALateProposalAndTheStagedROM() async throws {
        let requested = expectation(description: "Preview download begins")
        let provider = PendingArtworkProvider { _, _ in requested.fulfill() }
        let fixture = try await PreviewFixture(provider: provider)
        defer { fixture.library.removeFiles() }
        let task = Task { await fixture.review.loadAutomaticArtwork() }
        await fulfillment(of: [requested], timeout: 3)

        fixture.review.cancel()
        await provider.finish(with: ArtworkTestLibrary.download(data: ArtworkTestLibrary.png()))
        await task.value

        XCTAssertNil(fixture.review.proposedAutomaticArtwork)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.review.analysis.stagedURL.path))
        XCTAssertTrue(try fixture.library.container.repositories.games.fetchGames().isEmpty)
    }

    func testAPreferredBuildChangedDuringReviewKeepsTheStaleProposalOut() async throws {
        let provider = PreviewArtworkProvider(data: ArtworkTestLibrary.png())
        let fixture = try await PreviewFixture(provider: provider, existingGame: true)
        defer { fixture.library.removeFiles() }
        let container = fixture.library.container
        var game = try XCTUnwrap(container.repositories.games.fetchGames().first)
        fixture.review.markAsPreferred = false
        await fixture.review.loadAutomaticArtwork()
        XCTAssertNotNil(fixture.review.proposedAutomaticArtwork)
        game.preferredBuildID = try fixture.library.addBuild(to: game, dump: fixture.library.dumps[1], marker: 2).id
        try container.repositories.games.updateGame(game)

        _ = try fixture.review.commit()

        XCTAssertNil(try container.repositories.games.fetchGame(id: game.id)?.artworkAssetID)
        XCTAssertEqual(try container.repositories.games.fetchGame(id: game.id)?.preferredBuildID, game.preferredBuildID)
    }

    func testImportDoesNotWaitForASlowPreviewAndIgnoresItsLateResult() async throws {
        let requested = expectation(description: "Preview download begins")
        let provider = PendingArtworkProvider { _, _ in requested.fulfill() }
        var lookups = 0
        let fixture = try await PreviewFixture(provider: provider, fetchArtwork: { _ in lookups += 1 })
        defer { fixture.library.removeFiles() }
        let task = Task { await fixture.review.loadAutomaticArtwork() }
        await fulfillment(of: [requested], timeout: 3)

        let result = try fixture.review.commit()

        XCTAssertEqual(lookups, 1)
        await provider.finish(with: ArtworkTestLibrary.download(data: ArtworkTestLibrary.png()))
        await task.value
        XCTAssertNil(fixture.review.proposedAutomaticArtwork)
        XCTAssertNil(try fixture.library.container.repositories.games.fetchGame(id: result.game.id)?.artworkAssetID)
    }
}

private actor PreviewArtworkProvider: ArtworkProvider {
    let data: Data
    private(set) var requests: [ArtworkLookup] = []

    init(data: Data) { self.data = data }

    func artwork(for lookup: ArtworkLookup) async throws -> ProvidedArtwork? {
        requests.append(lookup)
        return ArtworkTestLibrary.download(data: data)
    }
}

@MainActor
private struct PreviewFixture {
    let library: ArtworkTestLibrary
    let review: ImportReviewViewModel

    init(provider: any ArtworkProvider, existingGame: Bool = false, fetchArtwork: ((Build) -> Void)? = nil) async throws {
        library = try await ArtworkTestLibrary(provider: provider)
        let container = library.container
        if existingGame { _ = try library.addGame(dump: library.dumps[0], marker: 1) }
        let file = library.root.appendingPathComponent("Preview Example.gb")
        try Data(repeating: 0, count: 0x8000).write(to: file)
        let coordinator = ImportCoordinator(analyzer: container.importAnalyzer,
            committer: container.importCommitter, assetStore: container.fileStore)
        review = ImportReviewViewModel(analysis: try coordinator.analyzeROM(at: file),
            games: try container.repositories.games.fetchGames(), coordinator: coordinator,
            existingBuilds: { container.builds(in: $0) },
            setArtwork: { _ = try container.gameArtwork.set(gameID: $0, imageData: $1, fileExtension: $2) },
            fetchArtwork: fetchArtwork ?? { _ in XCTFail("A completed preview must not start another artwork request") },
            proposeArtwork: container.proposeImportArtwork,
            applyArtworkProposal: container.applyImportArtworkProposal,
            knownDumps: container.knownDumps)
        review.matchGame(library.dumps[0])
    }
}

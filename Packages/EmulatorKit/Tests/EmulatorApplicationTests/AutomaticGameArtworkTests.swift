import AssetStorage
import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import XCTest

@MainActor
final class AutomaticGameArtworkTests: XCTestCase {
    func testDownloadedArtworkAndProvenanceAreStoredOnce() async throws {
        let fixture = try AutomaticArtworkFixture()
        defer { fixture.removeFiles() }
        let result = try await fixture.automatic([TestArtworkProvider { fixture.download }]).execute(gameID: fixture.game.id, lookup: fixture.lookup)
        XCTAssertTrue(result)
        let game = try XCTUnwrap(fixture.games.fetchGame(id: fixture.game.id))
        let asset = try XCTUnwrap(fixture.assets.fetchAsset(id: XCTUnwrap(game.artworkAssetID)))
        XCTAssertEqual(asset.storageClass, .userData)
        XCTAssertEqual(try JSONDecoder().decode(ArtworkProvenance.self, from: Data(XCTUnwrap(asset.provenanceJSON).utf8)), fixture.download.provenance)
        XCTAssertEqual(try fixture.store.readData(at: fixture.store.managedURL(relativePath: asset.relativePath)), fixture.download.data)
        let again = try await fixture.automatic([TestArtworkProvider { XCTFail("Chosen artwork must not recheck"); return nil }])
            .execute(gameID: fixture.game.id, lookup: fixture.lookup)
        XCTAssertFalse(again)
    }

    func testArtworkChosenDuringADownloadWins() async throws {
        let fixture = try AutomaticArtworkFixture()
        defer { fixture.removeFiles() }
        let provider = TestArtworkProvider {
            try fixture.artwork.set(gameID: fixture.game.id, imageData: Data([9]), fileExtension: "png")
            return fixture.download
        }
        let wrote = try await fixture.automatic([provider]).execute(gameID: fixture.game.id, lookup: fixture.lookup)
        XCTAssertFalse(wrote)
        let game = try XCTUnwrap(fixture.games.fetchGame(id: fixture.game.id))
        let asset = try XCTUnwrap(fixture.assets.fetchAsset(id: XCTUnwrap(game.artworkAssetID)))
        XCTAssertNil(asset.provenanceJSON)
        XCTAssertEqual(try fixture.store.readData(at: fixture.store.managedURL(relativePath: asset.relativePath)), Data([9]))
    }

    func testProviderMissesAndFailuresContinueTheChain() async throws {
        let fixture = try AutomaticArtworkFixture()
        defer { fixture.removeFiles() }
        let providers = [TestArtworkProvider { throw URLError(.notConnectedToInternet) },
            TestArtworkProvider { nil }, TestArtworkProvider { fixture.download },
            TestArtworkProvider { XCTFail("Only the chosen image is fetched"); return nil }]
        let wrote = try await fixture.automatic(providers).execute(gameID: fixture.game.id, lookup: fixture.lookup)
        XCTAssertTrue(wrote)
    }

    func testRemovingAManualChoiceDuringDownloadKeepsItRemoved() async throws {
        let fixture = try AutomaticArtworkFixture()
        defer { fixture.removeFiles() }
        let provider = TestArtworkProvider {
            try fixture.artwork.set(gameID: fixture.game.id, imageData: Data([9]), fileExtension: "png")
            try fixture.artwork.remove(gameID: fixture.game.id)
            return fixture.download
        }
        let wrote = try await fixture.automatic([provider]).execute(gameID: fixture.game.id, lookup: fixture.lookup)
        XCTAssertFalse(wrote)
        XCTAssertNil(try fixture.games.fetchGame(id: fixture.game.id)?.artworkAssetID)
    }

    func testUnrelatedGameEditsDoNotDiscardTheDownload() async throws {
        let fixture = try AutomaticArtworkFixture()
        defer { fixture.removeFiles() }
        let provider = TestArtworkProvider {
            var game = try XCTUnwrap(fixture.games.fetchGame(id: fixture.game.id))
            game.primaryTitle = "Player's title"
            game.modifiedAt = Date()
            try fixture.games.updateGame(game)
            return fixture.download
        }
        let wrote = try await fixture.automatic([provider]).execute(gameID: fixture.game.id, lookup: fixture.lookup)
        XCTAssertTrue(wrote)
        XCTAssertEqual(try fixture.games.fetchGame(id: fixture.game.id)?.primaryTitle, "Player's title")
    }

    func testRemovedArtworkDoesNotStartAnotherAutomaticLookup() async throws {
        let fixture = try AutomaticArtworkFixture()
        defer { fixture.removeFiles() }
        try fixture.artwork.set(gameID: fixture.game.id, imageData: Data([9]), fileExtension: "png")
        try fixture.artwork.remove(gameID: fixture.game.id)
        let wrote = try await fixture.automatic([TestArtworkProvider { XCTFail("Removal is a choice"); return nil }])
            .execute(gameID: fixture.game.id, lookup: fixture.lookup)
        XCTAssertFalse(wrote)
    }

    func testALookupCreatedForAnOlderPreferenceDoesNotStartADownload() async throws {
        let fixture = try AutomaticArtworkFixture()
        defer { fixture.removeFiles() }
        var game = fixture.game
        game.preferredBuildID = UUID()
        try fixture.games.updateGame(game)
        let wrote = try await fixture.automatic([TestArtworkProvider {
            XCTFail("The lookup was formed before the Preferred Build changed")
            return fixture.download
        }]).execute(gameID: game.id, lookup: fixture.lookup, expectedPreferredBuildID: fixture.game.preferredBuildID)
        XCTAssertFalse(wrote)
    }

    func testAMatchingPreferredBuildCanReceiveArtwork() async throws {
        let fixture = try AutomaticArtworkFixture()
        defer { fixture.removeFiles() }
        var game = fixture.game
        game.preferredBuildID = UUID()
        try fixture.games.updateGame(game)
        let wrote = try await fixture.automatic([TestArtworkProvider { fixture.download }])
            .execute(gameID: game.id, lookup: fixture.lookup, expectedPreferredBuildID: game.preferredBuildID)
        XCTAssertTrue(wrote)
    }

    func testMissingGamesDoNotDownloadAndDeletedGamesAreNotRecreated() async throws {
        let fixture = try AutomaticArtworkFixture()
        defer { fixture.removeFiles() }
        let missing = try await fixture.automatic([TestArtworkProvider { XCTFail("Missing Game"); return nil }])
            .execute(gameID: UUID(), lookup: fixture.lookup)
        XCTAssertFalse(missing)
        let deleted = try await fixture.automatic([TestArtworkProvider {
            try fixture.games.deleteGame(id: fixture.game.id)
            return fixture.download
        }]).execute(gameID: fixture.game.id, lookup: fixture.lookup)
        XCTAssertFalse(deleted)
        XCTAssertTrue(try fixture.assets.fetchAssets().isEmpty)
    }

    func testDisabledAutomaticArtworkDoesNotDownloadOrStoreAnInFlightResult() async throws {
        let fixture = try AutomaticArtworkFixture()
        defer { fixture.removeFiles() }
        let setting = AutomaticArtworkSetting(store: fixture.settings)
        XCTAssertTrue(try setting.load())
        try setting.save(false)
        let disabled = try await fixture.automatic([TestArtworkProvider { XCTFail("Disabled"); return nil }])
            .execute(gameID: fixture.game.id, lookup: fixture.lookup)
        XCTAssertFalse(disabled)
        try setting.save(true)
        let changed = try await fixture.automatic([TestArtworkProvider {
            try setting.save(false)
            return fixture.download
        }]).execute(gameID: fixture.game.id, lookup: fixture.lookup)
        XCTAssertFalse(changed)
        XCTAssertNil(try fixture.games.fetchGame(id: fixture.game.id)?.artworkAssetID)
        XCTAssertFalse(try AutomaticArtworkSetting(store: fixture.settings).load())
    }

    func testCancellationStopsFallbackAndLeavesTheGameEmpty() async throws {
        let fixture = try AutomaticArtworkFixture()
        defer { fixture.removeFiles() }
        do {
            _ = try await fixture.automatic([TestArtworkProvider { throw CancellationError() },
                TestArtworkProvider { XCTFail("Canceled lookup must not continue"); return nil }])
                .execute(gameID: fixture.game.id, lookup: fixture.lookup)
            XCTFail("Cancellation must propagate")
        } catch is CancellationError {}
        XCTAssertNil(try fixture.games.fetchGame(id: fixture.game.id)?.artworkAssetID)
    }
}

private struct TestArtworkProvider: ArtworkProvider {
    let result: @Sendable () throws -> ProvidedArtwork?
    func artwork(for lookup: ArtworkLookup) async throws -> ProvidedArtwork? { try result() }
}

private struct AutomaticArtworkFixture: Sendable {
    let game = Game(id: UUID(), primaryTitle: "Example", systemFamily: "gameboy", createdAt: .distantPast, modifiedAt: .distantPast)
    let games: InMemoryGameRepository
    let assets = InMemoryAssetRepository()
    let settings = InMemorySettingsStore()
    let store: ManagedFileStore
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("artwork-\(UUID())")
    let lookup = ArtworkLookup(system: .gameBoy, releaseNames: ["Example (World)"], inherited: false)
    let download = ProvidedArtwork(data: Data([1, 2]), fileExtension: "png", provenance: .init(provider: "test",
        sourceURL: URL(string: "https://example.com/art.png")!, fetchedAt: .distantPast, rights: "Synthetic test data"))

    init() throws {
        games = InMemoryGameRepository([game])
        store = try ManagedFileStore(rootURL: root)
    }

    var artwork: GameArtwork {
        GameArtwork(games: games, assets: assets, assetStore: store, prepareImage: { ($0, $1) }, settings: settings)
    }

    func automatic(_ providers: [any ArtworkProvider]) -> AutomaticGameArtwork {
        AutomaticGameArtwork(games: games, artwork: artwork, settings: settings, providers: providers)
    }

    func removeFiles() { try? FileManager.default.removeItem(at: root) }
}

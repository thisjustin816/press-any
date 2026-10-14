import AssetStorage
import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import XCTest

@MainActor
final class FindMissingGameArtworkTests: XCTestCase {
    func testFindingAProposalDoesNotStoreItOrRecordAChoice() async throws {
        let fixture = try ArtworkSearchFixture()
        defer { fixture.removeFiles() }
        try AutomaticArtworkSetting(store: fixture.settings).save(false)
        let finder = fixture.finder([TestArtworkProvider { fixture.download }])

        let proposal = try await finder.find(gameID: fixture.game.id, lookup: fixture.lookup, trigger: .userRequested)

        XCTAssertNil(try fixture.games.fetchGame(id: fixture.game.id)?.artworkAssetID)
        XCTAssertTrue(try fixture.assets.fetchAssets().isEmpty)
        XCTAssertNil(try fixture.settings.valueJSON(key: "artwork.chosen", scope: .game(fixture.game.id)))
        let provided = try XCTUnwrap(proposal)
        XCTAssertEqual(provided.data, fixture.download.data)
        XCTAssertTrue(try finder.apply(provided, gameID: fixture.game.id, trigger: .userRequested))
        XCTAssertNotNil(try fixture.games.fetchGame(id: fixture.game.id)?.artworkAssetID)
    }

    func testAcceptingAProposalPreservesALaterChoiceOrRemoval() async throws {
        for remove in [false, true] {
            let fixture = try ArtworkSearchFixture()
            defer { fixture.removeFiles() }
            let finder = fixture.finder([TestArtworkProvider { fixture.download }])
            let proposal = try await finder.find(gameID: fixture.game.id, lookup: fixture.lookup, trigger: .userRequested)
            let chosen = try fixture.artwork.set(gameID: fixture.game.id, imageData: Data([9]), fileExtension: "png")
            if remove { try fixture.artwork.remove(gameID: fixture.game.id) }

            let wrote = try finder.apply(XCTUnwrap(proposal), gameID: fixture.game.id, trigger: .userRequested)

            XCTAssertFalse(wrote)
            XCTAssertEqual(try fixture.games.fetchGame(id: fixture.game.id)?.artworkAssetID, remove ? nil : chosen.artworkAssetID)
        }
    }

    func testAcceptingAProposalPreservesAChangedBuildOrDeletedGame() async throws {
        for delete in [false, true] {
            let fixture = try ArtworkSearchFixture()
            defer { fixture.removeFiles() }
            let finder = fixture.finder([TestArtworkProvider { fixture.download }])
            let proposal = try await finder.find(gameID: fixture.game.id, lookup: fixture.lookup, trigger: .userRequested)
            if delete {
                try fixture.games.deleteGame(id: fixture.game.id)
            } else {
                var game = fixture.game
                game.preferredBuildID = UUID()
                try fixture.games.updateGame(game)
            }

            XCTAssertFalse(try finder.apply(XCTUnwrap(proposal), gameID: fixture.game.id, trigger: .userRequested))
            XCTAssertTrue(try fixture.assets.fetchAssets().isEmpty)
        }
    }

    func testUserRequestedSearchWorksWithAutomaticArtworkOff() async throws {
        let fixture = try ArtworkSearchFixture()
        defer { fixture.removeFiles() }
        try AutomaticArtworkSetting(store: fixture.settings).save(false)
        let wrote = try await fixture.finder([TestArtworkProvider { fixture.download }])
            .execute(gameID: fixture.game.id, lookup: fixture.lookup, trigger: .userRequested)
        XCTAssertTrue(wrote)
    }

    func testUserRequestedSearchKeepsDeliberatelyRemovedArtworkBlank() async throws {
        let fixture = try ArtworkSearchFixture()
        defer { fixture.removeFiles() }
        try fixture.artwork.remove(gameID: fixture.game.id)
        let wrote = try await fixture.finder([TestArtworkProvider {
            XCTFail("A batch search must preserve deliberate removals")
            return fixture.download
        }]).execute(gameID: fixture.game.id, lookup: fixture.lookup, trigger: .userRequested)
        XCTAssertFalse(wrote)
    }

    func testDownloadedArtworkAndProvenanceAreStoredOnce() async throws {
        let fixture = try ArtworkSearchFixture()
        defer { fixture.removeFiles() }
        let result = try await fixture.finder([TestArtworkProvider { fixture.download }]).execute(gameID: fixture.game.id, lookup: fixture.lookup)
        XCTAssertTrue(result)
        let game = try XCTUnwrap(fixture.games.fetchGame(id: fixture.game.id))
        let asset = try XCTUnwrap(fixture.assets.fetchAsset(id: XCTUnwrap(game.artworkAssetID)))
        XCTAssertEqual(asset.storageClass, .userData)
        XCTAssertEqual(try JSONDecoder().decode(ArtworkProvenance.self, from: Data(XCTUnwrap(asset.provenanceJSON).utf8)), fixture.download.provenance)
        XCTAssertEqual(try fixture.store.readData(at: fixture.store.managedURL(relativePath: asset.relativePath)), fixture.download.data)
        let again = try await fixture.finder([TestArtworkProvider { XCTFail("Chosen artwork must not recheck"); return nil }])
            .execute(gameID: fixture.game.id, lookup: fixture.lookup)
        XCTAssertFalse(again)
    }

    func testArtworkChosenDuringADownloadWins() async throws {
        let fixture = try ArtworkSearchFixture()
        defer { fixture.removeFiles() }
        let provider = TestArtworkProvider {
            try fixture.artwork.set(gameID: fixture.game.id, imageData: Data([9]), fileExtension: "png")
            return fixture.download
        }
        let wrote = try await fixture.finder([provider]).execute(gameID: fixture.game.id, lookup: fixture.lookup)
        XCTAssertFalse(wrote)
        let game = try XCTUnwrap(fixture.games.fetchGame(id: fixture.game.id))
        let asset = try XCTUnwrap(fixture.assets.fetchAsset(id: XCTUnwrap(game.artworkAssetID)))
        XCTAssertNil(asset.provenanceJSON)
        XCTAssertEqual(try fixture.store.readData(at: fixture.store.managedURL(relativePath: asset.relativePath)), Data([9]))
    }

    func testProviderMissesAndFailuresContinueTheChain() async throws {
        let fixture = try ArtworkSearchFixture()
        defer { fixture.removeFiles() }
        let providers = [TestArtworkProvider { throw URLError(.notConnectedToInternet) },
            TestArtworkProvider { nil }, TestArtworkProvider { fixture.download },
            TestArtworkProvider { XCTFail("Only the chosen image is fetched"); return nil }]
        let wrote = try await fixture.finder(providers).execute(gameID: fixture.game.id, lookup: fixture.lookup)
        XCTAssertTrue(wrote)
    }

    func testRemovingAManualChoiceDuringDownloadKeepsItRemoved() async throws {
        let fixture = try ArtworkSearchFixture()
        defer { fixture.removeFiles() }
        let provider = TestArtworkProvider {
            try fixture.artwork.set(gameID: fixture.game.id, imageData: Data([9]), fileExtension: "png")
            try fixture.artwork.remove(gameID: fixture.game.id)
            return fixture.download
        }
        let wrote = try await fixture.finder([provider]).execute(gameID: fixture.game.id, lookup: fixture.lookup)
        XCTAssertFalse(wrote)
        XCTAssertNil(try fixture.games.fetchGame(id: fixture.game.id)?.artworkAssetID)
    }

    func testUnrelatedGameEditsDoNotDiscardTheDownload() async throws {
        let fixture = try ArtworkSearchFixture()
        defer { fixture.removeFiles() }
        let provider = TestArtworkProvider {
            var game = try XCTUnwrap(fixture.games.fetchGame(id: fixture.game.id))
            game.primaryTitle = "Player's title"
            game.modifiedAt = Date()
            try fixture.games.updateGame(game)
            return fixture.download
        }
        let wrote = try await fixture.finder([provider]).execute(gameID: fixture.game.id, lookup: fixture.lookup)
        XCTAssertTrue(wrote)
        XCTAssertEqual(try fixture.games.fetchGame(id: fixture.game.id)?.primaryTitle, "Player's title")
    }

    func testRemovedArtworkDoesNotStartAnotherAutomaticLookup() async throws {
        let fixture = try ArtworkSearchFixture()
        defer { fixture.removeFiles() }
        try fixture.artwork.set(gameID: fixture.game.id, imageData: Data([9]), fileExtension: "png")
        try fixture.artwork.remove(gameID: fixture.game.id)
        let wrote = try await fixture.finder([TestArtworkProvider { XCTFail("Removal is a choice"); return nil }])
            .execute(gameID: fixture.game.id, lookup: fixture.lookup)
        XCTAssertFalse(wrote)
    }

    func testALookupCreatedForAnOlderPreferenceDoesNotStartADownload() async throws {
        let fixture = try ArtworkSearchFixture()
        defer { fixture.removeFiles() }
        var game = fixture.game
        game.preferredBuildID = UUID()
        try fixture.games.updateGame(game)
        let wrote = try await fixture.finder([TestArtworkProvider {
            XCTFail("The lookup was formed before the Preferred Build changed")
            return fixture.download
        }]).execute(gameID: game.id, lookup: fixture.lookup, expectedPreferredBuildID: fixture.game.preferredBuildID)
        XCTAssertFalse(wrote)
    }

    func testAMatchingPreferredBuildCanReceiveArtwork() async throws {
        let fixture = try ArtworkSearchFixture()
        defer { fixture.removeFiles() }
        var game = fixture.game
        game.preferredBuildID = UUID()
        try fixture.games.updateGame(game)
        let wrote = try await fixture.finder([TestArtworkProvider { fixture.download }])
            .execute(gameID: game.id, lookup: fixture.lookup, expectedPreferredBuildID: game.preferredBuildID)
        XCTAssertTrue(wrote)
    }

    func testMissingGamesDoNotDownloadAndDeletedGamesAreNotRecreated() async throws {
        let fixture = try ArtworkSearchFixture()
        defer { fixture.removeFiles() }
        let missing = try await fixture.finder([TestArtworkProvider { XCTFail("Missing Game"); return nil }])
            .execute(gameID: UUID(), lookup: fixture.lookup)
        XCTAssertFalse(missing)
        let deleted = try await fixture.finder([TestArtworkProvider {
            try fixture.games.deleteGame(id: fixture.game.id)
            return fixture.download
        }]).execute(gameID: fixture.game.id, lookup: fixture.lookup)
        XCTAssertFalse(deleted)
        XCTAssertTrue(try fixture.assets.fetchAssets().isEmpty)
    }

    func testDisabledAutomaticArtworkDoesNotDownloadOrStoreAnInFlightResult() async throws {
        let fixture = try ArtworkSearchFixture()
        defer { fixture.removeFiles() }
        let setting = AutomaticArtworkSetting(store: fixture.settings)
        XCTAssertTrue(try setting.load())
        try setting.save(false)
        let disabled = try await fixture.finder([TestArtworkProvider { XCTFail("Disabled"); return nil }])
            .execute(gameID: fixture.game.id, lookup: fixture.lookup)
        XCTAssertFalse(disabled)
        try setting.save(true)
        let changed = try await fixture.finder([TestArtworkProvider {
            try setting.save(false)
            return fixture.download
        }]).execute(gameID: fixture.game.id, lookup: fixture.lookup)
        XCTAssertFalse(changed)
        XCTAssertNil(try fixture.games.fetchGame(id: fixture.game.id)?.artworkAssetID)
        XCTAssertFalse(try AutomaticArtworkSetting(store: fixture.settings).load())
    }

    func testCancellationStopsFallbackAndLeavesTheGameEmpty() async throws {
        let fixture = try ArtworkSearchFixture()
        defer { fixture.removeFiles() }
        do {
            _ = try await fixture.finder([TestArtworkProvider { throw CancellationError() },
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

private struct ArtworkSearchFixture: Sendable {
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

    func finder(_ providers: [any ArtworkProvider]) -> FindMissingGameArtwork {
        FindMissingGameArtwork(games: games, artwork: artwork, settings: settings, providers: providers)
    }

    func removeFiles() { try? FileManager.default.removeItem(at: root) }
}

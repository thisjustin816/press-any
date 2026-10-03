import AssetStorage
import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import XCTest

final class GameArtworkTests: XCTestCase {
    func testSettingReplacingAndRemovingArtworkKeepsOneImage() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let game = Game(id: UUID(), primaryTitle: "Art", systemFamily: "gameboy", createdAt: now, modifiedAt: now)
        let games = InMemoryGameRepository([game])
        let assets = InMemoryAssetRepository()
        let store = try ManagedFileStore(rootURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("emulatorkit-artwork-tests-\(UUID().uuidString)", isDirectory: true))
        let artwork = GameArtwork(games: games, assets: assets, assetStore: store, now: { now })

        let first = try artwork.set(gameID: game.id, imageData: Data([1, 2, 3]), fileExtension: "png")
        let firstAsset = try XCTUnwrap(assets.fetchAsset(id: XCTUnwrap(first.artworkAssetID)))
        let firstURL = try store.managedURL(relativePath: firstAsset.relativePath)
        XCTAssertEqual(firstAsset.kind, .artwork)
        XCTAssertEqual(try store.readData(at: firstURL), Data([1, 2, 3]))
        XCTAssertEqual(try artwork.set(gameID: game.id, imageData: Data([1, 2, 3]), fileExtension: "png"), first, "the same image is a no-op")

        let second = try artwork.set(gameID: game.id, imageData: Data([4, 5]), fileExtension: "JPG")
        XCTAssertNotEqual(second.artworkAssetID, first.artworkAssetID)
        XCTAssertNil(try assets.fetchAsset(id: firstAsset.id), "the replaced image's asset is gone")
        XCTAssertFalse(store.fileExists(at: firstURL), "and so is its file")

        let secondAsset = try XCTUnwrap(assets.fetchAsset(id: XCTUnwrap(second.artworkAssetID)))
        let removed = try artwork.remove(gameID: game.id)
        XCTAssertNil(removed.artworkAssetID)
        XCTAssertNil(try games.fetchGame(id: game.id)?.artworkAssetID)
        XCTAssertNil(try assets.fetchAsset(id: secondAsset.id))
        XCTAssertFalse(store.fileExists(at: try store.managedURL(relativePath: secondAsset.relativePath)))

        XCTAssertThrowsError(try artwork.set(gameID: game.id, imageData: Data(), fileExtension: "png")) { error in
            XCTAssertEqual(error as? GameArtworkError, .emptyImage)
        }
    }
}

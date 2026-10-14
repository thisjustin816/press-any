import AssetStorage
import EmulatorApplication
import EmulatorDomain
import Foundation
import GRDB
import Importing
import PersistenceGRDB
import XCTest

@MainActor
final class ArtworkPersistenceTests: XCTestCase {
    func testAFailedCommitKeepsThePreviousArtworkFileForReplacementAndRemoval() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("artwork-rollback-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ManagedFileStore(rootURL: root)
        let db = try AppDatabase.inMemory()
        try db.migrate()
        let repos = db.makeRepositories()
        let game = Game(id: UUID(), primaryTitle: "Example", systemFamily: "gameboy", createdAt: .distantPast, modifiedAt: .distantPast)
        try repos.games.insertGame(game)
        let artwork = GameArtwork(games: repos.games, assets: repos.assets, assetStore: store,
            prepareImage: { ($0, $1) }, transactions: repos.transactions, settings: repos.settings)
        let original = try artwork.set(gameID: game.id, imageData: Data([1]), fileExtension: "png")
        let asset = try XCTUnwrap(repos.assets.fetchAsset(id: XCTUnwrap(original.artworkAssetID)))
        let originalURL = try store.managedURL(relativePath: asset.relativePath)
        try await db.writer.write { database in
            try database.execute(sql: """
                CREATE TABLE failed_artwork_commit (
                    game_id TEXT REFERENCES games(id) DEFERRABLE INITIALLY DEFERRED
                );
                CREATE TRIGGER fail_artwork_commit AFTER UPDATE OF artwork_asset_id ON games
                BEGIN INSERT INTO failed_artwork_commit VALUES ('missing-game'); END;
                """)
        }

        XCTAssertThrowsError(try artwork.set(gameID: game.id, imageData: Data([2]), fileExtension: "png"))
        XCTAssertEqual(try repos.games.fetchGame(id: game.id)?.artworkAssetID, original.artworkAssetID)
        XCTAssertTrue(store.fileExists(at: originalURL), "rollback must keep the referenced file")

        XCTAssertThrowsError(try artwork.remove(gameID: game.id))
        XCTAssertEqual(try repos.games.fetchGame(id: game.id)?.artworkAssetID, original.artworkAssetID)
        XCTAssertTrue(store.fileExists(at: originalURL), "failed removal must also keep the file")
    }

    func testFetchedArtworkAndSettingSurviveBackupAndRestore() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("artwork-backup-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ManagedFileStore(rootURL: root.appendingPathComponent("source"))
        let db = try AppDatabase.inMemory()
        try db.migrate()
        let repos = db.makeRepositories()
        let game = Game(id: UUID(), primaryTitle: "Example", systemFamily: "gameboy", createdAt: .distantPast, modifiedAt: .distantPast)
        try repos.games.insertGame(game)
        let provided = ProvidedArtwork(data: Data([1, 2, 3]), fileExtension: "png", provenance: .init(provider: "synthetic",
            sourceURL: URL(string: "https://example.com/art.png")!, fetchedAt: .distantPast, rights: "Synthetic test data"))
        let artwork = GameArtwork(games: repos.games, assets: repos.assets, assetStore: store,
            prepareImage: { ($0, $1) }, transactions: repos.transactions, settings: repos.settings)
        let automatic = AutomaticGameArtwork(games: repos.games, artwork: artwork, settings: repos.settings,
            providers: [PersistenceArtworkProvider(provided: provided)], transactions: repos.transactions)
        let wrote = try await automatic.execute(gameID: game.id,
            lookup: .init(system: .gameBoy, releaseNames: ["Example (World)"], inherited: false))
        XCTAssertTrue(wrote)
        try AutomaticArtworkSetting(store: repos.settings).save(false)
        let archive = try LibraryBackupService(repository: repos.backup, assetStore: store)
            .export(to: root, displayName: "Test", appVersion: "1", appBuild: "1")

        let restoredStore = try ManagedFileStore(rootURL: root.appendingPathComponent("restored"))
        let restoredDB = try AppDatabase.inMemory()
        try restoredDB.migrate()
        let restoredRepos = restoredDB.makeRepositories()
        let backup = LibraryBackupService(repository: restoredRepos.backup, assetStore: restoredStore)
        let prepared = try backup.prepare(from: archive)
        _ = try backup.restore(prepared, review: backup.review(prepared), choices: [:])
        let restored = try XCTUnwrap(restoredRepos.games.fetchGame(id: game.id))
        let asset = try XCTUnwrap(restoredRepos.assets.fetchAsset(id: XCTUnwrap(restored.artworkAssetID)))
        let provenance = try JSONDecoder().decode(ArtworkProvenance.self, from: Data(XCTUnwrap(asset.provenanceJSON).utf8))
        XCTAssertEqual(provenance, provided.provenance)
        XCTAssertEqual(try restoredStore.readData(at: restoredStore.managedURL(relativePath: asset.relativePath)), provided.data)
        XCTAssertFalse(try AutomaticArtworkSetting(store: restoredRepos.settings).load())
    }
}

private struct PersistenceArtworkProvider: ArtworkProvider {
    let provided: ProvidedArtwork
    func artwork(for lookup: ArtworkLookup) async throws -> ProvidedArtwork? { provided }
}

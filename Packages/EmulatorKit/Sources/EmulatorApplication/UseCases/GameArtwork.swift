import EmulatorDomain
import Foundation

public enum GameArtworkError: Error, Equatable {
    case gameNotFound(UUID)
    case emptyImage
}

/// Manually assigned cover art. Each Game holds at most one image, stored as user data; a
/// replaced or removed image is deleted with its asset row.
public struct GameArtwork: Sendable {
    private let games: any GameRepository
    private let assets: any ManagedAssetRepository
    private let assetStore: any AssetStore
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID

    public init(
        games: any GameRepository,
        assets: any ManagedAssetRepository,
        assetStore: any AssetStore,
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.games = games
        self.assets = assets
        self.assetStore = assetStore
        self.now = now
        self.makeID = makeID
    }

    @discardableResult
    public func set(gameID: UUID, imageData: Data, fileExtension: String, originalFilename: String? = nil) throws -> Game {
        guard var game = try games.fetchGame(id: gameID) else {
            throw GameArtworkError.gameNotFound(gameID)
        }
        guard !imageData.isEmpty else { throw GameArtworkError.emptyImage }

        let sha256 = assetStore.hashData(imageData)
        let destination = try assetStore.artworkURL(gameID: gameID, sha256: sha256, extension: fileExtension)
        let relativePath = try assetStore.managedRelativePath(for: destination)
        let previous = try game.artworkAssetID.flatMap { try assets.fetchAsset(id: $0) }
        if previous?.relativePath == relativePath { return game }

        try assetStore.writeDataAtomically(imageData, to: destination)
        let timestamp = now()
        let asset = ManagedAsset(
            id: makeID(),
            kind: .artwork,
            storageClass: .userData,
            contentSHA256: sha256,
            byteLength: Int64(imageData.count),
            relativePath: relativePath,
            originalFilename: originalFilename,
            integrityStatus: .verified,
            createdAt: timestamp
        )
        do {
            try assets.insertAsset(asset)
            game.artworkAssetID = asset.id
            game.modifiedAt = timestamp
            try games.updateGame(game)
        } catch {
            try? assets.deleteAsset(id: asset.id)
            try? assetStore.removeIfExists(destination)
            throw error
        }

        if let previous { assets.discard(previous, files: assetStore) }
        return game
    }

    @discardableResult
    public func remove(gameID: UUID) throws -> Game {
        guard var game = try games.fetchGame(id: gameID) else {
            throw GameArtworkError.gameNotFound(gameID)
        }
        guard let assetID = game.artworkAssetID else { return game }
        let previous = try assets.fetchAsset(id: assetID)
        game.artworkAssetID = nil
        game.modifiedAt = now()
        try games.updateGame(game)
        if let previous { assets.discard(previous, files: assetStore) }
        return game
    }
}

import EmulatorApplication
import Foundation

struct GameplayArtworkTarget {
    let gameID: UUID
    let games: any GameRepository
    let artwork: GameArtwork

    func hasArtwork() throws -> Bool {
        guard let game = try games.fetchGame(id: gameID) else {
            throw GameArtworkError.gameNotFound(gameID)
        }
        return game.artworkAssetID != nil
    }

    func set(_ png: Data) throws {
        _ = try artwork.set(gameID: gameID, imageData: png, fileExtension: "png")
        NotificationCenter.default.post(name: .libraryDidChange, object: nil)
    }
}

/// Keeps the PNG available until the share sheet finishes, including when it is canceled.
final class SharedGameplayScreenshot: Sendable {
    let url: URL
    private let directory: URL

    init(png: Data, temporaryDirectory: URL = FileManager.default.temporaryDirectory) throws {
        directory = temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        url = directory.appendingPathComponent("Screenshot.png")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try png.write(to: url, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    deinit { discard() }

    func discard() {
        try? FileManager.default.removeItem(at: directory)
    }
}

import EmulatorApplication
import EmulatorDomain
import GameIdentity
import UIKit
import XCTest
@testable import PressAny

@MainActor
struct ArtworkTestLibrary {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let container: AppContainer
    let dumps: [KnownDump]

    init(provider: any ArtworkProvider) throws {
        let index = try KnownDumpIndex.bundled()
        let recognized = index.catalog.games.filter { $0.system == .gameBoy && $0.files.contains { !$0.bad } }
        dumps = [try XCTUnwrap(recognized.first), try XCTUnwrap(recognized.dropFirst().first)]
        container = try AppContainer(rootURL: root, artworkProvider: provider)
    }

    func addGame(dump: KnownDump?, marker: UInt8) throws -> Game {
        var game = Game(id: UUID(), primaryTitle: "Artwork Example \(marker)", systemFamily: "gameboy",
            createdAt: .distantPast, modifiedAt: .distantPast)
        try container.repositories.games.insertGame(game)
        game.preferredBuildID = try addBuild(to: game, dump: dump, marker: marker).id
        try container.repositories.games.updateGame(game)
        return game
    }

    func addBuild(to game: Game, dump: KnownDump?, marker: UInt8) throws -> Build {
        // Artwork matching needs identity metadata, without a source ROM file.
        let hash = container.fileStore.hashData(Data([marker]))
        let asset = ManagedAsset(id: UUID(), kind: .sourceImage, storageClass: .source,
            contentSHA256: hash, byteLength: 1, relativePath: "Source/\(hash).gb", createdAt: .distantPast)
        try container.repositories.assets.insertAsset(asset)
        let build = Build(id: UUID(), gameID: game.id, system: .gameBoy, displayName: dump?.name ?? "Unknown",
            imageAssetID: asset.id, imageSHA256: hash, imageSHA1: dump?.files.first { !$0.bad }?.sha1,
            sourceKind: .importedImage, createdAt: .distantPast, modifiedAt: .distantPast)
        try container.repositories.builds.insertBuild(build)
        return build
    }

    static func png() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { context in
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }

    nonisolated static func download(data: Data) -> ProvidedArtwork {
        ProvidedArtwork(data: data, fileExtension: "png", provenance: .init(provider: "test",
            sourceURL: URL(string: "https://example.com/art.png")!, fetchedAt: .distantPast, rights: "Synthetic test data"))
    }

    func removeFiles() {
        do {
            try container.database.writer.close()
            try FileManager.default.removeItem(at: root)
        } catch {
            XCTFail("Artwork fixture cleanup failed: \(error)")
        }
    }
}

actor PendingArtworkProvider: ArtworkProvider {
    private let onRequest: @Sendable (ArtworkLookup, Int) -> Void
    private var pending: [CheckedContinuation<ProvidedArtwork?, any Error>] = []
    private(set) var requests: [ArtworkLookup] = []

    init(onRequest: @escaping @Sendable (ArtworkLookup, Int) -> Void) { self.onRequest = onRequest }

    func artwork(for lookup: ArtworkLookup) async throws -> ProvidedArtwork? {
        try await withCheckedThrowingContinuation { continuation in
            requests.append(lookup)
            pending.append(continuation)
            onRequest(lookup, requests.count)
        }
    }

    func finish(with artwork: ProvidedArtwork) {
        let continuations = pending
        pending.removeAll()
        for continuation in continuations { continuation.resume(returning: artwork) }
    }
}

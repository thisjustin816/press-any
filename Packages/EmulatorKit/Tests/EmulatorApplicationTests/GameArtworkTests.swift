import AssetStorage
import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import XCTest
#if canImport(ImageIO)
import CoreGraphics
import ImageIO
#endif

final class GameArtworkTests: XCTestCase {
    func testSettingReplacingAndRemovingArtworkKeepsOneImage() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let game = Game(id: UUID(), primaryTitle: "Art", systemFamily: "gameboy", createdAt: now, modifiedAt: now)
        let games = InMemoryGameRepository([game])
        let assets = InMemoryAssetRepository()
        let store = try ManagedFileStore(rootURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("emulatorkit-artwork-tests-\(UUID().uuidString)", isDirectory: true))
        // The test bytes aren't images, so they are stored as given.
        let artwork = GameArtwork(games: games, assets: assets, assetStore: store, prepareImage: { ($0, $1) }, now: { now })

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

    func testAnOversizedImageIsRefusedBeforeItIsRead() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let game = Game(id: UUID(), primaryTitle: "Art", systemFamily: "gameboy", createdAt: now, modifiedAt: now)
        let games = InMemoryGameRepository([game])
        let store = try ManagedFileStore(rootURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("emulatorkit-artwork-tests-\(UUID().uuidString)", isDirectory: true))
        let artwork = GameArtwork(games: games, assets: InMemoryAssetRepository(), assetStore: store, now: { now })
        let tooLarge = ImportSizeError.fileTooLarge(limit: ImportSizeLimit.artwork.bytes)

        let huge = try ImportTestFiles.sparse(
            at: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png"),
            byteCount: UInt64(ImportSizeLimit.artwork.bytes) + 1
        )
        XCTAssertThrowsError(try artwork.set(gameID: game.id, fileAt: huge)) {
            XCTAssertEqual($0 as? ImportSizeError, tooLarge)
        }
        let oversized = Data(count: Int(ImportSizeLimit.artwork.bytes) + 1)
        XCTAssertThrowsError(try artwork.set(gameID: game.id, imageData: oversized, fileExtension: "png")) {
            XCTAssertEqual($0 as? ImportSizeError, tooLarge)
        }
        XCTAssertNil(try games.fetchGame(id: game.id)?.artworkAssetID)
    }

    func testThePreparedImageIsWhatIsStored() throws {
        let fixture = try ArtworkFixture()
        let artwork = fixture.artwork { data, fileExtension in
            XCTAssertEqual(data, Data([1]))
            XCTAssertEqual(fileExtension, "jpg")
            return (Data([9, 9]), "png")
        }

        let game = try artwork.set(gameID: fixture.game.id, imageData: Data([1]), fileExtension: "jpg")
        let asset = try XCTUnwrap(fixture.assets.fetchAsset(id: XCTUnwrap(game.artworkAssetID)))
        XCTAssertEqual(try fixture.store.readData(at: fixture.store.managedURL(relativePath: asset.relativePath)), Data([9, 9]))
        XCTAssertEqual(URL(fileURLWithPath: asset.relativePath).pathExtension, "png")
        XCTAssertEqual(asset.byteLength, 2)

        let refusing = fixture.artwork { _, _ in throw GameArtworkError.unreadableImage }
        XCTAssertThrowsError(try refusing.set(gameID: fixture.game.id, imageData: Data([2]), fileExtension: "png")) {
            XCTAssertEqual($0 as? GameArtworkError, .unreadableImage)
        }
        XCTAssertEqual(try fixture.games.fetchGame(id: fixture.game.id)?.artworkAssetID, asset.id, "the old image stays")
    }

    func testALargeImageIsStoredDownscaled() throws {
        #if canImport(ImageIO)
        let fixture = try ArtworkFixture()
        let artwork = fixture.artwork(ArtworkImage.downscaled)

        let game = try artwork.set(gameID: fixture.game.id, imageData: try pngImage(width: 2048, height: 1024), fileExtension: "jpg")
        let asset = try XCTUnwrap(fixture.assets.fetchAsset(id: XCTUnwrap(game.artworkAssetID)))
        XCTAssertEqual(URL(fileURLWithPath: asset.relativePath).pathExtension, "png")
        let stored = try fixture.store.readData(at: fixture.store.managedURL(relativePath: asset.relativePath))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(stored as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, ArtworkImage.maximumPixelSize)
        XCTAssertEqual(image.height, ArtworkImage.maximumPixelSize / 2)
        #else
        throw XCTSkip("Downscaling needs ImageIO.")
        #endif
    }

    func testAFileThatIsNotAnImageIsRefused() throws {
        #if canImport(ImageIO)
        let fixture = try ArtworkFixture()
        let artwork = fixture.artwork(ArtworkImage.downscaled)

        XCTAssertThrowsError(try artwork.set(gameID: fixture.game.id, imageData: Data("not an image".utf8), fileExtension: "png")) {
            XCTAssertEqual($0 as? GameArtworkError, .unreadableImage)
        }
        XCTAssertNil(try fixture.games.fetchGame(id: fixture.game.id)?.artworkAssetID)
        #else
        throw XCTSkip("Decoding needs ImageIO.")
        #endif
    }
}

private struct ArtworkFixture {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let game: Game
    let games: InMemoryGameRepository
    let assets = InMemoryAssetRepository()
    let store: ManagedFileStore

    init() throws {
        game = Game(id: UUID(), primaryTitle: "Art", systemFamily: "gameboy", createdAt: now, modifiedAt: now)
        games = InMemoryGameRepository([game])
        store = try ManagedFileStore(rootURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("emulatorkit-artwork-tests-\(UUID().uuidString)", isDirectory: true))
    }

    func artwork(_ prepareImage: @escaping ArtworkPreparation) -> GameArtwork {
        GameArtwork(games: games, assets: assets, assetStore: store, prepareImage: prepareImage, now: { [now] in now })
    }
}

#if canImport(ImageIO)
private func pngImage(width: Int, height: Int) throws -> Data {
    let context = try XCTUnwrap(CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try XCTUnwrap(context.makeImage())
    let output = NSMutableData()
    let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output as CFMutableData, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return output as Data
}
#endif

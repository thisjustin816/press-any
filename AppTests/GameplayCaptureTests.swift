import CoreGraphics
import EmulationCore
import EmulatorDomain
import Foundation
import ImageIO
import XCTest
@testable import PressAny

final class GameplayCaptureTests: XCTestCase {
    func testPNGKeepsTheNativeFrameSizeAndOpaqueColors() throws {
        let frame = EmulatorVideoFrame(
            width: 2, height: 2,
            bgra8888: Data([0, 0, 255, 0, 0, 255, 0, 0, 0, 0, 255, 0, 0, 255, 0, 0]),
            emulatedNanoseconds: 1
        )
        let png = try PNGFrameEncoder().encode(frame)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), 1)
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 2)
        XCTAssertEqual(image.height, 2)
        var pixels = [UInt8](repeating: 0, count: 16)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        XCTAssertEqual(pixels, [255, 0, 0, 255, 0, 255, 0, 255, 255, 0, 0, 255, 0, 255, 0, 255])
    }

    func testIncompleteAndEmptyFramesCannotBeExported() {
        for frame in [
            EmulatorVideoFrame(width: 160, height: 144, bgra8888: Data([1, 2, 3]), emulatedNanoseconds: 1),
            EmulatorVideoFrame(width: 0, height: 0, bgra8888: Data(), emulatedNanoseconds: 1),
        ] {
            XCTAssertThrowsError(try PNGFrameEncoder().encode(frame))
        }
    }

    func testSharingKeepsSeparateFilesAndRemovesOnlyItsOwnTemporaryDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try SharedGameplayScreenshot(png: Data([1]), temporaryDirectory: root)
        var second: SharedGameplayScreenshot? = try SharedGameplayScreenshot(png: Data([2]), temporaryDirectory: root)
        let secondURL = try XCTUnwrap(second).url
        XCTAssertEqual(first.url.pathExtension, "png")
        XCTAssertNotEqual(first.url, secondURL)
        XCTAssertEqual(try Data(contentsOf: first.url), Data([1]))
        XCTAssertEqual(try Data(contentsOf: secondURL), Data([2]))
        first.discard()
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.url.deletingLastPathComponent().path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondURL.path))
        second = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondURL.deletingLastPathComponent().path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
    }

    @MainActor
    func testCaptureUsesOnlyTheChosenGamesExistingArtworkStorage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try AppContainer(rootURL: root)
        let now = Date()
        let game = Game(id: UUID(), primaryTitle: "Capture", systemFamily: "gameboy", createdAt: now, modifiedAt: now)
        let other = Game(id: UUID(), primaryTitle: "Other", systemFamily: "gameboy", createdAt: now, modifiedAt: now)
        try container.repositories.games.insertGame(game)
        try container.repositories.games.insertGame(other)
        let target = GameplayArtworkTarget(gameID: game.id, games: container.repositories.games, artwork: container.gameArtwork)
        XCTAssertFalse(try target.hasArtwork())
        let frame = EmulatorVideoFrame(width: 160, height: 144, bgra8888: Data(count: 160 * 144 * 4), emulatedNanoseconds: 1)
        try target.set(PNGFrameEncoder().encode(frame))
        XCTAssertTrue(try target.hasArtwork())
        let saved = try XCTUnwrap(container.repositories.games.fetchGame(id: game.id))
        let url = try XCTUnwrap(container.artworkURL(for: saved))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 160)
        XCTAssertEqual(image.height, 144)
        XCTAssertNil(try container.repositories.games.fetchGame(id: other.id)?.artworkAssetID)
        XCTAssertThrowsError(try target.set(Data([1, 2])))
        XCTAssertEqual(try container.repositories.games.fetchGame(id: game.id)?.artworkAssetID, saved.artworkAssetID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}

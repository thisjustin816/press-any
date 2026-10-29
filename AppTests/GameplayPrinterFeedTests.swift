import EmulationCore
import Foundation
import XCTest
@testable import PressAny

final class GameplayPrinterFeedTests: XCTestCase {
    func testOverlongPaperKeepsLaterPrintsInTheSameDelivery() throws {
        let feed = GameplayPrinterFeed()
        let section = try PrinterOutput(height: 200, luminance: Data(count: 32000), topMargin: 0, bottomMargin: 0, exposure: 64)
        try feed.receive(Array(repeating: section, count: 10))
        let next = try PrinterOutput(height: 1, luminance: Data(repeating: 170, count: 160), topMargin: 1, bottomMargin: 3, exposure: 64)
        XCTAssertThrowsError(try feed.receive([section, next]))
        XCTAssertEqual(feed.slips.count, 2)
        XCTAssertEqual(feed.slips[0].feedHeight, 2000)
        XCTAssertEqual(feed.slips.last?.sections, [next])
    }

    func testChangesNameNewSlipsAndSlipsThatGainedPaperOnly() throws {
        let feed = GameplayPrinterFeed()
        let attached = try PrinterOutput(height: 16, luminance: Data(count: 2560), topMargin: 0, bottomMargin: 0, exposure: 64)
        let separate = try PrinterOutput(height: 8, luminance: Data(count: 1280), topMargin: 1, bottomMargin: 3, exposure: 64)
        try feed.receive([separate])
        try feed.receive([attached])
        let before = feed.slips
        try feed.receive([attached])
        XCTAssertEqual(GameplayPrinterFeed.changes(from: before, to: feed.slips).map(\.id), [before[1].id])
        let grown = feed.slips
        try feed.receive([separate])
        XCTAssertEqual(GameplayPrinterFeed.changes(from: grown, to: feed.slips).map(\.id), [feed.slips[2].id])
    }

    func testPrintsAreKeptInOrderAndOneFailureIsReportedOnce() throws {
        final class Saved: @unchecked Sendable {
            let lock = NSLock()
            var ids: [UUID] = []
            var failures = 0
        }
        let saved = Saved()
        let first = PrinterSlip(output: try PrinterOutput(height: 8, luminance: Data(count: 1280), topMargin: 1, bottomMargin: 3, exposure: 64))
        let second = PrinterSlip(output: try PrinterOutput(height: 8, luminance: Data(count: 1280), topMargin: 1, bottomMargin: 3, exposure: 64))
        let prints = GameplayPrints(gameID: nil) { slip in
            struct Refused: Error {}
            saved.lock.withLock { saved.ids.append(slip.id) }
            throw Refused()
        }
        prints.keep([first, second]) { saved.lock.withLock { saved.failures += 1 } }
        prints.keep([first]) { saved.lock.withLock { saved.failures += 1 } }
        prints.finish()
        XCTAssertEqual(saved.lock.withLock { saved.ids }, [first.id, second.id, first.id])
        XCTAssertEqual(saved.lock.withLock { saved.failures }, 1)
    }

    func testADiscardedPrintIsRemovedAfterEarlierSavesAndNeverSavedAgain() throws {
        final class Kept: @unchecked Sendable {
            let lock = NSLock()
            var steps: [String] = []
        }
        let kept = Kept()
        let slip = PrinterSlip(output: try PrinterOutput(height: 8, luminance: Data(count: 1280), topMargin: 1, bottomMargin: 3, exposure: 64))
        let prints = GameplayPrints(
            gameID: nil,
            save: { slip in kept.lock.withLock { kept.steps.append("save \(slip.id)") } },
            discard: { id in kept.lock.withLock { kept.steps.append("discard \(id)") } }
        )
        prints.keep([slip]) {}
        prints.discard(slip.id) {}
        prints.keep([slip]) {}
        prints.finish()
        XCTAssertEqual(kept.lock.withLock { kept.steps }, ["save \(slip.id)", "discard \(slip.id)"])
    }

    func testAThumbnailShowsThePaperWithItsMargins() throws {
        let slip = PrinterSlip(output: try PrinterOutput(height: 8, luminance: Data(count: 1280), topMargin: 1, bottomMargin: 2, exposure: 64))
        let image = try XCTUnwrap(PrintThumbnail.image(for: slip))
        XCTAssertEqual(image.size, CGSize(width: 160, height: 8 + 3 * 8))
    }

    func testThePrinterBackgroundShowsATallPrintAboveThePrinter() throws {
        let output = try PrinterOutput(height: 160, luminance: Data(repeating: 0xFF, count: 160 * 160), topMargin: 1, bottomMargin: 3, exposure: 64)
        let image = try XCTUnwrap(PrinterScene.render(PrinterSlip(output: output))?.cgImage)
        // The paper starts 40 px down, after its render's 96 px inset; 60 px into it is above the
        // printer, whose lid starts 546 px down for this print.
        var pixel = [UInt8](repeating: 0, count: 4)
        try pixel.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            let y = 40 + 96 + 60
            context.draw(image, in: CGRect(x: -image.width / 2, y: y - image.height + 1, width: image.width, height: image.height))
        }
        XCTAssertGreaterThan(pixel[0], 200, "paper, not the dark background behind the printer")
    }

    func testEndingARollPreservesItsPaperAndSeparatesTheNextDelivery() throws {
        let feed = GameplayPrinterFeed()
        let section = try PrinterOutput(height: 16, luminance: Data(count: 2560), topMargin: 0, bottomMargin: 0, exposure: 64)
        try feed.receive([section])
        let first = try XCTUnwrap(feed.slips.first)
        feed.endRoll()
        try feed.receive([section])
        XCTAssertEqual(feed.slips.count, 2)
        XCTAssertEqual(feed.slips[0], first)
        XCTAssertNotEqual(feed.slips[1].id, first.id)
    }
}

final class GameplayPrinterLogTests: XCTestCase {
    func testTheLogKeepsTheNewestAndReadsAsText() {
        let log = GameplayPrinterLog()
        let poll = PrinterEvent(time: 0.5, kind: .packet, command: 15, compressed: false, length: 0, status: 0)
        log.append(Array(repeating: poll, count: GameplayPrinterLog.capacity))
        let ignored = PrinterEvent(time: 1.25, kind: .packet, command: 4, compressed: false, length: 640, status: 0x0E,
                                   ignoredWhilePrinting: true)
        log.append([ignored])
        XCTAssertEqual(log.events.count, GameplayPrinterLog.capacity)
        XCTAssertEqual(log.events.last, ignored)
        XCTAssertEqual(GameplayPrinterLog.text([ignored]),
                       "   1.250 s  Data, 640 bytes → 0x0E busy, image full, unprocessed data\n           Data sent while printing was ignored.")
    }
}

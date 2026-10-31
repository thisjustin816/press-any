import EmulationCore
import Foundation
import XCTest

final class PrinterTests: XCTestCase {
    func testRejectsInvalidDimensionsAndFeedValues() throws {
        for height in [0, 201, Int.max] {
            XCTAssertThrowsError(try PrinterOutput(height: height, luminance: Data(), topMargin: 0, bottomMargin: 0, exposure: 64))
        }
        for count in [0, 159, 161] {
            XCTAssertThrowsError(try PrinterOutput(height: 1, luminance: Data(count: count), topMargin: 0, bottomMargin: 0, exposure: 64))
        }
        for margin in [-1, 16] {
            XCTAssertThrowsError(try PrinterOutput(height: 1, luminance: Data(count: 160), topMargin: margin, bottomMargin: 0, exposure: 64))
            XCTAssertThrowsError(try PrinterOutput(height: 1, luminance: Data(count: 160), topMargin: 0, bottomMargin: margin, exposure: 64))
        }
        XCTAssertThrowsError(try PrinterOutput(height: 1, luminance: Data(count: 160), topMargin: 0, bottomMargin: 0, exposure: 128))
    }

    func testSlipPreservesEveryPrintPixelAtIntegerScale() throws {
        let levels: [UInt8] = [255, 170, 85, 0]
        let output = try PrinterOutput(height: 16, luminance: Data((0..<2560).map { levels[$0 % 4] }),
                                       topMargin: 2, bottomMargin: 3, exposure: 64)
        let image = PrinterSlipRenderer.render(output)
        XCTAssertEqual(image.width, 960)
        XCTAssertEqual(image.height, (56 + 72) * 4)
        let expected: [[UInt8]] = [[245, 249, 250, 255], [172, 175, 176, 255], [99, 102, 103, 255], [27, 29, 30, 255]]
        for y in 0..<16 {
            for x in 0..<160 {
                for sy in 0..<4 {
                    for sx in 0..<4 {
                        let row = PrinterSlipRenderer.printOriginY + 16 * 4 + y * 4 + sy
                        let col = PrinterSlipRenderer.printOriginX + x * 4 + sx
                        let i = (row * image.width + col) * 4
                        XCTAssertEqual(Array(image.bgra8888[i..<i + 4]), expected[x % 4])
                    }
                }
            }
        }
        XCTAssertEqual(image, PrinterSlipRenderer.render(output))
    }

    func testPhotographicBackgroundPreservesThePrintAndRejectsInvalidImages() throws {
        for size in [0, -1, 1537, Int.max] {
            XCTAssertThrowsError(try PrinterBackgroundImage(width: size, height: 1, bgra8888: Data()))
        }
        XCTAssertThrowsError(try PrinterBackgroundImage(width: 1, height: 1, bgra8888: Data(count: 3)))
        let texture = try PrinterBackgroundImage(width: 2, height: 1, bgra8888: Data([10, 20, 30, 255, 70, 80, 90, 255]))
        let output = try PrinterOutput(height: 1, luminance: Data(count: 160), topMargin: 0, bottomMargin: 0, exposure: 64)
        let image = PrinterSlipRenderer.render(PrinterSlip(output: output), image: texture)
        let transparent = PrinterSlipRenderer.render(output)
        XCTAssertEqual(Array(image.bgra8888.prefix(4)), [10, 20, 30, 255])
        let origin = (PrinterSlipRenderer.printOriginY * image.width + PrinterSlipRenderer.printOriginX) * 4
        XCTAssertEqual(image.bgra8888[origin..<origin + 160 * 4 * 4], transparent.bgra8888[origin..<origin + 160 * 4 * 4])
        XCTAssertEqual(image, PrinterSlipRenderer.render(PrinterSlip(output: output), image: texture))
    }

    func testDefaultIsTransparent() throws {
        let output = try PrinterOutput(height: 1, luminance: Data(count: 160), topMargin: 0, bottomMargin: 0, exposure: 64)
        XCTAssertEqual(PrinterBackground.defaultValue, .transparent)
        XCTAssertEqual(PrinterSlipRenderer.render(output).bgra8888[3], 0)
    }

    func testBackgroundChangesOnlyTheAreaBehindThePaper() throws {
        let output = try PrinterOutput(height: 1, luminance: Data(count: 160), topMargin: 0, bottomMargin: 0, exposure: 64)
        let light = PrinterSlipRenderer.render(output, background: .light)
        let dark = PrinterSlipRenderer.render(output, background: .dark)
        let clear = PrinterSlipRenderer.render(output, background: .transparent)
        XCTAssertEqual(clear.bgra8888[3], 0)
        XCTAssertEqual(light.bgra8888[3], 255)
        XCTAssertEqual(dark.bgra8888[3], 255)
        XCTAssertNotEqual(light.bgra8888.prefix(4), dark.bgra8888.prefix(4))
        let center = (PrinterSlipRenderer.printOriginY * light.width + PrinterSlipRenderer.printOriginX) * 4
        XCTAssertEqual(light.bgra8888[center..<center + 4], dark.bgra8888[center..<center + 4])
        XCTAssertEqual(light.bgra8888[center..<center + 4], clear.bgra8888[center..<center + 4])
    }

    func testFeedJoinsAttachedPaperAndRespectsNewRolls() throws {
        func output(top: Int = 0, bottom: Int = 0) throws -> PrinterOutput {
            try PrinterOutput(height: 16, luminance: Data(count: 2560), topMargin: top, bottomMargin: bottom, exposure: 64)
        }
        var feed = PrinterFeed()
        try feed.receive(output(top: 1))
        let id = try XCTUnwrap(feed.slips.first).id
        try feed.receive(output(bottom: 2))
        XCTAssertEqual(feed.slips.count, 1)
        XCTAssertEqual(feed.slips[0].id, id)
        XCTAssertEqual(feed.slips[0].feedHeight, 56)
        try feed.receive(output())
        XCTAssertEqual(feed.slips.count, 2)
        feed.endRoll()
        try feed.receive(output())
        XCTAssertEqual(feed.slips.count, 3)
        try feed.receive(output(top: 1))
        XCTAssertEqual(feed.slips.count, 4)
    }

    /// A Print's copies come out as one strip: its top margin once, then each copy with its bottom
    /// margin after it.
    func testCopiesOfOnePrintFeedOneStrip() throws {
        func copy(top: Int = 0, bottom: Int = 0, follows: Bool = false) throws -> PrinterOutput {
            try PrinterOutput(height: 16, luminance: Data(count: 2560), topMargin: top, bottomMargin: bottom,
                              exposure: 64, followsCopy: follows)
        }
        for count in [2, 3] {
            var feed = PrinterFeed()
            try feed.receive(copy(top: 1, bottom: 3))
            for _ in 1..<count { try feed.receive(copy(bottom: 3, follows: true)) }
            XCTAssertEqual(feed.slips.count, 1)
            let slip = feed.slips[0]
            XCTAssertEqual(slip.sections.map(\.topMargin), [1] + Array(repeating: 0, count: count - 1))
            XCTAssertEqual(slip.sections.map(\.bottomMargin), Array(repeating: 3, count: count))
            XCTAssertEqual(slip.feedHeight, 8 + count * (16 + 24))

            let image = PrinterSlipRenderer.render(slip)
            XCTAssertEqual(image.height, (8 + count * 40 + 72) * PrinterSlipRenderer.scale)
            let ink: [UInt8] = [27, 29, 30, 255]
            for index in 0..<count {
                let first = 36 + 8 + index * 40
                for (row, printed) in [(first - 1, false), (first, true), (first + 15, true), (first + 16, false)] {
                    let i = (row * PrinterSlipRenderer.scale * image.width + PrinterSlipRenderer.printOriginX) * 4
                    XCTAssertEqual(Array(image.bgra8888[i..<i + 4]) == ink, printed, "copy \(index), row \(row)")
                }
            }

            try feed.receive(copy(top: 1, bottom: 3))
            XCTAssertEqual(feed.slips.count, 2, "another Print feeds its own top margin onto new paper")
            try feed.receive(copy(bottom: 3))
            XCTAssertEqual(feed.slips.count, 3, "another Print after a bottom margin starts a new slip")
            feed.endRoll()
            try feed.receive(copy(bottom: 3, follows: true))
            XCTAssertEqual(feed.slips.count, 4, "a copy after a reset starts a new slip")
        }
    }

    func testDiscardingTheNewestSlipKeepsLaterPaperOffTheSlipBeforeIt() throws {
        let attached = try PrinterOutput(height: 16, luminance: Data(count: 2560), topMargin: 0, bottomMargin: 0, exposure: 64)
        var feed = PrinterFeed()
        try feed.receive(attached)
        feed.endRoll()
        try feed.receive(attached)
        let kept = feed.slips[0], discarded = feed.slips[1]
        feed.discard(id: discarded.id)
        XCTAssertEqual(feed.slips, [kept])
        try feed.receive(attached)
        XCTAssertEqual(feed.slips.count, 2)
        XCTAssertEqual(feed.slips[0], kept, "the paper after a discard starts a new slip")
        feed.discard(id: kept.id)
        try feed.receive(attached)
        XCTAssertEqual(feed.slips.count, 1, "discarding an older slip leaves the newest one attached")
        XCTAssertEqual(feed.slips[0].sections.count, 2)
    }

    func testFeedBoundsMemoryAndRefusesOverlongPaperWithoutDiscardingIt() throws {
        let output = try PrinterOutput(height: 200, luminance: Data(count: 32000), topMargin: 0, bottomMargin: 0, exposure: 64)
        var feed = PrinterFeed()
        for _ in 0..<10 { try feed.receive(output) }
        XCTAssertEqual(feed.slips[0].feedHeight, 2000)
        XCTAssertThrowsError(try feed.receive(output))
        XCTAssertEqual(feed.slips[0].feedHeight, 2000)
        for _ in 0..<12 { feed.endRoll(); try feed.receive(output) }
        XCTAssertEqual(feed.slips.count, PrinterFeed.retention)
        XCTAssertEqual(feed.slips[0].feedHeight, 200)
    }
}

import CoreGraphics
import EmulationCore
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import PressAny

final class PrinterBackgroundStoreTests: XCTestCase {
    private func fixture() throws -> Data {
        try PNGFrameEncoder().encode(EmulatorVideoFrame(width: 2, height: 2,
            bgra8888: Data([0, 0, 255, 255, 0, 255, 0, 255, 255, 0, 0, 255, 255, 255, 255, 255]),
            emulatedNanoseconds: 0))
    }

    func testDecodePreservesImageOrientationAndRefusesInvalidData() throws {
        let decoded = try PrinterBackgroundStore.decode(fixture())
        XCTAssertEqual(decoded.width, 2)
        XCTAssertEqual(decoded.height, 2)
        XCTAssertEqual(Array(decoded.bgra8888.prefix(4)), [0, 0, 255, 255])
        XCTAssertThrowsError(try PrinterBackgroundStore.decode(Data([0, 1, 2])))
        XCTAssertThrowsError(try PrinterBackgroundStore.decode(Data(count: PrinterBackgroundStore.maximumBytes + 1)))
    }

    func testImportedPhotoMetadataIsRemoved() throws {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(fixture() as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyGPSDictionary: [
            kCGImagePropertyGPSLatitude: 37.0, kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 122.0, kCGImagePropertyGPSLongitudeRef: "W",
        ]] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let tagged = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let taggedProperties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(tagged, 0, nil) as? [CFString: Any])
        XCTAssertNotNil(taggedProperties[kCGImagePropertyGPSDictionary])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try PrinterBackgroundStore(directory: directory).save(data as Data)
        let saved = try XCTUnwrap(CGImageSourceCreateWithURL(directory.appendingPathComponent("custom.jpg") as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(saved, 0, nil) as? [CFString: Any])
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
    }

    func testReopenFailedReplacementAndRemovalPreserveTheSavedBackground() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PrinterBackgroundStore(directory: directory)
        XCTAssertNil(try store.load())
        let saved = try store.save(fixture())
        let reopened = try XCTUnwrap(PrinterBackgroundStore(directory: directory).load())
        XCTAssertEqual(reopened.bgra8888, saved.bgra8888)
        XCTAssertThrowsError(try store.save(Data([9])))
        XCTAssertEqual(try store.load()?.bgra8888, saved.bgra8888)
        let url = directory.appendingPathComponent("custom.jpg")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        try store.remove()
        XCTAssertNil(try store.load())
        try store.remove()
    }

    func testFileImportRejectsLinksAndBundledWoodDecodes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let original = directory.appendingPathComponent("original.png")
        let link = directory.appendingPathComponent("link.png")
        try fixture().write(to: original)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
        XCTAssertThrowsError(try PrinterBackgroundStore.readFile(link))
        XCTAssertEqual(try PrinterBackgroundStore.readFile(original), try fixture())
        let photo = try PrinterBackgroundStore.wood(bundle: Bundle(for: AppDelegate.self))
        XCTAssertEqual(photo.width, 1024)
        XCTAssertEqual(photo.height, 1024)
    }
}

import Foundation
import XCTest
#if canImport(ImageIO)
import CoreGraphics
import ImageIO
import EmulatorApplication

final class ImportedImageTests: XCTestCase {
    func testSharedDecoderUsesEachCallersSizeAndAppliesOrientation() throws {
        let data = try fixture(width: 2048, height: 1024, properties: [kCGImagePropertyOrientation: 6])
        let cover = try ImportedImage.decode(data, maximumPixelSize: 1024)
        let background = try ImportedImage.decode(data, maximumPixelSize: 1536, maximumSourcePixels: 100_000_000)
        XCTAssertEqual(cover.width, 512)
        XCTAssertEqual(cover.height, 1024)
        XCTAssertEqual(background.width, 768)
        XCTAssertEqual(background.height, 1536)
        XCTAssertThrowsError(try ImportedImage.decode(data, maximumPixelSize: 1536, maximumSourcePixels: 100))
        XCTAssertThrowsError(try ImportedImage.decode(Data([0, 1]), maximumPixelSize: 1024))
    }

    func testPNGPreservesTransparencyAndJPEGFlattensOntoWhite() throws {
        let image = try ImportedImage.decode(fixture(width: 2, height: 2), maximumPixelSize: 2)
        for format in [ImportedImage.Format.png, .jpeg] {
            let data = try ImportedImage.encode(image, format: format)
            let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            XCTAssertEqual(CGImageSourceGetType(source) as String?, format == .png ? "public.png" : "public.jpeg")
            let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let context = try bitmap(width: 2, height: 2)
            context.draw(decoded, in: CGRect(x: 0, y: 0, width: 2, height: 2))
            let pixel = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
            if format == .png {
                XCTAssertEqual(pixel[3], 0)
            } else {
                XCTAssertEqual(pixel[3], 255)
                for channel in 0..<3 { XCTAssertGreaterThanOrEqual(pixel[channel], 250) }
            }
        }
    }

    func testBothEncodersDiscardGPSMetadata() throws {
        let data = try fixture(width: 2, height: 2, properties: [kCGImagePropertyGPSDictionary: [
            kCGImagePropertyGPSLatitude: 37.0, kCGImagePropertyGPSLatitudeRef: "N",
        ]])
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertNotNil(properties[kCGImagePropertyGPSDictionary])
        let image = try ImportedImage.decode(data, maximumPixelSize: 1024)
        for format in [ImportedImage.Format.png, .jpeg] {
            let normalized = try ImportedImage.encode(image, format: format)
            let output = try XCTUnwrap(CGImageSourceCreateWithData(normalized as CFData, nil))
            let saved = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(output, 0, nil) as? [CFString: Any])
            XCTAssertNil(saved[kCGImagePropertyGPSDictionary])
        }
    }

    private func bitmap(width: Int, height: Int) throws -> CGContext {
        try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
    }

    private func fixture(width: Int, height: Int, properties: [CFString: Any] = [:]) throws -> Data {
        let context = try bitmap(width: width, height: height)
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        // TIFF carries orientation, GPS and alpha in the same fixture.
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.tiff" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
#endif

#if canImport(ImageIO)
import CoreGraphics
import ImageIO
#endif
import Foundation

/// Turns picked artwork into the bytes that are stored, and their file extension.
public typealias ArtworkPreparation = @Sendable (_ data: Data, _ fileExtension: String) throws -> (data: Data, fileExtension: String)

public enum ArtworkImage {
    /// The longest edge stored artwork can have, in pixels.
    public static let maximumPixelSize = 1024

    /// Decodes the image and stores it as PNG, downscaled to `maximumPixelSize` when larger. Library
    /// views load artwork at full size each time they show it, so a huge image costs memory on
    /// every display. Without ImageIO, which only test hosts lack, the bytes are kept as given.
    public static func downscaled(_ data: Data, fileExtension: String) throws -> (data: Data, fileExtension: String) {
        #if canImport(ImageIO)
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            throw GameArtworkError.unreadableImage
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, "public.png" as CFString, 1, nil) else {
            throw GameArtworkError.unreadableImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw GameArtworkError.unreadableImage }
        return (output as Data, "png")
        #else
        return (data, fileExtension)
        #endif
    }
}

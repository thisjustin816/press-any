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
        do {
            let image = try ImportedImage.decode(data, maximumPixelSize: maximumPixelSize)
            return (try ImportedImage.encode(image, format: .png), "png")
        } catch {
            throw GameArtworkError.unreadableImage
        }
        #else
        return (data, fileExtension)
        #endif
    }
}

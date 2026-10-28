#if canImport(ImageIO)
import CoreGraphics
import Foundation
import ImageIO

/// Image processing shared by cover art and printer backgrounds. Callers bound input bytes
/// before decoding and choose their own storage size and format.
public enum ImportedImage {
    public enum ImageError: Error { case unreadableImage }
    public enum Format { case png, jpeg }

    public static func decode(_ data: Data, maximumPixelSize: Int, maximumSourcePixels: Int? = nil) throws -> CGImage {
        guard maximumPixelSize > 0,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw ImageError.unreadableImage
        }
        if let limit = maximumSourcePixels {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, Double(width) * Double(height) <= Double(limit) else {
                throw ImageError.unreadableImage
            }
        }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
        ] as CFDictionary) else { throw ImageError.unreadableImage }
        return image
    }

    /// Encodes only pixels, discarding source metadata. JPEG flattens transparency onto white.
    public static func encode(_ image: CGImage, format: Format) throws -> Data {
        let outputImage: CGImage
        let type: CFString
        let properties: CFDictionary?
        switch format {
        case .png:
            outputImage = image
            type = "public.png" as CFString
            properties = nil
        case .jpeg:
            guard let context = CGContext(data: nil, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw ImageError.unreadableImage }
            let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(bounds)
            context.draw(image, in: bounds)
            guard let flattened = context.makeImage() else { throw ImageError.unreadableImage }
            outputImage = flattened
            type = "public.jpeg" as CFString
            properties = [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, type, 1, nil) else {
            throw ImageError.unreadableImage
        }
        CGImageDestinationAddImage(destination, outputImage, properties)
        guard CGImageDestinationFinalize(destination) else { throw ImageError.unreadableImage }
        return output as Data
    }
}
#endif

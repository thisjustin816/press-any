import CoreGraphics
import EmulationCore
import EmulationSession
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Encodes a game frame as a PNG at its own size, for save-state thumbnails.
struct PNGFrameEncoder: FrameImageEncoding {
    enum EncodingError: Error {
        case unreadableFrame
        case encoderFailed
    }

    let fileExtension = "png"

    func encode(_ frame: EmulatorVideoFrame) throws -> Data {
        // The core's BGRA is little-endian ARGB with alpha first; the picture is opaque.
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue
        guard frame.bgra8888.count >= frame.width * frame.height * 4,
              let provider = CGDataProvider(data: frame.bgra8888 as CFData),
              let image = CGImage(
                  width: frame.width,
                  height: frame.height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: frame.width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              )
        else { throw EncodingError.unreadableFrame }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw EncodingError.encoderFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw EncodingError.encoderFailed }
        return output as Data
    }
}

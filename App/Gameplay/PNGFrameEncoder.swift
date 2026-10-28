import CoreGraphics
import EmulationCore
import EmulationSession
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Encodes a game frame as a PNG at its own size.
struct PNGFrameEncoder: FrameImageEncoding {
    enum EncodingError: Error {
        case unreadableFrame
        case encoderFailed
    }

    let fileExtension = "png"
    var preservesAlpha = false

    func encode(_ frame: EmulatorVideoFrame) throws -> Data {
        // Core frames are opaque; rendered paper also uses premultiplied alpha at its edges.
        let alpha: CGImageAlphaInfo = preservesAlpha ? .premultipliedFirst : .noneSkipFirst
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | alpha.rawValue
        guard frame.width > 0, frame.height > 0,
              frame.bgra8888.count >= frame.width * frame.height * 4,
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

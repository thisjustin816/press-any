import Foundation

/// A row-major 128 by 112 sensor image, with interleaved red, green and blue bytes per pixel.
public struct CameraFrame: Equatable, Sendable {
    public static let width = 128
    public static let height = 112
    public let rgb888: Data

    public enum ValidationError: Error { case invalidByteCount }

    public init(luminance: Data) throws {
        guard luminance.count == Self.width * Self.height else {
            throw ValidationError.invalidByteCount
        }
        var rgb = Data(capacity: luminance.count * 3)
        for value in luminance { rgb.append(contentsOf: [value, value, value]) }
        self.rgb888 = rgb
    }

    public init(rgb888: Data) throws {
        guard rgb888.count == Self.width * Self.height * 3 else {
            throw ValidationError.invalidByteCount
        }
        self.rgb888 = rgb888
    }
}

public protocol CameraCapability: AnyObject {
    /// Whether the loaded cartridge has a camera sensor.
    var hasCamera: Bool { get }
    /// Supplies the next shot's sensor image. RGB sequences may hold one image across channels.
    /// Nil clears external images and any held sequence to neutral gray.
    /// Call between frames, on the same serialized worker as other core operations.
    func setCameraFrame(_ frame: CameraFrame?)
}

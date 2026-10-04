import EmulationCore
import Foundation

/// Turns a video frame into an image file, for save-state thumbnails. The app supplies one;
/// without it, states are saved with no thumbnail.
public protocol FrameImageEncoding: Sendable {
    /// The extension of the files `encode` makes, such as "png".
    var fileExtension: String { get }
    func encode(_ frame: EmulatorVideoFrame) throws -> Data
}

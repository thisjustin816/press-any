import EmulationCore
import Foundation

enum CameraFrameSampler {
    /// Center-crops BGRA pixels to the sensor's aspect ratio, retaining every color channel.
    static func sampleBGRA(
        _ bytes: UnsafeRawBufferPointer, width: Int, height: Int, bytesPerRow: Int
    ) throws -> CameraFrame {
        guard width > 0, height > 0, bytesPerRow > 0, width <= bytesPerRow / 4,
              height <= bytes.count / bytesPerRow else {
            throw CameraFrame.ValidationError.invalidByteCount
        }
        let scale = max(Double(CameraFrame.width) / Double(width), Double(CameraFrame.height) / Double(height))
        let offsetX = (Double(width) - Double(CameraFrame.width) / scale) / 2
        let offsetY = (Double(height) - Double(CameraFrame.height) / scale) / 2
        var rgb = Data(count: CameraFrame.width * CameraFrame.height * 3)
        rgb.withUnsafeMutableBytes { (output: UnsafeMutableRawBufferPointer) in
            for y in 0..<CameraFrame.height {
                let sourceY = min(height - 1, Int(offsetY + (Double(y) + 0.5) / scale))
                for x in 0..<CameraFrame.width {
                    let sourceX = min(width - 1, Int(offsetX + (Double(x) + 0.5) / scale))
                    let source = sourceY * bytesPerRow + sourceX * 4
                    let target = (y * CameraFrame.width + x) * 3
                    output[target] = bytes[source + 2]
                    output[target + 1] = bytes[source + 1]
                    output[target + 2] = bytes[source]
                }
            }
        }
        return try CameraFrame(rgb888: rgb)
    }
}

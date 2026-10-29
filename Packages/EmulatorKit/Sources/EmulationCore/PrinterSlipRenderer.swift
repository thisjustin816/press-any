import Foundation

public enum PrinterBackground: String, CaseIterable, Sendable {
    case transparent, light, dark

    public static let defaultValue: Self = .transparent
}

/// A decoded background, independent of an image file format or Apple framework.
public struct PrinterBackgroundImage: Sendable {
    public let width: Int
    public let height: Int
    public let bgra8888: Data
    public enum ValidationError: Error { case invalidImage }

    public init(width: Int, height: Int, bgra8888: Data) throws {
        guard (1...1536).contains(width), (1...1536).contains(height), bgra8888.count == width * height * 4 else {
            throw ValidationError.invalidImage
        }
        self.width = width
        self.height = height
        self.bgra8888 = bgra8888
    }
}

/// Produces a paper-shaped image with an unchanged, integer-scaled print grid.
public enum PrinterSlipRenderer {
    public struct Image: Equatable, Sendable {
        public let width: Int
        public let height: Int
        /// Premultiplied BGRA8888, including transparent paper edges.
        public let bgra8888: Data
    }

    public static let scale = 4
    public static let printOriginX = 40 * scale
    public static let printOriginY = 36 * scale
    /// The paper's torn edges follow the printer's cutter: a tooth every `tearPitch` pixels, each
    /// `tearDepth` deep, starting at the paper's left edge. The Printer background draws its cutter
    /// from the same numbers.
    public static let tearPitch = 4 * scale
    public static let tearDepth = 4 * scale

    public static func render(_ output: PrinterOutput, background: PrinterBackground = .defaultValue) -> Image {
        render(PrinterSlip(output: output), background: background)
    }

    public static func render(_ slip: PrinterSlip, background: PrinterBackground = .defaultValue) -> Image {
        render(slip, background: background, image: nil)
    }

    public static func render(_ slip: PrinterSlip, image: PrinterBackgroundImage) -> Image {
        render(slip, background: .light, image: image)
    }

    private static func render(_ slip: PrinterSlip, background: PrinterBackground, image: PrinterBackgroundImage?) -> Image {
        let width = 240 * scale
        let height = (slip.feedHeight + 72) * scale
        let left = 24 * scale
        let right = 216 * scale
        let top = 24 * scale
        let bottom = height - 24 * scale
        let base: (Int, Int, Int) = background == .dark ? (42, 44, 48) : (226, 227, 229)
        let photo = image.map { Array($0.bgra8888) }
        let fit = image.map { max(Double(width) / Double($0.width), Double(height) / Double($0.height)) } ?? 1
        let cropX = image.map { (Double($0.width) - Double(width) / fit) / 2 } ?? 0
        let cropY = image.map { (Double($0.height) - Double(height) / fit) / 2 } ?? 0
        var pixels = Data(count: width * height * 4)
        pixels.withUnsafeMutableBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<width {
                    let i = (y * width + x) * 4
                    let dx = max(left - x, 0, x - right)
                    let dy = max(top + 6 * scale - y, 0, y - bottom - 6 * scale)
                    let distance = Int(Double(dx * dx + dy * dy).squareRoot())
                    let shadow = max(0, 18 - distance / 2)
                    var surface = base
                    if let image, let photo {
                        let sourceX = min(image.width - 1, Int(cropX + Double(x) / fit))
                        let sourceY = min(image.height - 1, Int(cropY + Double(y) / fit))
                        let source = (sourceY * image.width + sourceX) * 4
                        surface = (Int(photo[source + 2]), Int(photo[source + 1]), Int(photo[source]))
                    }
                    var rgb = (max(0, surface.0 - shadow), max(0, surface.1 - shadow), max(0, surface.2 - shadow))
                    var alpha = background == .transparent ? 0 : 255
                    let tooth = (x - left + tearPitch) % tearPitch
                    let tear = min(tooth, tearPitch - tooth) * 2 * tearDepth / tearPitch
                    if x >= left, x < right, y >= top + tear, y < bottom - tear {
                        let noise = (x * 73 + y * 151 + (x * y) % 29) % 5
                        let edge = min(x - left, right - 1 - x)
                        let curl = max(0, 8 * scale - (bottom - y)) / scale
                        let shade = noise + (edge < 2 ? 8 : 0) + curl
                        rgb = (250 - shade, 249 - shade, 245 - shade)
                        alpha = 255
                    } else if background == .transparent {
                        rgb = (0, 0, 0)
                        alpha = shadow
                    }
                    bytes[i] = UInt8(rgb.2); bytes[i + 1] = UInt8(rgb.1)
                    bytes[i + 2] = UInt8(rgb.0); bytes[i + 3] = UInt8(alpha)
                }
            }
            var row = 36
            for section in slip.sections {
                row += section.topMargin * 8
                for y in 0..<section.height {
                    for x in 0..<PrinterOutput.width {
                        let level = Int(section.luminance[y * PrinterOutput.width + x])
                        let r = UInt8(30 + level * 220 / 255)
                        let g = UInt8(29 + level * 220 / 255)
                        let b = UInt8(27 + level * 218 / 255)
                        for sy in 0..<scale {
                            for sx in 0..<scale {
                                let i = (((row + y) * scale + sy) * width + printOriginX + x * scale + sx) * 4
                                bytes[i] = b; bytes[i + 1] = g; bytes[i + 2] = r; bytes[i + 3] = 255
                            }
                        }
                    }
                }
                row += section.height + section.bottomMargin * 8
            }
        }
        return Image(width: width, height: height, bgra8888: pixels)
    }
}

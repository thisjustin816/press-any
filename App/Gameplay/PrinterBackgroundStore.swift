import CoreGraphics
import EmulationCore
import EmulatorApplication
import Foundation

/// Keeps one normalized custom background without the source image's metadata.
struct PrinterBackgroundStore: Sendable {
    enum ImageError: Error { case invalidImage, tooLarge, missingWood }
    static let maximumBytes = 25 * 1024 * 1024
    private static let maximumPixelSize = 1536
    private static let maximumSourcePixels = 100_000_000
    let directory: URL

    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PrinterBackgrounds", isDirectory: true)) {
        self.directory = directory
    }

    private var customURL: URL { directory.appendingPathComponent("custom.jpg") }

    func load() throws -> PrinterBackgroundImage? {
        guard FileManager.default.fileExists(atPath: customURL.path) else { return nil }
        return try Self.decode(Self.readFile(customURL))
    }

    func remove() throws {
        if FileManager.default.fileExists(atPath: customURL.path) { try FileManager.default.removeItem(at: customURL) }
    }

    func save(_ data: Data) throws -> PrinterBackgroundImage {
        guard data.count <= Self.maximumBytes else { throw ImageError.tooLarge }
        let jpeg: Data
        do {
            let image = try ImportedImage.decode(data, maximumPixelSize: Self.maximumPixelSize, maximumSourcePixels: Self.maximumSourcePixels)
            jpeg = try ImportedImage.encode(image, format: .jpeg)
        } catch { throw ImageError.invalidImage }
        let normalized = try Self.decode(jpeg)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try jpeg.write(to: customURL, options: .atomic)
        // Reuse the persisted pixels so reopening the preview produces the same export.
        return normalized
    }

    static func readFile(_ url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw ImageError.invalidImage }
        guard let size = values.fileSize, size <= maximumBytes else { throw ImageError.tooLarge }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= maximumBytes else { throw ImageError.tooLarge }
        return data
    }

    static func wood(bundle: Bundle = .main) throws -> PrinterBackgroundImage {
        guard let url = bundle.url(forResource: "PrinterWood", withExtension: "jpg") else { throw ImageError.missingWood }
        return try decode(readFile(url))
    }

    static func decode(_ data: Data) throws -> PrinterBackgroundImage {
        guard data.count <= maximumBytes else { throw ImageError.tooLarge }
        let image: CGImage
        do { image = try ImportedImage.decode(data, maximumPixelSize: Self.maximumPixelSize, maximumSourcePixels: Self.maximumSourcePixels) }
        catch { throw ImageError.invalidImage }
        var pixels = Data(count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else {
                throw ImageError.invalidImage
            }
            let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(bounds)
            context.draw(image, in: bounds)
        }
        return try PrinterBackgroundImage(width: image.width, height: image.height, bgra8888: pixels)
    }
}

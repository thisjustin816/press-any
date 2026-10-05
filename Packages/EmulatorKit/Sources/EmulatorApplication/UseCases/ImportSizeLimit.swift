import Foundation

public enum ImportSizeError: Error, Equatable, LocalizedError {
    case fileTooLarge(limit: Int64)

    public var errorDescription: String? {
        switch self {
        case .fileTooLarge(let limit):
            "This file is larger than \(limit / 1_048_576) MB, the most this kind of file can be."
        }
    }
}

/// The largest file each kind of import accepts. Picked files are checked before they are read
/// or staged, so a huge or mislabeled file fails at once instead of filling memory or disk.
public struct ImportSizeLimit: Equatable, Sendable {
    public let bytes: Int64

    public init(bytes: Int64) {
        self.bytes = bytes
    }

    /// The largest size a GB/GBC header can declare (code $08).
    public static let rom = ImportSizeLimit(bytes: 8 * 1_048_576)
    /// Matches the largest result a BPS patch may produce.
    public static let patch = ImportSizeLimit(bytes: 64 * 1_048_576)
    /// TPP1 cartridges can declare 2 MB of RAM, and RTC trailers add under 100 bytes.
    public static let batterySave = ImportSizeLimit(bytes: 4 * 1_048_576)
    /// Stored artwork is downscaled, so only the file as picked can be this large.
    public static let artwork = ImportSizeLimit(bytes: 20 * 1_048_576)
    public static let variableMap = ImportSizeLimit(bytes: 4 * 1_048_576)

    /// Throws when the file, after following symbolic links, is larger than the limit.
    public func check(fileAt url: URL) throws {
        let size = try url.resolvingSymlinksInPath().resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        try check(byteCount: Int64(size))
    }

    public func check(byteCount: Int64) throws {
        guard byteCount <= bytes else { throw ImportSizeError.fileTooLarge(limit: bytes) }
    }
}

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

    /// The largest size a GB/GBC header can declare (code $08). Patch results and the images the
    /// core loads are held to it too.
    public static let rom = ImportSizeLimit(bytes: 8 * 1_048_576)
    /// Twice the largest result a patch may produce, room for any IPS or BPS encoding of it.
    public static let patch = ImportSizeLimit(bytes: 16 * 1_048_576)
    /// TPP1 cartridges can declare 2 MB of RAM, and RTC trailers add under 100 bytes.
    public static let batterySave = ImportSizeLimit(bytes: 4 * 1_048_576)
    /// Stored artwork is downscaled, so only the file as picked can be this large.
    public static let artwork = ImportSizeLimit(bytes: 20 * 1_048_576)
    public static let variableMap = ImportSizeLimit(bytes: 4 * 1_048_576)
    /// A zip holding a ROM, patches or saves. Each file inside is held to its own kind's limit.
    public static let archive = ImportSizeLimit(bytes: 32 * 1_048_576)
    /// A Library Backup or Game package, read from a mapped file one entry at a time. 2 GiB keeps
    /// every zip offset and size in 32 bits, so the format never needs Zip64.
    public static let backupArchive = ImportSizeLimit(bytes: 2 * 1_073_741_824)

    /// Throws when the file, after following symbolic links, is larger than the limit.
    public func check(fileAt url: URL) throws {
        let size = try url.resolvingSymlinksInPath().resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        try check(byteCount: Int64(size))
    }

    public func check(byteCount: Int64) throws {
        guard byteCount <= bytes else { throw ImportSizeError.fileTooLarge(limit: bytes) }
    }
}

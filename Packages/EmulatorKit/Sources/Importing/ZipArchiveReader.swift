import CZlib
import EmulatorApplication
import Foundation

/// A file or folder in a zip archive. Folder paths end in `/` and have empty data.
public struct ZipArchiveEntry: Equatable, Sendable {
    /// The entry's filename without its folders.
    public let filename: String
    public let relativePath: String
    public let data: Data

    public init(filename: String, data: Data) {
        self.init(filename: filename, relativePath: filename, data: data)
    }

    public init(relativePath: String, data: Data) {
        self.init(filename: String(relativePath.split(separator: "/").last ?? ""), relativePath: relativePath, data: data)
    }

    public init(filename: String, relativePath: String, data: Data) {
        self.filename = filename
        self.relativePath = relativePath
        self.data = data
    }
}

public enum ZipArchiveError: LocalizedError, Equatable {
    case notAZip
    case damaged
    case encrypted
    case unsupportedCompression
    case entryTooLarge(String)
    case tooManyEntries
    case unsafePath(String)
    case duplicatePath(String)
    case archiveTooLarge
    case totalSizeTooLarge

    public var errorDescription: String? {
        switch self {
        case .notAZip: "This file isn’t a zip archive."
        case .damaged: "This zip archive is damaged."
        case .encrypted: "Password-protected zip archives can’t be opened."
        case .unsupportedCompression: "This zip archive uses a compression method that can’t be opened. Unzip it in Files first."
        case .entryTooLarge(let name): "“\(name)” in this zip is too large to import."
        case .tooManyEntries: "This zip archive holds too many files to open."
        case .unsafePath(let path): "\"\(path)\" is not a safe relative path in this zip."
        case .duplicatePath(let path): "\"\(path)\" appears more than once in this zip."
        case .archiveTooLarge: "This zip archive is too large to open."
        case .totalSizeTooLarge: "The files in this zip archive are too large to open together."
        }
    }
}

/// Reads classic, single-disk ZIP archives. Stored and deflated entries are supported;
/// encryption and Zip64 (including newer required versions and Zip64 extra fields) are refused.
public enum ZipArchiveReader {
    /// Archive entry cap, including folders. ROM imports separately allow at most 32 matches.
    public static let maximumEntries = 4_096
    /// Maximum encoded size of a zip of ROMs, patches or saves: the 32 MiB import cap.
    public static let maximumArchiveBytes = Int(ImportSizeLimit.archive.bytes)
    /// Maximum encoded size of a backup: 2 GiB. Also enforced by the writer.
    public static let maximumBackupArchiveBytes = Int(ImportSizeLimit.backupArchive.bytes)
    /// Maximum backup entry size: 64 MiB, checked before allocation or inflation.
    public static let maximumEntryBytes = 64 << 20
    /// Maximum expanded backup payload, the same 2 GiB. The writer uses the same payload limits.
    public static let maximumTotalBytes = maximumBackupArchiveBytes
    static let maximumMatchingEntries = 32

    /// A backup archive whose entries are validated up front and extracted one at a time, so
    /// memory holds at most one entry beyond the mapped file.
    public struct BackupArchive: Sendable {
        private let archive: Data
        private let entries: [String: ArchivedEntry]
        /// Every entry path in archive order, including folders.
        public let paths: [String]

        /// Maps the file instead of reading it, after checking its size against the backup limit.
        public init(contentsOf url: URL) throws {
            try ImportSizeLimit.backupArchive.check(fileAt: url)
            try self.init(data: Data(contentsOf: url, options: .alwaysMapped))
        }

        public init(data: Data) throws {
            let data = data.startIndex == 0 ? data : Data(data)
            let directory = try backupDirectory(in: data)
            archive = data
            paths = directory.map(\.path)
            entries = Dictionary(directory.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        }

        public func contains(_ path: String) -> Bool { entries[path] != nil }

        public func byteLength(of path: String) -> Int? { entries[path]?.size }

        public func data(at path: String) throws -> Data {
            guard let entry = entries[path] else { throw ZipArchiveError.damaged }
            return try extract(entry, from: archive)
        }
    }

    /// ROM imports keep only basenames, skip folders and macOS metadata, and apply extension limits.
    /// Entries they don't want are skipped unread, along with links and anything this reader
    /// can't open, so a download's odd readme doesn't stop its ROM from importing.
    public static func entries(
        in archive: Data,
        extensions: Set<String>,
        limit: (String) -> Int64
    ) throws -> [ZipArchiveEntry] {
        let archive = Data(archive)
        func wanted(_ path: String) -> Bool {
            filename(of: path).map { extensions.contains(($0 as NSString).pathExtension.lowercased()) } ?? false
        }
        let directory = try directory(in: archive, limit: maximumArchiveBytes, wanted: wanted)
        var entries: [ZipArchiveEntry] = []
        for entry in directory {
            guard let filename = filename(of: entry.path) else { continue }
            guard entries.count < maximumMatchingEntries else { throw ZipArchiveError.tooManyEntries }
            guard Int64(entry.size) <= limit((filename as NSString).pathExtension.lowercased()) else {
                throw ZipArchiveError.entryTooLarge(filename)
            }
            entries.append(ZipArchiveEntry(filename: filename, data: try extract(entry, from: archive)))
        }
        return entries
    }

    /// Reads every backup entry with its relative path, including folders and empty files.
    /// Paths and the full declared payload budget are validated before any file is extracted.
    public static func backupEntries(in archive: Data) throws -> [ZipArchiveEntry] {
        let backup = try BackupArchive(data: archive)
        return try backup.paths.map { ZipArchiveEntry(relativePath: $0, data: try backup.data(at: $0)) }
    }

    /// Checks for the exact root `backup-manifest.json` using metadata only, with no extraction
    /// or ROM matching cap. This identifies the container, not the validity of its manifest data.
    public static func isLibraryBackup(_ archive: Data) throws -> Bool {
        try !directory(in: archive, limit: maximumBackupArchiveBytes, wanted: { $0 == "backup-manifest.json" }).isEmpty
    }

    private struct ArchivedEntry: Sendable {
        let name: Data
        let path: String
        let method: UInt16
        let crc: UInt32
        let compressedSize: Int
        let size: Int
        let dataStart: Int
        let localRange: Range<Int>
    }

    private static func backupDirectory(in archive: Data) throws -> [ArchivedEntry] {
        let entries = try directory(in: archive, limit: maximumBackupArchiveBytes)
        for entry in entries {
            guard String(data: entry.name, encoding: .utf8) != nil else { throw ZipArchiveError.damaged }
        }
        try ZipArchiveFormat.validatePaths(entries.map(\.path))
        var total = 0
        for entry in entries {
            try ZipArchiveFormat.validateSize(entry.size, path: entry.path, total: &total)
            guard entry.method == 0 || entry.method == 8 else { throw ZipArchiveError.unsupportedCompression }
            guard !entry.path.hasSuffix("/") || entry.size == 0 else { throw ZipArchiveError.damaged }
        }
        return entries
    }

    private static func extract(_ entry: ArchivedEntry, from archive: Data) throws -> Data {
        let stored = try bytes(archive, entry.dataStart, entry.compressedSize)
        let data: Data
        switch entry.method {
        case 0: data = stored
        case 8: data = try inflate(stored, size: entry.size)
        default: throw ZipArchiveError.unsupportedCompression
        }
        guard ZipArchiveFormat.checksum(data) == entry.crc else { throw ZipArchiveError.damaged }
        return data
    }

    /// Reads the central directory. With `wanted`, entries it rejects and links are skipped before
    /// validation, and trailing bytes after the end record are ignored; without it, every entry
    /// must be valid. Backups pass none.
    private static func directory(in archive: Data, limit: Int,
                                  wanted: ((String) -> Bool)? = nil) throws -> [ArchivedEntry] {
        guard archive.count <= limit else { throw ZipArchiveError.archiveTooLarge }
        let end = try endOfCentralDirectory(in: archive, allowsTrailingBytes: wanted != nil)
        guard end.entryCount <= maximumEntries else { throw ZipArchiveError.tooManyEntries }
        let directoryEnd = end.directoryOffset + end.directorySize
        var offset = end.directoryOffset
        var entries: [ArchivedEntry] = []
        for _ in 0..<end.entryCount {
            guard offset <= directoryEnd - 46, try uint32(archive, offset) == 0x0201_4b50 else {
                throw ZipArchiveError.damaged
            }
            let nameLength = Int(try uint16(archive, offset + 28))
            let extraLength = Int(try uint16(archive, offset + 30))
            let commentLength = Int(try uint16(archive, offset + 32))
            let next = offset + 46 + nameLength + extraLength + commentLength
            guard next <= directoryEnd else { throw ZipArchiveError.damaged }
            let name = try bytes(archive, offset + 46, nameLength)
            let fileType = (try uint32(archive, offset + 38) >> 16) & 0xf000
            if let wanted, fileType == 0xa000 || !wanted(String(decoding: name, as: UTF8.self)) {
                offset = next
                continue
            }
            entries.append(try entry(in: archive, at: offset, name: name, directoryOffset: end.directoryOffset))
            offset = next
        }
        guard offset == directoryEnd else { throw ZipArchiveError.damaged }
        let ranges = entries.map(\.localRange).sorted { $0.lowerBound < $1.lowerBound }
        for index in 1..<max(1, ranges.count) {
            guard ranges[index - 1].upperBound <= ranges[index].lowerBound else { throw ZipArchiveError.damaged }
        }
        return entries
    }

    /// Validates one central directory record and its local header.
    private static func entry(in archive: Data, at offset: Int, name: Data, directoryOffset: Int) throws -> ArchivedEntry {
        let version = try uint16(archive, offset + 6)
        let flags = try uint16(archive, offset + 8)
        let method = try uint16(archive, offset + 10)
        let timestamp = try uint32(archive, offset + 12)
        let crc = try uint32(archive, offset + 16)
        let compressedSize = Int(try uint32(archive, offset + 20))
        let size = Int(try uint32(archive, offset + 24))
        let nameLength = name.count
        let extraLength = Int(try uint16(archive, offset + 30))
        let attributes = try uint32(archive, offset + 38)
        let localOffset = Int(try uint32(archive, offset + 42))
        guard version >= 10, version <= 20,
              compressedSize != 0xffff_ffff, size != 0xffff_ffff, localOffset != 0xffff_ffff,
              try uint16(archive, offset + 34) == 0 else { throw ZipArchiveError.damaged }
        guard flags & 0x2041 == 0 else { throw ZipArchiveError.encrypted }
        guard flags & ~UInt16(0x080e) == 0 else { throw ZipArchiveError.damaged }
        let fileType = (attributes >> 16) & 0xf000
        guard fileType == 0 || fileType == 0x8000 || fileType == 0x4000 else { throw ZipArchiveError.damaged }
        try validateExtra(archive, offset + 46 + nameLength, extraLength)
        guard localOffset <= directoryOffset - 30,
              try uint32(archive, localOffset) == 0x0403_4b50,
              try uint16(archive, localOffset + 4) == version,
              try uint16(archive, localOffset + 6) == flags,
              try uint16(archive, localOffset + 8) == method,
              try uint32(archive, localOffset + 10) == timestamp else { throw ZipArchiveError.damaged }
        let localNameLength = Int(try uint16(archive, localOffset + 26))
        let localExtraLength = Int(try uint16(archive, localOffset + 28))
        let dataStart = localOffset + 30 + localNameLength + localExtraLength
        let dataEnd = dataStart + compressedSize
        guard dataEnd <= directoryOffset,
              try bytes(archive, localOffset + 30, localNameLength) == name else { throw ZipArchiveError.damaged }
        try validateExtra(archive, localOffset + 30 + localNameLength, localExtraLength)
        let localCRC = try uint32(archive, localOffset + 14)
        let localCompressedSize = try uint32(archive, localOffset + 18)
        let localSize = try uint32(archive, localOffset + 22)
        var rangeEnd = dataEnd
        if flags & 8 == 0 {
            guard localCRC == crc, localCompressedSize == compressedSize, localSize == size else {
                throw ZipArchiveError.damaged
            }
        } else {
            guard (localCRC == 0 || localCRC == crc),
                  (localCompressedSize == 0 || localCompressedSize == compressedSize),
                  (localSize == 0 || localSize == size) else { throw ZipArchiveError.damaged }
            rangeEnd = try descriptorEnd(in: archive, at: dataEnd, before: directoryOffset,
                                         crc: crc, compressedSize: compressedSize, size: size)
        }
        guard method != 0 || compressedSize == size else { throw ZipArchiveError.damaged }
        return ArchivedEntry(name: name, path: String(decoding: name, as: UTF8.self), method: method,
                             crc: crc, compressedSize: compressedSize, size: size,
                             dataStart: dataStart, localRange: localOffset..<rangeEnd)
    }

    private static func validateExtra(_ archive: Data, _ offset: Int, _ size: Int) throws {
        let end = offset + size
        var cursor = offset
        while cursor < end {
            guard cursor <= end - 4 else { throw ZipArchiveError.damaged }
            let identifier = try uint16(archive, cursor)
            let length = Int(try uint16(archive, cursor + 2))
            guard identifier != 1, length <= end - cursor - 4 else { throw ZipArchiveError.damaged }
            cursor += 4 + length
        }
    }

    private static func descriptorEnd(in archive: Data, at offset: Int, before end: Int,
                                      crc: UInt32, compressedSize: Int, size: Int) throws -> Int {
        for prefix in [4, 0] {
            let start = offset + prefix
            guard start <= end - 12 else { continue }
            if prefix == 4, try uint32(archive, offset) != 0x0807_4b50 { continue }
            if try uint32(archive, start) == crc,
               try uint32(archive, start + 4) == compressedSize,
               try uint32(archive, start + 8) == size { return start + 12 }
        }
        throw ZipArchiveError.damaged
    }

    /// The last part of an entry's path, or nil for a folder or macOS resource-fork metadata.
    private static func filename(of path: String) -> String? {
        let parts = path.split(whereSeparator: { $0 == "/" || $0 == "\\" })
        guard !path.hasSuffix("/"), let last = parts.last, !parts.contains("__MACOSX"), !last.hasPrefix("._"),
              last != ".", last != ".." else { return nil }
        return String(last)
    }

    private static func endOfCentralDirectory(in archive: Data, allowsTrailingBytes: Bool) throws
        -> (entryCount: Int, directoryOffset: Int, directorySize: Int) {
        // The record is 22 bytes, followed by a comment of at most 65,535.
        guard archive.count >= 22 else { throw ZipArchiveError.notAZip }
        var offset = archive.count - 22
        let earliest = max(0, archive.count - 22 - 65_535)
        while offset >= earliest {
            if try uint32(archive, offset) == 0x0605_4b50 {
                let commentLength = Int(try uint16(archive, offset + 20))
                let recordEnd = offset + 22 + commentLength
                guard recordEnd == archive.count || (allowsTrailingBytes && recordEnd < archive.count) else {
                    offset -= 1
                    continue
                }
                let entryCount = Int(try uint16(archive, offset + 10))
                let directorySize = Int(try uint32(archive, offset + 12))
                let directoryOffset = Int(try uint32(archive, offset + 16))
                guard try uint16(archive, offset + 4) == 0, try uint16(archive, offset + 6) == 0,
                      try uint16(archive, offset + 8) == entryCount,
                      entryCount != 0xffff, directoryOffset != 0xffff_ffff, directorySize != 0xffff_ffff,
                      directoryOffset + directorySize == offset else {
                    // Trailing bytes can contain the signature by chance; keep looking before them.
                    if allowsTrailingBytes && recordEnd < archive.count {
                        offset -= 1
                        continue
                    }
                    throw ZipArchiveError.damaged
                }
                return (entryCount, directoryOffset, directorySize)
            }
            offset -= 1
        }
        throw ZipArchiveError.notAZip
    }

    /// Inflates raw deflate data into exactly `size` bytes, so a damaged or hostile entry can't
    /// produce more than the limit already checked.
    private static func inflate(_ input: Data, size: Int) throws -> Data {
        // Empty deflate streams still contain an end marker and need output space to validate it.
        var output = Data(count: max(1, size))
        var stream = z_stream()
        // Negative window bits: raw deflate, without the zlib header zip leaves out.
        guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw ZipArchiveError.damaged
        }
        defer { inflateEnd(&stream) }
        var input = input
        let result = input.withUnsafeMutableBytes { inputBuffer in
            output.withUnsafeMutableBytes { outputBuffer in
                stream.next_in = inputBuffer.bindMemory(to: Bytef.self).baseAddress
                stream.avail_in = uInt(inputBuffer.count)
                stream.next_out = outputBuffer.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(outputBuffer.count)
                return CZlib.inflate(&stream, Z_FINISH)
            }
        }
        guard result == Z_STREAM_END, Int(stream.total_out) == size,
              Int(stream.total_in) == input.count else { throw ZipArchiveError.damaged }
        return size == 0 ? Data() : output
    }

    private static func bytes(_ data: Data, _ offset: Int, _ count: Int) throws -> Data {
        guard offset >= 0, count >= 0, offset <= data.count - count else { throw ZipArchiveError.damaged }
        return data.subdata(in: offset..<(offset + count))
    }

    private static func uint16(_ data: Data, _ offset: Int) throws -> UInt16 {
        let value = try bytes(data, offset, 2)
        return UInt16(value[0]) | UInt16(value[1]) << 8
    }

    private static func uint32(_ data: Data, _ offset: Int) throws -> UInt32 {
        let value = try bytes(data, offset, 4)
        return UInt32(value[0]) | UInt32(value[1]) << 8 | UInt32(value[2]) << 16 | UInt32(value[3]) << 24
    }
}

/// Shared backup validation and CRC rules for the reader and writer.
enum ZipArchiveFormat {
    static func validatePaths(_ paths: [String]) throws {
        var kinds: [String: Bool] = [:]
        for path in paths {
            let isDirectory = path.hasSuffix("/")
            let key = isDirectory ? String(path.dropLast()) : path
            let parts = key.split(separator: "/", omittingEmptySubsequences: false)
            guard !key.isEmpty, !path.contains("\\"), !path.contains(":"),
                  !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
                throw ZipArchiveError.unsafePath(path)
            }
            guard kinds.updateValue(isDirectory, forKey: key) == nil else { throw ZipArchiveError.duplicatePath(path) }
        }
        for path in paths {
            let parts = path.split(separator: "/")
            var parent = ""
            for part in parts.dropLast() {
                parent = parent.isEmpty ? String(part) : parent + "/" + part
                guard kinds[parent] != false else { throw ZipArchiveError.unsafePath(path) }
            }
        }
    }

    static func validateSize(_ size: Int, path: String, total: inout Int) throws {
        guard size <= ZipArchiveReader.maximumEntryBytes else { throw ZipArchiveError.entryTooLarge(path) }
        guard size <= ZipArchiveReader.maximumTotalBytes - total else { throw ZipArchiveError.totalSizeTooLarge }
        total += size
    }

    static func checksum(_ data: Data, continuing previous: UInt32 = 0) -> UInt32 {
        data.withUnsafeBytes { buffer in
            UInt32(crc32(uLong(previous), buffer.bindMemory(to: Bytef.self).baseAddress, uInt(buffer.count)))
        }
    }
}

import CZlib
import Foundation

/// A file read out of a zip archive.
public struct ZipArchiveEntry: Equatable, Sendable {
    /// The entry's filename without its folders.
    public let filename: String
    public let data: Data
}

public enum ZipArchiveError: LocalizedError, Equatable {
    case notAZip
    case damaged
    case encrypted
    case unsupportedCompression
    case entryTooLarge(String)
    case tooManyEntries

    public var errorDescription: String? {
        switch self {
        case .notAZip: "This file isn’t a zip archive."
        case .damaged: "This zip archive is damaged."
        case .encrypted: "Password-protected zip archives can’t be opened."
        case .unsupportedCompression: "This zip archive uses a compression method that can’t be opened. Unzip it in Files first."
        case .entryTooLarge(let name): "“\(name)” in this zip is too large to import."
        case .tooManyEntries: "This zip archive holds too many files to open."
        }
    }
}

/// Reads the files a ROM hack or homebrew download is zipped with, in memory. Only entries whose
/// extension is asked for are read; readmes and folders are skipped. Entries must be stored or
/// deflated, which is what zip tools write by default. Each entry's size is checked against its
/// limit before it's inflated, inflating stops at the size the archive declares, and the result
/// must match the entry's CRC32.
public enum ZipArchiveReader {
    /// More entries than any download needs; a zip listing more is refused before any is read.
    static let maximumEntries = 4_096
    static let maximumMatchingEntries = 32

    public static func entries(
        in archive: Data,
        extensions: Set<String>,
        limit: (String) -> Int64
    ) throws -> [ZipArchiveEntry] {
        let archive = Data(archive)
        let end = try endOfCentralDirectory(in: archive)
        guard end.entryCount <= maximumEntries else { throw ZipArchiveError.tooManyEntries }
        var offset = end.directoryOffset
        var entries: [ZipArchiveEntry] = []
        for _ in 0..<end.entryCount {
            guard try uint32(archive, offset) == 0x0201_4b50 else { throw ZipArchiveError.damaged }
            let flags = try uint16(archive, offset + 8)
            let method = try uint16(archive, offset + 10)
            let crc = try uint32(archive, offset + 16)
            let compressedSize = Int(try uint32(archive, offset + 20))
            let size = Int(try uint32(archive, offset + 24))
            let nameLength = Int(try uint16(archive, offset + 28))
            let extraLength = Int(try uint16(archive, offset + 30))
            let commentLength = Int(try uint16(archive, offset + 32))
            let localOffset = Int(try uint32(archive, offset + 42))
            let path = String(decoding: try bytes(archive, offset + 46, nameLength), as: UTF8.self)
            offset += 46 + nameLength + extraLength + commentLength

            guard let filename = filename(of: path), extensions.contains((filename as NSString).pathExtension.lowercased()) else {
                continue
            }
            guard entries.count < maximumMatchingEntries else { throw ZipArchiveError.tooManyEntries }
            guard flags & 1 == 0 else { throw ZipArchiveError.encrypted }
            guard Int64(size) <= limit((filename as NSString).pathExtension.lowercased()) else {
                throw ZipArchiveError.entryTooLarge(filename)
            }
            guard try uint32(archive, localOffset) == 0x0403_4b50 else { throw ZipArchiveError.damaged }
            let dataStart = localOffset + 30 + Int(try uint16(archive, localOffset + 26)) + Int(try uint16(archive, localOffset + 28))
            let stored = try bytes(archive, dataStart, compressedSize)
            let data: Data
            switch method {
            case 0:
                guard stored.count == size else { throw ZipArchiveError.damaged }
                data = stored
            case 8:
                data = try inflate(stored, size: size)
            default:
                throw ZipArchiveError.unsupportedCompression
            }
            guard checksum(data) == crc else { throw ZipArchiveError.damaged }
            entries.append(ZipArchiveEntry(filename: filename, data: data))
        }
        return entries
    }

    /// The last part of an entry's path, or nil for a folder or macOS resource-fork metadata.
    private static func filename(of path: String) -> String? {
        let parts = path.split(whereSeparator: { $0 == "/" || $0 == "\\" })
        guard !path.hasSuffix("/"), let last = parts.last, !parts.contains("__MACOSX"), !last.hasPrefix("._"),
              last != ".", last != ".." else { return nil }
        return String(last)
    }

    private static func endOfCentralDirectory(in archive: Data) throws -> (entryCount: Int, directoryOffset: Int) {
        // The record is 22 bytes, followed by a comment of at most 65,535.
        guard archive.count >= 22 else { throw ZipArchiveError.notAZip }
        var offset = archive.count - 22
        let earliest = max(0, archive.count - 22 - 65_535)
        while offset >= earliest {
            if try uint32(archive, offset) == 0x0605_4b50 {
                let entryCount = Int(try uint16(archive, offset + 10))
                let directorySize = Int(try uint32(archive, offset + 12))
                let directoryOffset = Int(try uint32(archive, offset + 16))
                // Zip64 archives mark these fields as all ones; no Game Boy download needs one.
                guard entryCount != 0xffff, directoryOffset != 0xffff_ffff,
                      directoryOffset + directorySize <= offset else { throw ZipArchiveError.damaged }
                return (entryCount, directoryOffset)
            }
            offset -= 1
        }
        throw ZipArchiveError.notAZip
    }

    /// Inflates raw deflate data into exactly `size` bytes, so a damaged or hostile entry can't
    /// produce more than the limit already checked.
    private static func inflate(_ input: Data, size: Int) throws -> Data {
        guard size > 0 else {
            guard !input.isEmpty else { return Data() }
            throw ZipArchiveError.damaged
        }
        var output = Data(count: size)
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
        guard result == Z_STREAM_END, Int(stream.total_out) == size else { throw ZipArchiveError.damaged }
        return output
    }

    private static func checksum(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { buffer in
            UInt32(crc32(0, buffer.bindMemory(to: Bytef.self).baseAddress, uInt(buffer.count)))
        }
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

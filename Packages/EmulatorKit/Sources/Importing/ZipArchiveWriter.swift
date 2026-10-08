import Foundation

/// Writes classic, single-disk ZIP archives with UTF-8 names and stored (uncompressed) data.
/// Zip64 is unsupported. The reader's entry and payload limits also apply here, with the backup
/// archive limit unless a smaller one is given.
public enum ZipArchiveWriter {
    public enum Content: Sendable {
        case data(Data)
        /// A file streamed in chunks. It must keep the size it has when writing starts.
        case file(URL)
    }

    public struct Item: Sendable {
        public let relativePath: String
        public let content: Content

        public init(relativePath: String, content: Content) {
            self.relativePath = relativePath
            self.content = content
        }
    }

    public static func archive(entries: [ZipArchiveEntry],
                               maximumBytes: Int = ZipArchiveReader.maximumBackupArchiveBytes) throws -> Data {
        let output = DataOutput()
        try write(entries.map { Item(relativePath: $0.relativePath, content: .data($0.data)) }, to: output, maximumBytes: maximumBytes)
        return output.data
    }

    /// Streams the archive to a new file at `url`, so memory holds one chunk of a file at a time.
    public static func write(_ items: [Item], to url: URL,
                             maximumBytes: Int = ZipArchiveReader.maximumBackupArchiveBytes) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        do {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try write(items, to: FileOutput(handle: handle), maximumBytes: maximumBytes)
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    /// The size of an archive holding entries at `paths` with `payloadBytes` of data in all.
    public static func archiveByteLength(paths: [String], payloadBytes: Int) -> Int {
        22 + payloadBytes + paths.reduce(0) { $0 + 76 + 2 * $1.utf8.count }
    }

    private static let chunkSize = 1 << 20

    private static func size(of content: Content) throws -> Int {
        switch content {
        case .data(let data): data.count
        case .file(let url): (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        }
    }

    private static func write(_ items: [Item], to output: some ZipOutput, maximumBytes: Int) throws {
        guard items.count <= ZipArchiveReader.maximumEntries else { throw ZipArchiveError.tooManyEntries }
        try ZipArchiveFormat.validatePaths(items.map(\.relativePath))
        var sizes: [Int] = []
        var total = 0
        for item in items {
            let nameSize = item.relativePath.utf8.count
            guard nameSize <= Int(UInt16.max) else { throw ZipArchiveError.entryTooLarge(item.relativePath) }
            let size = try size(of: item.content)
            guard !item.relativePath.hasSuffix("/") || size == 0 else { throw ZipArchiveError.damaged }
            try ZipArchiveFormat.validateSize(size, path: item.relativePath, total: &total)
            sizes.append(size)
        }
        guard archiveByteLength(paths: items.map(\.relativePath), payloadBytes: total) <= maximumBytes else {
            throw ZipArchiveError.archiveTooLarge
        }

        var directory = Data()
        for (item, size) in zip(items, sizes) {
            let name = Data(item.relativePath.utf8)
            let offset = UInt32(output.offset)
            var header = Data()
            header.appendUInt32(0x0403_4b50)
            header.appendUInt16(20)
            header.appendUInt16(0x0800)
            header.appendUInt16(0)
            header.appendUInt16(0)
            header.appendUInt16(0x0021) // DOS date: January 1, 1980.
            header.appendUInt32(0) // CRC-32, filled in once the data is written.
            header.appendUInt32(UInt32(size))
            header.appendUInt32(UInt32(size))
            header.appendUInt16(UInt16(name.count))
            header.appendUInt16(0)
            header.append(name)
            try output.write(header)
            let crc = try writeContent(item, size: size, to: output)
            var crcBytes = Data()
            crcBytes.appendUInt32(crc)
            try output.overwrite(crcBytes, at: Int(offset) + 14)

            directory.appendUInt32(0x0201_4b50)
            directory.appendUInt16(20)
            directory.appendUInt16(20)
            directory.appendUInt16(0x0800)
            directory.appendUInt16(0)
            directory.appendUInt16(0)
            directory.appendUInt16(0x0021)
            directory.appendUInt32(crc)
            directory.appendUInt32(UInt32(size))
            directory.appendUInt32(UInt32(size))
            directory.appendUInt16(UInt16(name.count))
            directory.appendUInt16(0)
            directory.appendUInt16(0)
            directory.appendUInt16(0)
            directory.appendUInt16(0)
            directory.appendUInt32(item.relativePath.hasSuffix("/") ? 0x10 : 0)
            directory.appendUInt32(offset)
            directory.append(name)
        }
        let directoryOffset = UInt32(output.offset)
        var end = directory
        end.appendUInt32(0x0605_4b50)
        end.appendUInt16(0)
        end.appendUInt16(0)
        end.appendUInt16(UInt16(items.count))
        end.appendUInt16(UInt16(items.count))
        end.appendUInt32(UInt32(directory.count))
        end.appendUInt32(directoryOffset)
        end.appendUInt16(0)
        try output.write(end)
    }

    private static func writeContent(_ item: Item, size: Int, to output: some ZipOutput) throws -> UInt32 {
        switch item.content {
        case .data(let data):
            try output.write(data)
            return ZipArchiveFormat.checksum(data)
        case .file(let url):
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var crc: UInt32 = 0
            var written = 0
            while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
                written += chunk.count
                guard written <= size else { throw ZipArchiveError.damaged }
                crc = ZipArchiveFormat.checksum(chunk, continuing: crc)
                try output.write(chunk)
            }
            guard written == size else { throw ZipArchiveError.damaged }
            return crc
        }
    }
}

private protocol ZipOutput {
    var offset: Int { get }
    func write(_ data: Data) throws
    func overwrite(_ data: Data, at offset: Int) throws
}

private final class DataOutput: ZipOutput {
    var data = Data()
    var offset: Int { data.count }
    func write(_ bytes: Data) { data.append(bytes) }
    func overwrite(_ bytes: Data, at offset: Int) { data.replaceSubrange(offset..<(offset + bytes.count), with: bytes) }
}

private final class FileOutput: ZipOutput {
    let handle: FileHandle
    private(set) var offset = 0

    init(handle: FileHandle) { self.handle = handle }

    func write(_ data: Data) throws {
        try handle.write(contentsOf: data)
        offset += data.count
    }

    func overwrite(_ data: Data, at position: Int) throws {
        try handle.seek(toOffset: UInt64(position))
        try handle.write(contentsOf: data)
        try handle.seek(toOffset: UInt64(offset))
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }

    mutating func appendUInt32(_ value: UInt32) {
        appendUInt16(UInt16(truncatingIfNeeded: value))
        appendUInt16(UInt16(truncatingIfNeeded: value >> 16))
    }
}

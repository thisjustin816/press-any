import Foundation

/// Writes classic, single-disk ZIP archives with UTF-8 names and stored (uncompressed) data.
/// Zip64 is unsupported. The reader's public entry, archive, and payload limits also apply here.
public enum ZipArchiveWriter {
    public static func archive(entries: [ZipArchiveEntry]) throws -> Data {
        guard entries.count <= ZipArchiveReader.maximumEntries else { throw ZipArchiveError.tooManyEntries }
        try ZipArchiveFormat.validatePaths(entries.map(\.relativePath))
        var total = 0
        var archiveSize = 22
        for entry in entries {
            let nameSize = entry.relativePath.utf8.count
            guard nameSize <= Int(UInt16.max) else { throw ZipArchiveError.entryTooLarge(entry.relativePath) }
            guard !entry.relativePath.hasSuffix("/") || entry.data.isEmpty else { throw ZipArchiveError.damaged }
            try ZipArchiveFormat.validateSize(entry.data.count, path: entry.relativePath, total: &total)
            let recordSize = 76 + 2 * nameSize + entry.data.count
            guard recordSize <= ZipArchiveReader.maximumArchiveBytes - archiveSize else { throw ZipArchiveError.archiveTooLarge }
            archiveSize += recordSize
        }

        var archive = Data()
        archive.reserveCapacity(archiveSize)
        var directory = Data()
        for entry in entries {
            let name = Data(entry.relativePath.utf8)
            let size = UInt32(entry.data.count)
            let crc = ZipArchiveFormat.checksum(entry.data)
            let offset = UInt32(archive.count)
            archive.appendUInt32(0x0403_4b50)
            archive.appendUInt16(20)
            archive.appendUInt16(0x0800)
            archive.appendUInt16(0)
            archive.appendUInt16(0)
            archive.appendUInt16(0x0021) // DOS date: January 1, 1980.
            archive.appendUInt32(crc)
            archive.appendUInt32(size)
            archive.appendUInt32(size)
            archive.appendUInt16(UInt16(name.count))
            archive.appendUInt16(0)
            archive.append(name)
            archive.append(entry.data)

            directory.appendUInt32(0x0201_4b50)
            directory.appendUInt16(20)
            directory.appendUInt16(20)
            directory.appendUInt16(0x0800)
            directory.appendUInt16(0)
            directory.appendUInt16(0)
            directory.appendUInt16(0x0021)
            directory.appendUInt32(crc)
            directory.appendUInt32(size)
            directory.appendUInt32(size)
            directory.appendUInt16(UInt16(name.count))
            directory.appendUInt16(0)
            directory.appendUInt16(0)
            directory.appendUInt16(0)
            directory.appendUInt16(0)
            directory.appendUInt32(entry.relativePath.hasSuffix("/") ? 0x10 : 0)
            directory.appendUInt32(offset)
            directory.append(name)
        }
        let directoryOffset = UInt32(archive.count)
        archive.append(directory)
        archive.appendUInt32(0x0605_4b50)
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt16(UInt16(entries.count))
        archive.appendUInt16(UInt16(entries.count))
        archive.appendUInt32(UInt32(directory.count))
        archive.appendUInt32(directoryOffset)
        archive.appendUInt16(0)
        return archive
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

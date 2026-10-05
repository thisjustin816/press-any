import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public protocol FileOperations: Sendable {
    func createDirectory(at url: URL) throws
    func fileExists(at url: URL) -> Bool
    func write(_ data: Data, to url: URL) throws
    func synchronizeFile(at url: URL) throws
    func synchronizeDirectory(at url: URL) throws
    func moveItem(at source: URL, to destination: URL) throws
    func replaceItem(at destination: URL, with source: URL) throws
    func removeItemIfExists(at url: URL) throws
}

public struct FoundationFileOperations: FileOperations {
    // Computed, not stored: FileManager is not Sendable on Apple platforms, so storing it in this
    // Sendable struct fails to compile there even though Linux accepts it.
    private var fileManager: FileManager { .default }

    public init() {}

    public func createDirectory(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    public func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .withoutOverwriting)
    }

    public func synchronizeFile(at url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try Self.flushToStorage(handle.fileDescriptor)
    }

    /// Makes a rename in the directory durable; until then a power loss can bring back the old entry.
    public func synchronizeDirectory(at url: URL) throws {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        try Self.flushToStorage(descriptor)
    }

    /// On Apple platforms fsync only hands the data to the drive, which can still lose it from
    /// its cache on power loss; F_FULLFSYNC waits for the drive. Some file systems refuse
    /// F_FULLFSYNC, and fsync is the best they offer.
    private static func flushToStorage(_ descriptor: Int32) throws {
        #if canImport(Darwin)
        if fcntl(descriptor, F_FULLFSYNC) == 0 { return }
        #endif
        guard fsync(descriptor) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    public func moveItem(at source: URL, to destination: URL) throws {
        try fileManager.moveItem(at: source, to: destination)
    }

    public func replaceItem(at destination: URL, with source: URL) throws {
        let result = source.withUnsafeFileSystemRepresentation { sourcePath in
            destination.withUnsafeFileSystemRepresentation { destinationPath in
                guard let sourcePath, let destinationPath else { return Int32(-1) }
                return rename(sourcePath, destinationPath)
            }
        }
        guard result == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    public func removeItemIfExists(at url: URL) throws {
        guard fileExists(at: url) else { return }
        try fileManager.removeItem(at: url)
    }
}

public struct AtomicFileWriter: Sendable {
    private let fileOperations: any FileOperations

    public init(fileOperations: any FileOperations = FoundationFileOperations()) {
        self.fileOperations = fileOperations
    }

    public func write(_ data: Data, to destination: URL) throws {
        let directory = destination.deletingLastPathComponent()
        try fileOperations.createDirectory(at: directory)

        let temporary = directory.appendingPathComponent(".\(UUID().uuidString.lowercased()).tmp")
        do {
            try fileOperations.write(data, to: temporary)
            try fileOperations.synchronizeFile(at: temporary)

            if fileOperations.fileExists(at: destination) {
                try fileOperations.replaceItem(at: destination, with: temporary)
            } else {
                try fileOperations.moveItem(at: temporary, to: destination)
            }
        } catch {
            try? fileOperations.removeItemIfExists(at: temporary)
            throw error
        }
        // The new bytes are in place either way. Failing here would tell the caller the write
        // failed, and a caller that then restores the old file would lose the new one.
        try? fileOperations.synchronizeDirectory(at: directory)
    }
}

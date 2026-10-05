import Foundation

/// Files for import tests that check size limits and cleanup.
public enum ImportTestFiles {
    /// A file that reports `byteCount` bytes without writing them.
    @discardableResult
    public static func sparse(at url: URL, byteCount: UInt64) throws -> URL {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: byteCount)
        return url
    }

    /// What is left in a managed store's staging directory, which a finished or failed import
    /// should leave empty.
    public static func stagedItems(under rootURL: URL) -> [String] {
        let staging = rootURL.appendingPathComponent("Staging", isDirectory: true)
        return (try? FileManager.default.contentsOfDirectory(atPath: staging.path)) ?? []
    }
}

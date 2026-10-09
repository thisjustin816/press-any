import Foundation

/// A battery save is written to its file before the database learns its new hash, so a write the
/// app was stopped partway through would leave a good file that looks damaged. The hash the file is
/// about to have is written beside it first and removed once the database agrees, so a later load
/// can tell a finished write from a damaged file and complete it.
public struct PendingSaveWrite: Codable, Equatable, Sendable {
    public var sha256: String
    /// The Build whose game wrote the save, or nil when that isn't known.
    public var writtenByBuildID: UUID?

    public init(sha256: String, writtenByBuildID: UUID?) {
        self.sha256 = sha256
        self.writtenByBuildID = writtenByBuildID
    }
}

extension AssetStore {
    public func pendingSaveWriteURL(for saveURL: URL) -> URL {
        saveURL.appendingPathExtension("pending")
    }

    public func beginPendingSaveWrite(_ write: PendingSaveWrite, for saveURL: URL) throws {
        try writeDataAtomically(JSONEncoder().encode(write), to: pendingSaveWriteURL(for: saveURL))
    }

    public func endPendingSaveWrite(for saveURL: URL) {
        try? removeIfExists(pendingSaveWriteURL(for: saveURL))
    }

    /// The write that left the save at `saveURL` with this hash, when the app stopped before the
    /// database caught up. Nil when there's none or it was for other bytes, so a damaged file is
    /// never mistaken for one.
    public func pendingSaveWrite(for saveURL: URL, matching sha256: String) -> PendingSaveWrite? {
        let url = pendingSaveWriteURL(for: saveURL)
        guard fileExists(at: url), let data = try? readData(at: url),
              let write = try? JSONDecoder().decode(PendingSaveWrite.self, from: data),
              write.sha256 == sha256 else { return nil }
        return write
    }
}

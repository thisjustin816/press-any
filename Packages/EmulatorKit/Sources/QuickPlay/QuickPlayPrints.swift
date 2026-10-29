import EmulationCore
import EmulatorApplication
import Foundation

/// A Quick Play session's prints, kept in its folder as printer archives. They go with the session
/// when it expires, and move to the Game's Captures when it is added to the library.
public struct QuickPlayPrints: Sendable {
    private let session: QuickPlaySession
    private let files: any AssetStore

    public init(session: QuickPlaySession, files: any AssetStore) {
        self.session = session
        self.files = files
    }

    /// Saves the slip, or its longer paper when it is already saved.
    public func save(_ slip: PrinterSlip) throws {
        try files.writeDataAtomically(try PrinterSlipArchive.encode(slip), to: url(for: slip.id))
    }

    /// Removes the print from the session.
    public func discard(id: UUID) throws {
        try files.removeIfExists(url(for: id))
    }

    /// Oldest first, each with the time its file was first written.
    public func slips() throws -> [(slip: PrinterSlip, printedAt: Date)] {
        let folder = session.printsURL
        guard files.fileExists(at: folder) else { return [] }
        let keys: [URLResourceKey] = [.creationDateKey, .contentModificationDateKey]
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)
            .filter { $0.pathExtension == "print" }
            .compactMap { url -> (slip: PrinterSlip, printedAt: Date)? in
                guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { return nil }
                let values = try? url.resourceValues(forKeys: Set(keys))
                let date = values?.creationDate ?? values?.contentModificationDate ?? .distantPast
                return (try PrinterSlipArchive.decode(files.readData(at: url), id: id), date)
            }
            .sorted { $0.printedAt != $1.printedAt ? $0.printedAt < $1.printedAt : $0.slip.id.uuidString < $1.slip.id.uuidString }
    }

    private func url(for id: UUID) -> URL {
        session.printsURL.appendingPathComponent("\(id.uuidString.lowercased()).print")
    }
}

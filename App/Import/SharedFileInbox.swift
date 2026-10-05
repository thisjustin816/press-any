import AssetStorage
import EmulatorApplication
import Foundation

struct SharedFile: Identifiable {
    enum Kind {
        case rom
        case patch
    }

    let id: UUID
    let url: URL
    let originalFilename: String
    let kind: Kind
}

enum SharedFileError: LocalizedError {
    case unsupportedFile
    case notAFile

    var errorDescription: String? {
        switch self {
        case .unsupportedFile: "Choose a Game Boy ROM (.gb or .gbc) or a patch (.ips or .bps)."
        case .notAFile: "Only regular files can be opened. Folders and links aren’t supported."
        }
    }
}

/// Keeps incoming files available after the sending app releases its URL.
@MainActor
final class SharedFileInbox {
    private let store: ManagedFileStore
    private var ownedDirectories: [UUID: URL] = [:]

    init(store: ManagedFileStore) {
        self.store = store
    }

    func receive(_ url: URL) throws -> SharedFile {
        guard url.isFileURL else { throw SharedFileError.notAFile }
        let kind: SharedFile.Kind
        let limit: ImportSizeLimit
        switch url.pathExtension.lowercased() {
        case "gb", "gbc":
            kind = .rom
            limit = .rom
        case "ips", "bps":
            kind = .patch
            limit = .patch
        default:
            throw SharedFileError.unsupportedFile
        }
        let filename = url.lastPathComponent
        guard !filename.contains("/"), !filename.contains("\\") else { throw SharedFileError.notAFile }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw SharedFileError.notAFile }
        try limit.check(fileAt: url)
        let id = UUID()
        // stageCopy independently refuses links and gives each receipt an isolated directory.
        let staged = try store.stageCopy(from: url, transactionID: id)
        let directory = staged.deletingLastPathComponent()
        do {
            try limit.check(fileAt: staged)
            // A separate folder avoids a collision with "staged.gb" on case-insensitive storage.
            let receiptDirectory = directory.appendingPathComponent("Receipt", isDirectory: true)
            try FileManager.default.createDirectory(at: receiptDirectory, withIntermediateDirectories: true)
            let destination = receiptDirectory.appendingPathComponent(filename)
            try FileManager.default.moveItem(at: staged, to: destination)
            ownedDirectories[id] = directory
            return SharedFile(id: id, url: destination, originalFilename: filename, kind: kind)
        } catch {
            try? store.removeIfExists(directory)
            throw error
        }
    }

    func discard(_ file: SharedFile) {
        guard let directory = ownedDirectories.removeValue(forKey: file.id) else { return }
        try? store.removeIfExists(directory)
    }
}

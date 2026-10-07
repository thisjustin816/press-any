import AssetStorage
import EmulatorApplication
import Foundation
import Importing

struct SharedFile: Identifiable {
    enum Kind {
        case rom
        case patch
        case save
    }

    let id: UUID
    let url: URL
    let originalFilename: String
    let kind: Kind
}

enum SharedFileError: LocalizedError {
    case unsupportedFile
    case notAFile
    case emptyArchive

    var errorDescription: String? {
        switch self {
        case .unsupportedFile: "Choose a Game Boy ROM (.gb or .gbc), a patch (.ips or .bps), a save (.sav or .srm), or a zip holding them."
        case .notAFile: "Only regular files can be opened. Folders and links aren’t supported."
        case .emptyArchive: "This zip has no Game Boy ROM, patch or save in it."
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
        // A file from Files opens in place and is never touched here. Other apps hand over a copy in
        // Documents/Inbox; the receipt keeps its own copy, so that one goes whether or not the file
        // is accepted.
        defer { Self.removeIfInInbox(url) }
        guard let accepted = Self.kind(forExtension: url.pathExtension) else { throw SharedFileError.unsupportedFile }
        let filename = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        guard !filename.contains("/"), !filename.contains("\\") else { throw SharedFileError.notAFile }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try stage(url, filename: filename, kind: accepted.kind, limit: accepted.limit)
    }

    /// A zip yields each ROM, patch and save inside it, in the archive's order; anything else is a
    /// single file, as `receive` takes it.
    func receiveAll(_ url: URL) throws -> [SharedFile] {
        guard url.pathExtension.lowercased() == "zip" else { return [try receive(url)] }
        guard url.isFileURL else { throw SharedFileError.notAFile }
        defer { Self.removeIfInInbox(url) }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw SharedFileError.notAFile }
        try ImportSizeLimit.archive.check(fileAt: url)
        let staged = try store.stageCopy(from: url, transactionID: UUID())
        let directory = staged.deletingLastPathComponent()
        defer { try? store.removeIfExists(directory) }
        try ImportSizeLimit.archive.check(fileAt: staged)
        let entries = try ZipArchiveReader.entries(
            in: Data(contentsOf: staged),
            extensions: Set(Self.extensions.keys)
        ) { Self.kind(forExtension: $0)?.limit.bytes ?? 0 }
        guard !entries.isEmpty else { throw SharedFileError.emptyArchive }
        var files: [SharedFile] = []
        do {
            for entry in entries {
                guard let accepted = Self.kind(forExtension: (entry.filename as NSString).pathExtension) else { continue }
                let extracted = directory.appendingPathComponent(UUID().uuidString)
                try entry.data.write(to: extracted)
                files.append(try stage(extracted, filename: entry.filename, kind: accepted.kind, limit: accepted.limit))
            }
        } catch {
            files.forEach(discard)
            throw error
        }
        return files
    }

    private static let extensions: [String: (kind: SharedFile.Kind, limit: ImportSizeLimit)] = [
        "gb": (.rom, .rom), "gbc": (.rom, .rom),
        "ips": (.patch, .patch), "bps": (.patch, .patch),
        "sav": (.save, .batterySave), "srm": (.save, .batterySave),
    ]

    private static func kind(forExtension fileExtension: String) -> (kind: SharedFile.Kind, limit: ImportSizeLimit)? {
        extensions[fileExtension.lowercased()]
    }

    /// Copies a regular file into its own receipt folder under `filename`.
    private func stage(_ url: URL, filename: String, kind: SharedFile.Kind, limit: ImportSizeLimit) throws -> SharedFile {
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

    private static func removeIfInInbox(_ url: URL) {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let inbox = documents.appendingPathComponent("Inbox", isDirectory: true).resolvingSymlinksInPath().path + "/"
        guard url.resolvingSymlinksInPath().path.hasPrefix(inbox) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    func discard(_ file: SharedFile) {
        guard let directory = ownedDirectories.removeValue(forKey: file.id) else { return }
        try? store.removeIfExists(directory)
    }
}

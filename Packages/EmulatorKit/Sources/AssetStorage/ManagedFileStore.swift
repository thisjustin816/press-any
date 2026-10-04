import EmulatorApplication
import Foundation

public enum ManagedFileStoreError: Error, Equatable {
    case invalidSHA256(String)
    case unsafeRelativePath(String)
    case invalidFileExtension(String)
    case contentHashMismatch(expected: String, actual: String)
}

public struct ManagedFileStore: AssetStore, Sendable {
    public let rootURL: URL
    private let atomicWriter: AtomicFileWriter

    public init(rootURL: URL, atomicWriter: AtomicFileWriter = AtomicFileWriter()) throws {
        self.rootURL = rootURL.standardizedFileURL
        self.atomicWriter = atomicWriter
        try FileManager.default.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
    }

    public func stageCopy(from sourceURL: URL, transactionID: UUID) throws -> URL {
        let directory = rootURL
            .appendingPathComponent("Staging", isDirectory: true)
            .appendingPathComponent(transactionID.uuidString.lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let destination = directory.appendingPathComponent(sourceURL.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination
    }

    public func hashFile(at url: URL) throws -> String {
        try SHA256Digest.file(at: url)
    }

    public func hashData(_ data: Data) -> String {
        SHA256Digest.data(data)
    }

    public func sourceImageURL(sha256: String) throws -> URL {
        let normalizedHash = try validateSHA256(sha256)
        return rootURL
            .appendingPathComponent("Source/ROM", isDirectory: true)
            .appendingPathComponent(String(normalizedHash.prefix(2)), isDirectory: true)
            .appendingPathComponent("\(normalizedHash).rom")
    }

    public func commitSourceROM(stagedURL: URL, sha256: String) throws -> URL {
        try commitImmutableSource(
            stagedURL: stagedURL,
            sha256: sha256,
            relativeDirectory: "Source/ROM",
            filenameExtension: "rom"
        )
    }

    public func sourcePatchURL(sha256: String, extension fileExtension: String) throws -> URL {
        let normalizedHash = try validateSHA256(sha256)
        let normalizedExtension = try validateFileExtension(fileExtension)
        return rootURL
            .appendingPathComponent("Source/Patch", isDirectory: true)
            .appendingPathComponent(String(normalizedHash.prefix(2)), isDirectory: true)
            .appendingPathComponent("\(normalizedHash).\(normalizedExtension)")
    }

    public func commitSourcePatch(stagedURL: URL, sha256: String, extension fileExtension: String) throws -> URL {
        let normalizedExtension = try validateFileExtension(fileExtension)

        return try commitImmutableSource(
            stagedURL: stagedURL,
            sha256: sha256,
            relativeDirectory: "Source/Patch",
            filenameExtension: normalizedExtension
        )
    }

    public func variableMapURL(sha256: String, extension fileExtension: String) throws -> URL {
        let normalizedHash = try validateSHA256(sha256)
        let normalizedExtension = try validateFileExtension(fileExtension)
        return rootURL
            .appendingPathComponent("Source/VariableMap", isDirectory: true)
            .appendingPathComponent(String(normalizedHash.prefix(2)), isDirectory: true)
            .appendingPathComponent("\(normalizedHash).\(normalizedExtension)")
    }

    public func commitVariableMap(stagedURL: URL, sha256: String, extension fileExtension: String) throws -> URL {
        try commitImmutableSource(
            stagedURL: stagedURL,
            sha256: sha256,
            relativeDirectory: "Source/VariableMap",
            filenameExtension: try validateFileExtension(fileExtension)
        )
    }

    public func generatedImageURL(sha256: String) -> URL {
        let normalized = normalizedSHA256OrFallback(sha256)
        return rootURL
            .appendingPathComponent("Cache/GeneratedROM", isDirectory: true)
            .appendingPathComponent(String(normalized.prefix(2)), isDirectory: true)
            .appendingPathComponent("\(normalized).rom")
    }

    public func persistentSaveURL(profileID: UUID) -> URL {
        rootURL
            .appendingPathComponent("UserData/SaveProfiles", isDirectory: true)
            .appendingPathComponent(profileID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent("battery.sav")
    }

    public func artworkURL(gameID: UUID, sha256: String, extension fileExtension: String) throws -> URL {
        rootURL
            .appendingPathComponent("UserData/Artwork", isDirectory: true)
            .appendingPathComponent(gameID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent("\(try validateSHA256(sha256)).\(try validateFileExtension(fileExtension))")
    }

    public func stateURL(stateID: UUID) -> URL {
        rootURL
            .appendingPathComponent("UserData/States", isDirectory: true)
            .appendingPathComponent("\(stateID.uuidString.lowercased()).state")
    }

    public func quickPlayRoot(sessionID: UUID) -> URL {
        rootURL
            .appendingPathComponent("Temporary/QuickPlay", isDirectory: true)
            .appendingPathComponent(sessionID.uuidString.lowercased(), isDirectory: true)
    }

    public func quickPlaySessionIDs() throws -> [UUID] {
        let directory = rootURL.appendingPathComponent("Temporary/QuickPlay", isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            return UUID(uuidString: url.lastPathComponent)
        }
    }

    public func managedRelativePath(for url: URL) throws -> String {
        let candidate = url.standardizedFileURL
        let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        guard candidate.path.hasPrefix(rootPath) else {
            throw ManagedFileStoreError.unsafeRelativePath(candidate.path)
        }
        return String(candidate.path.dropFirst(rootPath.count))
    }

    public func managedURL(relativePath: String) throws -> URL {
        try resolveManagedPath(relativePath)
    }

    public func readData(at url: URL) throws -> Data {
        try Data(contentsOf: url, options: .mappedIfSafe)
    }

    public func writeDataAtomically(_ data: Data, to url: URL) throws {
        try atomicWriter.write(data, to: url)
    }

    public func copyFileAtomically(from source: URL, to destination: URL) throws {
        let data = try Data(contentsOf: source, options: .mappedIfSafe)
        try writeDataAtomically(data, to: destination)
    }

    public func fileByteLength(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func removeIfExists(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    public func resolveManagedPath(_ relativePath: String) throws -> URL {
        guard !relativePath.hasPrefix("/") else {
            throw ManagedFileStoreError.unsafeRelativePath(relativePath)
        }

        let candidate = rootURL.appendingPathComponent(relativePath).standardizedFileURL
        let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        guard candidate.path == rootURL.path || candidate.path.hasPrefix(rootPath) else {
            throw ManagedFileStoreError.unsafeRelativePath(relativePath)
        }
        return candidate
    }

    private func commitImmutableSource(
        stagedURL: URL,
        sha256: String,
        relativeDirectory: String,
        filenameExtension: String
    ) throws -> URL {
        let normalizedHash = try validateSHA256(sha256)
        let actualHash = try hashFile(at: stagedURL)
        guard actualHash == normalizedHash else {
            throw ManagedFileStoreError.contentHashMismatch(expected: normalizedHash, actual: actualHash)
        }

        let destination = rootURL
            .appendingPathComponent(relativeDirectory, isDirectory: true)
            .appendingPathComponent(String(normalizedHash.prefix(2)), isDirectory: true)
            .appendingPathComponent("\(normalizedHash).\(filenameExtension)")

        // A file already at the content-addressed path is reused only if it still has that
        // content. A damaged one is replaced, so importing the good file again repairs it.
        let damaged: Bool
        if FileManager.default.fileExists(atPath: destination.path) {
            guard (try? hashFile(at: destination)) != normalizedHash else { return destination }
            damaged = true
        } else {
            damaged = false
        }

        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".\(UUID().uuidString.lowercased()).tmp")
        do {
            try FileManager.default.copyItem(at: stagedURL, to: temporary)
            let handle = try FileHandle(forWritingTo: temporary)
            try handle.synchronize()
            try handle.close()

            if damaged {
                try FileManager.default.removeItem(at: destination)
            }
            do {
                try FileManager.default.moveItem(at: temporary, to: destination)
            } catch {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try? FileManager.default.removeItem(at: temporary)
                    return destination
                }
                throw error
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        return destination
    }

    private func validateFileExtension(_ value: String) throws -> String {
        let normalized = value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !normalized.isEmpty,
              normalized.count <= 12,
              normalized.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) else {
            throw ManagedFileStoreError.invalidFileExtension(value)
        }
        return normalized
    }

    private func validateSHA256(_ value: String) throws -> String {
        let normalized = value.lowercased()
        guard normalized.count == 64,
              normalized.utf8.allSatisfy({ byte in
                  (48...57).contains(byte) || (97...102).contains(byte)
              }) else {
            throw ManagedFileStoreError.invalidSHA256(value)
        }
        return normalized
    }

    private func normalizedSHA256OrFallback(_ value: String) -> String {
        (try? validateSHA256(value)) ?? value.lowercased()
    }
}

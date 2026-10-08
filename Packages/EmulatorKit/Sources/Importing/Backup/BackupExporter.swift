import EmulatorApplication
import EmulatorDomain
import Foundation

/// Writes a backup in three steps, so the database is read only while files are copied. Inside
/// one snapshot read it copies each carried file to staging. Outside the read it checks the
/// copies against their recorded hashes, then streams the zip and moves it into place.
struct BackupExporter {
    let repository: any LibraryBackupRepository
    let store: any AssetStore

    struct Request: Sendable {
        var gameID: UUID?
        var includeROMs: Bool
        /// Leaves a missing or damaged save, state or artwork file out instead of failing. The
        /// automatic backup before Replace uses this; it must capture what the library still has.
        var keepsDamagedFiles: Bool
        var filenameStem: @Sendable (LibraryBackupSnapshot) -> String
        var appVersion: String
        var appBuild: String
        /// Runs inside the snapshot read, before any file is copied.
        var check: @Sendable (LibraryBackupSnapshot) throws -> Void = { _ in }
    }

    private struct StagedFile {
        let asset: ManagedAsset
        let url: URL?
    }

    private struct StagedBackup {
        let snapshot: LibraryBackupSnapshot
        let files: [StagedFile]
    }

    static let omissions = ["Generated patched ROMs and image fingerprints", "Crash recovery checkpoints",
                            "Quick Play sessions, staged files, and Recently Deleted", "Device view preferences and launch markers"]

    static func carriesFile(_ asset: ManagedAsset, includesROMs: Bool) -> Bool {
        asset.kind != .generatedImage && asset.storageClass != .cache
            && (includesROMs || asset.kind != .sourceImage)
    }

    /// The archive size for `snapshot`, counting records, carried files and entry headers.
    static func estimatedArchiveBytes(_ snapshot: LibraryBackupSnapshot, includesROMs: Bool) throws -> Int64 {
        let records = try BackupSnapshotCodec.records(snapshot)
        let carried = snapshot.assets.filter { carriesFile($0, includesROMs: includesROMs) }
        let manifest = 1_024 + 160 * (records.count + carried.count)
        let payload = records.values.reduce(0) { $0 + $1.count } + carried.reduce(0) { $0 + Int($1.byteLength) } + manifest
        let paths = Array(records.keys) + carried.map(\.relativePath) + ["backup-manifest.json"]
        return Int64(ZipArchiveWriter.archiveByteLength(paths: paths, payloadBytes: payload))
    }

    func write(_ request: Request, to directory: URL, progress: @Sendable (Double) -> Void) throws -> URL {
        let staging = store.rootURL.appendingPathComponent("Staging/\(UUID().uuidString.lowercased())", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? store.removeIfExists(staging) }
        for attempt in 0..<2 {
            let copies = staging.appendingPathComponent("attempt-\(attempt)", isDirectory: true)
            try FileManager.default.createDirectory(at: copies, withIntermediateDirectories: true)
            let staged = try repository.readSnapshot { snapshot in
                try request.check(snapshot)
                return try stage(snapshot, request: request, to: copies, progress: progress)
            }
            // A battery save is written before its row changes, so a copy taken in between
            // differs from the row. A second read sees the finished save.
            if let verified = try verify(staged, request: request, finalAttempt: attempt == 1, progress: progress) {
                progress(0.6)
                let url = try writeArchive(staged.snapshot, files: verified, request: request, staging: staging, to: directory)
                progress(1)
                return url
            }
            try? store.removeIfExists(copies)
        }
        throw LibraryBackupError.gameIsSaving
    }

    private func stage(_ snapshot: LibraryBackupSnapshot, request: Request, to copies: URL,
                       progress: @Sendable (Double) -> Void) throws -> StagedBackup {
        let snapshot = try snapshot.scoped(to: request.gameID).backupOmittingExternalLineage()
        do {
            try BackupSnapshotCodec.validate(snapshot)
        } catch LibraryBackupError.invalidArchive(let reason) {
            throw LibraryBackupError.cannotBackUp(reason)
        }
        let estimate = try Self.estimatedArchiveBytes(snapshot, includesROMs: request.includeROMs)
        guard estimate <= LibraryBackupService.maximumArchiveBytes else { throw LibraryBackupError.backupTooLarge(estimate) }
        let carried = snapshot.assets.filter { Self.carriesFile($0, includesROMs: request.includeROMs) }
        var files: [StagedFile] = []
        for (index, asset) in carried.enumerated() {
            let source = try store.backupManagedURL(asset.relativePath)
            guard store.fileExists(at: source) else {
                files.append(StagedFile(asset: asset, url: nil))
                continue
            }
            let copy = copies.appendingPathComponent(String(index))
            try FileManager.default.copyItem(at: source, to: copy)
            files.append(StagedFile(asset: asset, url: copy))
            progress(Double(index + 1) / Double(max(1, carried.count)) * 0.2)
        }
        return StagedBackup(snapshot: snapshot, files: files)
    }

    private struct VerifiedFiles {
        var included: [(asset: ManagedAsset, url: URL)] = []
        var omissions: [String] = []
        var missingFiles: [String] = []
    }

    /// Nil asks for another read: a save or state copy differed from its row.
    private func verify(_ staged: StagedBackup, request: Request, finalAttempt: Bool,
                        progress: @Sendable (Double) -> Void) throws -> VerifiedFiles? {
        var result = VerifiedFiles()
        for (index, file) in staged.files.enumerated() {
            defer { progress(0.2 + Double(index + 1) / Double(max(1, staged.files.count)) * 0.4) }
            let asset = file.asset
            let name = asset.kind == .sourceImage
                ? asset.originalFilename ?? asset.contentSHA256 : staged.snapshot.describe(asset)
            guard let url = file.url else {
                if asset.kind == .sourceImage {
                    result.omissions.append("Missing ROM: \(name)")
                } else if request.keepsDamagedFiles {
                    result.omissions.append("Missing file left out: \(name)")
                    result.missingFiles.append(asset.relativePath)
                } else {
                    throw LibraryBackupError.missingLibraryFile(name)
                }
                continue
            }
            let matches = (try? store.fileByteLength(at: url)) == asset.byteLength
                && (try? store.hashFile(at: url)) == asset.contentSHA256
            if matches {
                result.included.append((asset, url))
                continue
            }
            if asset.kind == .sourceImage {
                result.omissions.append("Changed ROM left out: \(name)")
                continue
            }
            let isBeingSaved = asset.kind == .persistentSave || asset.kind == .saveState
            if isBeingSaved && !finalAttempt { return nil }
            if request.keepsDamagedFiles {
                result.omissions.append("Damaged file left out: \(name)")
                result.missingFiles.append(asset.relativePath)
            } else if isBeingSaved {
                throw LibraryBackupError.gameIsSaving
            } else {
                throw LibraryBackupError.damagedLibraryFile(name)
            }
        }
        return result
    }

    private func writeArchive(_ snapshot: LibraryBackupSnapshot, files: VerifiedFiles, request: Request,
                              staging: URL, to directory: URL) throws -> URL {
        let records = try BackupSnapshotCodec.records(snapshot)
        var inventory = records.mapValues { BackupFileInfo(sha256: store.hashData($0), byteLength: Int64($0.count)) }
        for file in files.included {
            inventory[file.asset.relativePath] = BackupFileInfo(sha256: file.asset.contentSHA256, byteLength: file.asset.byteLength)
        }
        var omissions = Self.omissions
        if !request.includeROMs { omissions.append("Source ROM files") }
        let manifest = LibraryBackupManifest(appVersion: request.appVersion, appBuild: request.appBuild,
            migrationID: snapshot.migrationID, createdAt: Date(), includesROMs: request.includeROMs,
            gameID: request.gameID, recordCounts: BackupSnapshotCodec.counts(snapshot),
            files: inventory, notCarriedOver: omissions + files.omissions, missingFiles: files.missingFiles.sorted())
        var items = records.map { ZipArchiveWriter.Item(relativePath: $0.key, content: .data($0.value)) }
        items += files.included.map { ZipArchiveWriter.Item(relativePath: $0.asset.relativePath, content: .file($0.url)) }
        items.append(ZipArchiveWriter.Item(relativePath: "backup-manifest.json",
            content: .data(try BackupSnapshotCodec.encoder().encode(manifest))))
        items.sort { $0.relativePath < $1.relativePath }
        let partial = staging.appendingPathComponent("backup.zip")
        do {
            try ZipArchiveWriter.write(items, to: partial)
        } catch ZipArchiveError.archiveTooLarge {
            throw LibraryBackupError.backupTooLarge(try Self.estimatedArchiveBytes(snapshot, includesROMs: request.includeROMs))
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let date = ISO8601DateFormatter().string(from: manifest.createdAt).replacingOccurrences(of: ":", with: "-")
        let filename = ExportLibraryFiles.safeFilename("\(request.filenameStem(snapshot)) \(date).zip")
        let url = ExportLibraryFiles.availableURL(for: filename, in: directory)
        try FileManager.default.moveItem(at: partial, to: url)
        return url
    }
}

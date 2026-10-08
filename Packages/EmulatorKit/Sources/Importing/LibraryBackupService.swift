import EmulatorApplication
import EmulatorDomain
import Foundation

public struct LibraryBackupService: Sendable {
    private let repository: any LibraryBackupRepository
    private let store: any AssetStore
    private let inFlight: InFlightFiles

    public init(repository: any LibraryBackupRepository, assetStore: any AssetStore,
                inFlight: InFlightFiles = InFlightFiles()) {
        self.repository = repository
        store = assetStore
        self.inFlight = inFlight
    }

    public func summary(gameID: UUID? = nil, includeROMs: Bool = false) throws -> BackupSummary {
        try repository.readSnapshot { snapshot in
            let snapshot = try snapshot.scoped(to: gameID)
            let records = try BackupSnapshotCodec.records(snapshot)
            let fileBytes = snapshot.assets.filter { carriesFile($0, includesROMs: includeROMs) }
                .reduce(Int64(0)) { $0 + $1.byteLength }
            return BackupSummary(recordCounts: BackupSnapshotCodec.counts(snapshot),
                approximateByteLength: fileBytes + Int64(records.values.reduce(0) { $0 + $1.count }))
        }
    }

    public func export(to directory: URL, displayName: String, appVersion: String, appBuild: String,
                       includeROMs: Bool = false, gameID: UUID? = nil,
                       progress: @escaping @Sendable (Double) -> Void = { _ in }) throws -> URL {
        try repository.readSnapshot { snapshot in
            try writeBackup(snapshot.scoped(to: gameID), to: directory, displayName: displayName,
                appVersion: appVersion, appBuild: appBuild, includeROMs: includeROMs, gameID: gameID, progress: progress)
        }
    }

    public func prepare(from url: URL) throws -> PreparedLibraryRestore {
        try ImportSizeLimit.archive.check(fileAt: url)
        let bytes = try Data(contentsOf: url)
        let entries = try ZipArchiveReader.backupEntries(in: bytes)
        guard let manifestEntry = entries.first(where: { $0.relativePath == "backup-manifest.json" }) else {
            throw LibraryBackupError.invalidArchive("no root manifest")
        }
        struct Version: Decodable { let formatVersion: Int }
        let version = try JSONDecoder().decode(Version.self, from: manifestEntry.data).formatVersion
        guard version <= LibraryBackupManifest.currentFormatVersion else { throw LibraryBackupError.newerFormat }
        guard version >= 1 else { throw LibraryBackupError.invalidArchive("invalid format version") }
        let manifest = try JSONDecoder().decode(LibraryBackupManifest.self, from: manifestEntry.data)
        guard !manifest.isEncrypted else { throw LibraryBackupError.encrypted }
        let files = Dictionary(uniqueKeysWithValues: entries.filter { !$0.relativePath.hasSuffix("/") }.map { ($0.relativePath, $0.data) })
        guard !manifest.files.keys.contains("backup-manifest.json"),
              Set(files.keys).subtracting(["backup-manifest.json"]) == Set(manifest.files.keys) else {
            let missing = manifest.files.keys.first { files[$0] == nil }
            if let missing { throw LibraryBackupError.missingFile(missing) }
            throw LibraryBackupError.invalidArchive("the file inventory does not match the manifest")
        }
        for (path, info) in manifest.files {
            guard let data = files[path] else { throw LibraryBackupError.missingFile(path) }
            guard info.byteLength >= 0, Int64(data.count) == info.byteLength, store.hashData(data) == info.sha256 else {
                throw LibraryBackupError.checksumMismatch(path)
            }
        }
        let snapshot = try BackupSnapshotCodec.decode(files, migrationID: manifest.migrationID)
        try BackupSnapshotCodec.validate(snapshot)
        let counts = BackupSnapshotCodec.counts(snapshot)
        for (kind, count) in manifest.recordCounts {
            guard counts[kind] == count else { throw LibraryBackupError.invalidArchive("record counts do not match") }
        }
        if manifest.isGamePackage {
            guard let id = manifest.gameID, snapshot.games.contains(where: { $0.id == id }) else {
                throw LibraryBackupError.invalidArchive("the Game package has no matching Game")
            }
        }
        let assetPaths = Set(snapshot.assets.map(\.relativePath))
        for path in manifest.files.keys where !BackupSnapshotCodec.recordFilenames.contains(path) && !assetPaths.contains(path) {
            throw LibraryBackupError.invalidArchive("unrecognized file \(path); update the app")
        }
        for asset in snapshot.assets {
            if carriesFile(asset, includesROMs: manifest.includesROMs) {
                guard let data = files[asset.relativePath] else {
                    if asset.kind == .sourceImage { continue }
                    throw LibraryBackupError.missingFile(asset.relativePath)
                }
                guard Int64(data.count) == asset.byteLength, store.hashData(data) == asset.contentSHA256 else {
                    throw LibraryBackupError.checksumMismatch(asset.relativePath)
                }
            } else if files[asset.relativePath] != nil {
                throw LibraryBackupError.invalidArchive("an excluded asset is present")
            }
        }
        return PreparedLibraryRestore(manifest: manifest, snapshot: snapshot, files: files)
    }

    public func review(_ prepared: PreparedLibraryRestore) throws -> LibraryRestoreReview {
        try repository.readSnapshot { snapshot in
            let (archive, leftAlone) = prepared.snapshot.leavingOut(snapshot.retained.recordIDs)
            var merge = BackupMerge(archive: archive, library: snapshot)
            _ = try merge.merged()
            return LibraryRestoreReview(snapshot: snapshot, added: merge.added, skipped: merge.skipped,
                conflicts: merge.conflicts, missingROMs: missingROMs(in: archive, files: prepared.files, library: snapshot),
                leftAlone: leftAlone)
        }
    }

    /// Writes the backup Replace Entire Library requires. It always includes ROMs: the incoming
    /// backup may not carry a Build the current library has, and Replace leaves no other copy.
    public func makeSafetyBackup(for prepared: PreparedLibraryRestore, review: LibraryRestoreReview,
                                 to directory: URL, displayName: String, appVersion: String, appBuild: String) throws -> URL {
        guard !prepared.manifest.isGamePackage else { throw LibraryBackupError.unsafeChoice("Game package replacement") }
        return try repository.readSnapshot { snapshot in
            try requireUnchanged(snapshot, review.snapshot)
            return try writeBackup(snapshot, to: directory, displayName: displayName,
                appVersion: appVersion, appBuild: appBuild, includeROMs: true,
                gameID: nil, progress: { _ in })
        }
    }

    public func restore(_ prepared: PreparedLibraryRestore, review: LibraryRestoreReview,
                        choices: [String: RestoreChoice], replaceEntireLibrary: Bool = false,
                        safetyBackupURL: URL? = nil,
                        progress: @escaping @Sendable (Double) -> Void = { _ in }) throws -> RestoreReport {
        if replaceEntireLibrary {
            guard !prepared.manifest.isGamePackage, let safetyBackupURL else { throw LibraryBackupError.safetyBackupRequired }
            let safety = try prepare(from: safetyBackupURL)
            try requireUnchanged(safety.snapshot, review.snapshot.backupOmittingExternalLineage(), includingRetained: false)
            guard safety.manifest.includesROMs, !safety.manifest.isGamePackage else { throw LibraryBackupError.safetyBackupRequired }
        }
        let library = try repository.readSnapshot { $0 }
        try requireUnchanged(library, review.snapshot)
        // Replacement clears Recently Deleted, so nothing in the backup has to be left alone.
        let (archive, leftAlone) = replaceEntireLibrary
            ? (prepared.snapshot, []) : prepared.snapshot.leavingOut(library.retained.recordIDs)
        var merge = BackupMerge(archive: archive, library: replaceEntireLibrary ? LibraryBackupSnapshot() : library)
        if !replaceEntireLibrary {
            for incoming in archive.builds {
                if let existing = library.builds.first(where: { $0.id == incoming.id }),
                   existing.imageSHA256 != incoming.imageSHA256 || existing.sourceKind != incoming.sourceKind {
                    throw LibraryBackupError.invalidArchive("a Build identity refers to different ROM bytes")
                }
            }
        }
        let merged = try merge.merged(choices: choices)
        let plan = try BackupRestorePlanner(store: store).plan(prepared: prepared, archive: archive,
            library: library,
            merged: merged, choices: choices, replacing: replaceEntireLibrary)
        let lease = inFlight.lease()
        for path in plan.files.keys { lease.hold(path) }
        for asset in library.assets { lease.hold(asset.relativePath) }
        defer { lease.end() }
        let transactionID = UUID()
        let stagingRoot = store.rootURL.appendingPathComponent("Staging/\(transactionID.uuidString.lowercased())", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        defer { try? store.removeIfExists(stagingRoot) }
        var staged: [String: URL] = [:]
        for (path, bytes) in plan.files {
            let temporary = stagingRoot.appendingPathComponent(UUID().uuidString)
            try store.writeDataAtomically(bytes, to: temporary)
            staged[path] = temporary
        }
        var created: [URL] = []
        do {
            let ordered = staged.keys.sorted()
            for (index, path) in ordered.enumerated() {
                let destination = try safeManagedURL(path)
                // A new path is mandatory even when an existing file is damaged. Rollback must
                // never have to recreate a file the player already owned.
                guard !store.fileExists(at: destination) else { throw LibraryBackupError.libraryChanged }
                created.append(destination)
                if let source = staged[path] { try store.copyFileAtomically(from: source, to: destination) }
                progress(Double(index + 1) / Double(max(1, ordered.count)) * 0.8)
            }
            let report = RestoreReport(restoredAt: Date(), added: merge.added, skipped: merge.skipped,
                resolutions: merge.conflicts.compactMap { conflict in
                    choices[conflict.id].map { RestoreResolution(record: "\(conflict.kind): \(conflict.name)", choice: $0) }
                }, missingROMs: missingROMs(in: plan.snapshot, files: plan.files, library: plan.snapshot),
                notCarriedOver: prepared.manifest.notCarriedOver + leftAloneNote(leftAlone) + plan.notes)
            let result = try repository.commitSnapshot(replacingLibrary: replaceEntireLibrary) { current in
                try requireUnchanged(current, review.snapshot)
                // The plan reuses rows that Recently Deleted records hold.
                guard current.retained.assets == library.retained.assets else { throw LibraryBackupError.libraryChanged }
                return (plan.snapshot, report, report)
            }
            progress(1)
            return result
        } catch {
            for url in created { try? store.removeIfExists(url) }
            throw error
        }
    }

    private func writeBackup(_ snapshot: LibraryBackupSnapshot, to directory: URL, displayName: String,
                             appVersion: String, appBuild: String, includeROMs: Bool, gameID: UUID?,
                             progress: @Sendable (Double) -> Void) throws -> URL {
        let snapshot = snapshot.backupOmittingExternalLineage()
        do {
            try BackupSnapshotCodec.validate(snapshot)
        } catch LibraryBackupError.invalidArchive(let reason) {
            throw LibraryBackupError.cannotBackUp(reason)
        }
        var files = try BackupSnapshotCodec.records(snapshot)
        var omissions = ["Generated patched ROMs and image fingerprints", "Crash recovery checkpoints",
                         "Quick Play sessions, staged files, and Recently Deleted", "Device view preferences and launch markers"]
        if !includeROMs { omissions.append("Source ROM files") }
        let included = snapshot.assets.filter { carriesFile($0, includesROMs: includeROMs) }
        var total = files.values.reduce(0) { $0 + $1.count }
        for (index, asset) in included.enumerated() {
            let url = try safeManagedURL(asset.relativePath)
            if !store.fileExists(at: url), asset.kind == .sourceImage {
                omissions.append("Missing ROM: \(asset.originalFilename ?? asset.contentSHA256)")
                continue
            }
            guard store.fileExists(at: url) else { throw LibraryBackupError.missingLibraryFile(asset.relativePath) }
            let bytes = try store.readData(at: url)
            guard Int64(bytes.count) == asset.byteLength, store.hashData(bytes) == asset.contentSHA256 else {
                throw LibraryBackupError.missingLibraryFile(asset.relativePath)
            }
            total += bytes.count
            try ImportSizeLimit.archive.check(byteCount: Int64(total))
            files[asset.relativePath] = bytes
            progress(Double(index + 1) / Double(max(1, included.count)) * 0.8)
        }
        let manifest = LibraryBackupManifest(appVersion: appVersion, appBuild: appBuild,
            migrationID: snapshot.migrationID, createdAt: Date(), includesROMs: includeROMs,
            gameID: gameID, recordCounts: BackupSnapshotCodec.counts(snapshot),
            files: files.mapValues { BackupFileInfo(sha256: store.hashData($0), byteLength: Int64($0.count)) },
            notCarriedOver: omissions)
        files["backup-manifest.json"] = try BackupSnapshotCodec.encoder().encode(manifest)
        let zip = try ZipArchiveWriter.archive(entries: files.sorted { $0.key < $1.key }.map { ZipArchiveEntry(relativePath: $0.key, data: $0.value) })
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let date = ISO8601DateFormatter().string(from: manifest.createdAt).replacingOccurrences(of: ":", with: "-")
        let filename = ExportLibraryFiles.safeFilename("\(displayName) Backup \(date).zip")
        let url = ExportLibraryFiles.availableURL(for: filename, in: directory)
        try store.writeDataAtomically(zip, to: url)
        progress(1)
        return url
    }

    private func safeManagedURL(_ path: String) throws -> URL {
        let url = try store.managedURL(relativePath: path)
        let root = store.rootURL.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        guard url.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(root) else {
            throw LibraryBackupError.invalidArchive("an asset path leaves the managed folder")
        }
        return url
    }

    private func carriesFile(_ asset: ManagedAsset, includesROMs: Bool) -> Bool {
        asset.kind != .generatedImage && asset.storageClass != .cache
            && (includesROMs || asset.kind != .sourceImage)
    }

    private func requireUnchanged(_ current: LibraryBackupSnapshot, _ reviewed: LibraryBackupSnapshot,
                                  includingRetained: Bool = true) throws {
        guard try BackupSnapshotCodec.canonical(current) == BackupSnapshotCodec.canonical(reviewed),
              !includingRetained || current.retained.recordIDs == reviewed.retained.recordIDs else {
            throw LibraryBackupError.libraryChanged
        }
    }

    private func leftAloneNote(_ names: [String]) -> [String] {
        guard !names.isEmpty else { return [] }
        let count = names.count == 1 ? "1 item" : "\(names.count) items"
        return ["\(count) in Recently Deleted or deleted for good were left alone: \(names.joined(separator: ", "))"]
    }

    private func missingROMs(in snapshot: LibraryBackupSnapshot, files: [String: Data],
                             library: LibraryBackupSnapshot) -> [RestoreMissingROM] {
        func available(_ asset: ManagedAsset) -> Bool {
            if let data = files[asset.relativePath], store.hashData(data) == asset.contentSHA256 { return true }
            let matches = library.assets.filter { $0.contentSHA256 == asset.contentSHA256 }
            return ([asset] + matches).contains { candidate in
                guard let url = try? safeManagedURL(candidate.relativePath), store.fileExists(at: url) else { return false }
                return (try? store.hashFile(at: url)) == candidate.contentSHA256
            }
        }
        func playable(_ build: Build, visited: Set<UUID>) -> Bool {
            guard !visited.contains(build.id), let image = snapshot.assets.first(where: { $0.id == build.imageAssetID }) else { return false }
            if available(image) { return true }
            guard build.sourceKind == .patchRecipe,
                  let recipe = snapshot.recipes.first(where: { $0.resultBuildID == build.id }),
                  let base = snapshot.builds.first(where: { $0.id == recipe.baseBuildID }),
                  recipe.items.filter(\.enabled).allSatisfy({ item in
                      snapshot.assets.first { $0.id == item.patchAssetID }.map(available) ?? false
                  }) else { return false }
            return playable(base, visited: visited.union([build.id]))
        }
        return snapshot.builds.filter { !playable($0, visited: []) }.map { RestoreMissingROM(id: $0.id, name: $0.displayName) }
    }
}

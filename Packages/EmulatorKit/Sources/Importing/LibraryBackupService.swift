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

    /// The largest backup or Game package this app writes or opens.
    public static let maximumArchiveBytes = Int64(ZipArchiveReader.maximumBackupArchiveBytes)

    public func summary(gameID: UUID? = nil, includeROMs: Bool = false) throws -> BackupSummary {
        try repository.readSnapshot { snapshot in
            let snapshot = try snapshot.scoped(to: gameID).backupOmittingExternalLineage()
            return BackupSummary(recordCounts: BackupSnapshotCodec.counts(snapshot),
                approximateByteLength: try BackupExporter.estimatedArchiveBytes(snapshot, includesROMs: includeROMs))
        }
    }

    public func export(to directory: URL, displayName: String, appVersion: String, appBuild: String,
                       includeROMs: Bool = false, gameID: UUID? = nil,
                       progress: @escaping @Sendable (Double) -> Void = { _ in }) throws -> URL {
        try BackupExporter(repository: repository, store: store).write(BackupExporter.Request(
            gameID: gameID, includeROMs: includeROMs, keepsDamagedFiles: false,
            filenameStem: { snapshot in
                // A Game package is named for its Game, so it never reads as a whole-library backup.
                gameID.flatMap { id in snapshot.games.first { $0.id == id }?.primaryTitle } ?? "\(displayName) Backup"
            }, appVersion: appVersion, appBuild: appBuild),
            to: directory, progress: progress)
    }

    public func prepare(from url: URL) throws -> PreparedLibraryRestore {
        let archive = try ZipArchiveReader.BackupArchive(contentsOf: url)
        guard archive.contains("backup-manifest.json") else {
            throw LibraryBackupError.invalidArchive("no root manifest")
        }
        let manifestData = try archive.data(at: "backup-manifest.json")
        struct Version: Decodable { let formatVersion: Int }
        let version = try JSONDecoder().decode(Version.self, from: manifestData).formatVersion
        guard version <= LibraryBackupManifest.currentFormatVersion else { throw LibraryBackupError.newerFormat }
        guard version >= 1 else { throw LibraryBackupError.invalidArchive("invalid format version") }
        let manifest = try JSONDecoder().decode(LibraryBackupManifest.self, from: manifestData)
        guard !manifest.isEncrypted else { throw LibraryBackupError.encrypted }
        let payload = Set(archive.paths.filter { !$0.hasSuffix("/") }).subtracting(["backup-manifest.json"])
        guard !manifest.files.keys.contains("backup-manifest.json"), payload == Set(manifest.files.keys) else {
            if let missing = manifest.files.keys.sorted().first(where: { !payload.contains($0) }) {
                throw LibraryBackupError.missingFile(missing)
            }
            throw LibraryBackupError.invalidArchive("the file inventory does not match the manifest")
        }
        guard Set(manifest.missingFiles).isDisjoint(with: manifest.files.keys) else {
            throw LibraryBackupError.invalidArchive("a file is listed as both present and missing")
        }
        // One entry at a time, so memory holds a single file however large the backup is.
        var records: [String: Data] = [:]
        for (path, info) in manifest.files.sorted(by: { $0.key < $1.key }) {
            guard info.byteLength >= 0, archive.byteLength(of: path).map(Int64.init) == info.byteLength else {
                throw LibraryBackupError.checksumMismatch(path)
            }
            let data = try archive.data(at: path)
            guard store.hashData(data) == info.sha256 else { throw LibraryBackupError.checksumMismatch(path) }
            if BackupSnapshotCodec.recordFilenames.contains(path) { records[path] = data }
        }
        let snapshot = try BackupSnapshotCodec.decode(records, migrationID: manifest.migrationID)
        try BackupSnapshotCodec.validate(snapshot)
        let counts = BackupSnapshotCodec.counts(snapshot)
        for (kind, count) in manifest.recordCounts {
            guard counts[kind] == count else { throw LibraryBackupError.invalidArchive("record counts do not match") }
        }
        if manifest.isGamePackage {
            guard let id = manifest.gameID, snapshot.games.contains(where: { $0.id == id }) else {
                throw LibraryBackupError.invalidArchive("the Game package has no matching Game")
            }
            // A package holds only what exporting its Game would write: no App or System settings
            // and no Game the package doesn't depend on.
            let scope = try snapshot.scoped(to: id).backupOmittingExternalLineage()
            guard try BackupSnapshotCodec.canonical(scope) == BackupSnapshotCodec.canonical(snapshot) else {
                throw LibraryBackupError.invalidArchive("the Game package holds records outside its Game")
            }
        }
        let assetPaths = Set(snapshot.assets.map(\.relativePath))
        for path in manifest.files.keys where !BackupSnapshotCodec.recordFilenames.contains(path) && !assetPaths.contains(path) {
            throw LibraryBackupError.invalidArchive("unrecognized file \(path); update the app")
        }
        for asset in snapshot.assets {
            if BackupExporter.carriesFile(asset, includesROMs: manifest.includesROMs) {
                guard let info = manifest.files[asset.relativePath] else {
                    if asset.kind == .sourceImage || manifest.missingFiles.contains(asset.relativePath) { continue }
                    throw LibraryBackupError.missingFile(asset.relativePath)
                }
                guard info.byteLength == asset.byteLength, info.sha256 == asset.contentSHA256 else {
                    throw LibraryBackupError.checksumMismatch(asset.relativePath)
                }
            } else if manifest.files[asset.relativePath] != nil {
                throw LibraryBackupError.invalidArchive("an excluded asset is present")
            }
        }
        return PreparedLibraryRestore(manifest: manifest, snapshot: snapshot, archive: archive)
    }

    public func review(_ prepared: PreparedLibraryRestore) throws -> LibraryRestoreReview {
        try repository.readSnapshot { snapshot in
            let (archive, leftAlone) = prepared.snapshot.leavingOut(snapshot.retained.recordIDs)
            var merge = BackupMerge(archive: archive, library: snapshot)
            _ = try merge.merged()
            return LibraryRestoreReview(snapshot: snapshot, added: merge.added, skipped: merge.skipped,
                conflicts: merge.conflicts, missingROMs: missingROMs(in: archive, hasFile: prepared.hasFile, library: snapshot),
                leftAlone: leftAlone)
        }
    }

    /// Writes the backup Replace Entire Library requires. It always includes ROMs: the incoming
    /// backup may not carry a Build the current library has, and Replace leaves no other copy.
    public func makeSafetyBackup(for prepared: PreparedLibraryRestore, review: LibraryRestoreReview,
                                 to directory: URL, displayName: String, appVersion: String, appBuild: String) throws -> URL {
        guard !prepared.manifest.isGamePackage else { throw LibraryBackupError.unsafeChoice("Game package replacement") }
        return try BackupExporter(repository: repository, store: store).write(BackupExporter.Request(
            gameID: nil, includeROMs: true, keepsDamagedFiles: true,
            filenameStem: { _ in "\(displayName) Backup" }, appVersion: appVersion, appBuild: appBuild,
            check: { try requireUnchanged($0, review.snapshot) }),
            to: directory, progress: { _ in })
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
        for (path, source) in plan.files {
            let temporary = stagingRoot.appendingPathComponent(UUID().uuidString)
            switch source {
            case .archive(let archived): try store.writeDataAtomically(prepared.fileData(archived), to: temporary)
            case .bytes(let bytes): try store.writeDataAtomically(bytes, to: temporary)
            }
            staged[path] = temporary
        }
        var created: [URL] = []
        do {
            let ordered = staged.keys.sorted()
            for (index, path) in ordered.enumerated() {
                let destination = try store.backupManagedURL(path)
                // A new path is mandatory even when an existing file is damaged. Rollback must
                // never have to recreate a file the player already owned.
                guard !store.fileExists(at: destination) else { throw LibraryBackupError.libraryChanged }
                created.append(destination)
                if let source = staged[path] { try store.copyFileAtomically(from: source, to: destination) }
                progress(Double(index + 1) / Double(max(1, ordered.count)) * 0.8)
            }
            let report = RestoreReport(restoredAt: Date(),
                added: Self.addedCount(plan.snapshot, comparedWith: replaceEntireLibrary ? LibraryBackupSnapshot() : library),
                skipped: merge.skipped,
                resolutions: merge.conflicts.compactMap { conflict in
                    choices[conflict.id].map { RestoreResolution(record: "\(conflict.kind): \(conflict.name)", choice: $0) }
                }, missingROMs: missingROMs(in: plan.snapshot, hasFile: { plan.files[$0] != nil }, library: plan.snapshot),
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

    private func requireUnchanged(_ current: LibraryBackupSnapshot, _ reviewed: LibraryBackupSnapshot,
                                  includingRetained: Bool = true) throws {
        guard try BackupSnapshotCodec.canonical(current) == BackupSnapshotCodec.canonical(reviewed),
              !includingRetained || current.retained.recordIDs == reviewed.retained.recordIDs else {
            throw LibraryBackupError.libraryChanged
        }
    }

    /// Records the restore creates, including copies kept as before restore or from backup.
    private static func addedCount(_ result: LibraryBackupSnapshot, comparedWith library: LibraryBackupSnapshot) -> Int {
        func count<T>(_ values: [T], _ existing: [T], _ key: (T) -> String) -> Int {
            let keys = Set(existing.map(key))
            return values.filter { !keys.contains(key($0)) }.count
        }
        return count(result.games, library.games) { $0.id.uuidString }
            + count(result.builds, library.builds) { $0.id.uuidString }
            + count(result.profiles, library.profiles) { $0.id.uuidString }
            + count(result.states, library.states) { $0.id.uuidString }
            + count(result.recipes, library.recipes) { $0.id.uuidString }
            + count(result.variableMaps, library.variableMaps) { $0.id.uuidString }
            + count(result.reports, library.reports) { $0.identity }
            + count(result.declarations, library.declarations, BackupSnapshotCodec.declarationID)
            + count(result.settings, library.settings) { $0.identity }
    }

    private func leftAloneNote(_ names: [String]) -> [String] {
        guard !names.isEmpty else { return [] }
        let count = names.count == 1 ? "1 item in Recently Deleted or deleted for good was" : "\(names.count) items in Recently Deleted or deleted for good were"
        return ["\(count) left alone: \(names.joined(separator: ", "))"]
    }

    /// `hasFile` says whether the restore brings bytes for a path; they were checked in prepare.
    private func missingROMs(in snapshot: LibraryBackupSnapshot, hasFile: (String) -> Bool,
                             library: LibraryBackupSnapshot) -> [RestoreMissingROM] {
        func available(_ asset: ManagedAsset) -> Bool {
            if hasFile(asset.relativePath) { return true }
            let matches = (library.assets + library.retained.assets).filter { $0.contentSHA256 == asset.contentSHA256 }
            return ([asset] + matches).contains { candidate in
                guard let url = try? store.backupManagedURL(candidate.relativePath), store.fileExists(at: url) else { return false }
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

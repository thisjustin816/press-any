import EmulatorApplication
import EmulatorDomain
import Foundation

/// Where a restored file's bytes come from: a verified archive entry, or library bytes already
/// read and checked against the reviewed hash.
enum BackupRestoreFile {
    case archive(String)
    case bytes(Data)
}

struct BackupRestorePlan {
    var snapshot: LibraryBackupSnapshot
    /// Keyed by destination path.
    var files: [String: BackupRestoreFile]
    /// Player-facing notes for the report, such as a damaged library file that had no copy kept.
    var notes: [String] = []
}

struct BackupRestorePlanner {
    let store: any AssetStore

    /// `archive` is the backup's snapshot without the records the library left alone.
    func plan(prepared: PreparedLibraryRestore, archive: LibraryBackupSnapshot, library: LibraryBackupSnapshot,
              merged: LibraryBackupSnapshot, choices: [String: RestoreChoice], replacing: Bool) throws -> BackupRestorePlan {
        var result = merged
        var files: [String: BackupRestoreFile] = [:]
        func archived(_ path: String) -> BackupRestoreFile? { prepared.hasFile(path) ? .archive(path) : nil }
        var notes: [String] = []
        var assets = library.assets
        // Recently Deleted records keep their rows, which still own their paths and hashes.
        let retained = library.retained.assets
        var mapping: [UUID: UUID] = [:]
        func selected(_ kind: String, _ id: UUID, _ existingIDs: Set<UUID>) -> Bool {
            replacing || !existingIDs.contains(id) || choices["\(kind)/\(id.uuidString)"] == .archive
        }
        func pathIsTaken(_ path: String) -> Bool {
            (assets + retained).contains { $0.relativePath.lowercased() == path.lowercased() } || files[path] != nil
        }
        /// Puts archive bytes back for a row whose file is missing or damaged. A damaged file is
        /// never overwritten, so the row moves to a new path.
        func repair(_ row: ManagedAsset, with incoming: ManagedAsset) throws {
            guard let bytes = archived(incoming.relativePath), !validFile(row) else { return }
            var repaired = row
            if store.fileExists(at: try store.managedURL(relativePath: row.relativePath)) {
                repaired = row.backupCopy(path: restoredPath(incoming))
            }
            assets.removeAll { $0.id == repaired.id }
            assets.append(repaired)
            files[repaired.relativePath] = bytes
        }
        for incoming in archive.assets {
            let existing = assets.first { $0.id == incoming.id }
            if incoming.storageClass == .source || incoming.kind == .generatedImage,
               let same = (assets + retained).first(where: { $0.kind == incoming.kind && $0.contentSHA256 == incoming.contentSHA256 }) {
                mapping[incoming.id] = same.id
                if !assets.contains(where: { $0.id == same.id }) { assets.append(same) }
                try repair(same, with: incoming)
                continue
            }
            if let existing, existing.contentSHA256 == incoming.contentSHA256 && existing.kind == incoming.kind {
                mapping[incoming.id] = existing.id
                try repair(existing, with: incoming)
                continue
            }
            let id = existing == nil && !retained.contains(where: { $0.id == incoming.id }) ? incoming.id : UUID()
            var path = incoming.relativePath
            let url = try store.managedURL(relativePath: path)
            let adoptable = !pathIsTaken(path) && validFile(incoming)
            if !adoptable && (store.fileExists(at: url) || pathIsTaken(path)) {
                path = restoredPath(incoming)
            }
            let imported = incoming.backupCopy(id: id, path: path)
            mapping[incoming.id] = imported.id
            assets.append(imported)
            if !adoptable, let bytes = archived(incoming.relativePath) { files[path] = bytes }
        }
        func mapped(_ id: UUID) -> UUID { mapping[id] ?? id }
        let gameIDs = Set(library.games.map(\.id)), buildIDs = Set(library.builds.map(\.id))
        let profileIDs = Set(library.profiles.map(\.id)), stateIDs = Set(library.states.map(\.id))
        let recipeIDs = Set(library.recipes.map(\.id)), mapIDs = Set(library.variableMaps.map(\.id))
        result.games = result.games.map { value in
            var value = value
            if selected("Game", value.id, gameIDs), let id = value.artworkAssetID { value.artworkAssetID = mapped(id) }
            return value
        }
        result.builds = result.builds.map { value in
            selected("Build", value.id, buildIDs)
                ? value.backupCopy(imageAssetID: mapped(value.imageAssetID), parentBuildID: value.parentBuildID) : value
        }
        result.profiles = result.profiles.map { value in
            var value = value
            if selected("Save Profile", value.id, profileIDs), let id = value.persistentSaveAssetID { value.persistentSaveAssetID = mapped(id) }
            return value
        }
        result.states = result.states.map { value in
            selected("Save State", value.id, stateIDs)
                ? value.backupCopy(assetID: mapped(value.stateAssetID), thumbnailID: value.screenshotAssetID.map(mapped)) : value
        }
        result.recipes = result.recipes.map { value in
            guard selected("Patch Recipe", value.id, recipeIDs) else { return value }
            return PatchRecipe(id: value.id, resultBuildID: value.resultBuildID, baseBuildID: value.baseBuildID,
                expectedResultSHA256: value.expectedResultSHA256, items: value.items.map {
                    PatchRecipeItem(position: $0.position, patchAssetID: mapped($0.patchAssetID), enabled: $0.enabled,
                        ignoresBaseMismatch: $0.ignoresBaseMismatch, expectedInputSHA256: $0.expectedInputSHA256)
                }, createdAt: value.createdAt)
        }
        result.variableMaps = result.variableMaps.map { value in
            guard selected("Variable Map", value.id, mapIDs) else { return value }
            return BuildVariableMap(id: value.id, buildID: value.buildID, assetID: mapped(value.assetID),
                format: value.format, source: value.source, originalFilename: value.originalFilename, attachedAt: value.attachedAt)
        }
        func copyAsset(_ original: ManagedAsset, path: String, bytes: BackupRestoreFile) -> UUID {
            let copy = original.backupCopy(id: UUID(), path: path)
            assets.append(copy)
            files[path] = bytes
            return copy.id
        }
        /// The library's current bytes, checked against the reviewed hash. A missing or damaged
        /// file has nothing left to keep, so the restore can repair over it.
        func savedBytes(_ asset: ManagedAsset) -> BackupRestoreFile? {
            guard let url = try? store.managedURL(relativePath: asset.relativePath), store.fileExists(at: url),
                  let bytes = try? store.readData(at: url), store.hashData(bytes) == asset.contentSHA256 else { return nil }
            return .bytes(bytes)
        }
        if !replacing {
            for incoming in archive.profiles {
                let choice = choices["Save Profile/\(incoming.id.uuidString)"]
                guard choice == .archive || choice == .keepBoth,
                      let current = library.profiles.first(where: { $0.id == incoming.id }) else { continue }
                let source = choice == .keepBoth ? incoming : current
                let sourceAssets = choice == .keepBoth ? archive.assets : library.assets
                let id = UUID()
                var assetID: UUID?
                if let sourceID = source.persistentSaveAssetID,
                   let sourceAsset = sourceAssets.first(where: { $0.id == sourceID }) {
                    let bytes: BackupRestoreFile
                    if choice == .keepBoth {
                        guard let file = archived(sourceAsset.relativePath) else { throw LibraryBackupError.missingFile(sourceAsset.relativePath) }
                        bytes = file
                    } else {
                        guard let saved = savedBytes(sourceAsset) else {
                            notes.append("The library's save for \(current.displayName) was missing or damaged, so no before restore copy was kept.")
                            continue
                        }
                        bytes = saved
                    }
                    assetID = copyAsset(sourceAsset, path: try store.managedRelativePath(for: store.persistentSaveURL(profileID: id)), bytes: bytes)
                }
                let suffix = choice == .keepBoth ? " from backup" : " before restore"
                let name = availableProfileName(source.displayName + suffix, gameID: source.gameID, in: result)
                result.profiles.append(source.backupCopy(id: id, name: name, assetID: assetID))
                if choice == .keepBoth {
                    result.states.removeAll { $0.saveProfileID == incoming.id && !stateIDs.contains($0.id) }
                    for state in archive.states where state.saveProfileID == incoming.id {
                        let newStateID = UUID()
                        guard let original = archive.assets.first(where: { $0.id == state.stateAssetID }),
                              let bytes = archived(original.relativePath) else { throw LibraryBackupError.missingFile(state.stateAssetID.uuidString) }
                        let stateAssetID = copyAsset(original, path: try store.managedRelativePath(for: store.stateURL(stateID: newStateID)), bytes: bytes)
                        var thumbnailID: UUID?
                        if let oldID = state.screenshotAssetID, let thumbnail = archive.assets.first(where: { $0.id == oldID }),
                           let bytes = archived(thumbnail.relativePath) {
                            thumbnailID = copyAsset(thumbnail, path: restoredPath(thumbnail), bytes: bytes)
                        }
                        result.states.append(state.backupCopy(id: newStateID, profileID: id, assetID: stateAssetID, thumbnailID: thumbnailID))
                    }
                }
            }
            for incoming in archive.states {
                let choice = choices["Save State/\(incoming.id.uuidString)"]
                guard choice == .archive || choice == .keepBoth,
                      let current = library.states.first(where: { $0.id == incoming.id }) else { continue }
                // Keeping both versions of the profile already copies its backup states.
                if choice == .keepBoth && choices["Save Profile/\(incoming.saveProfileID.uuidString)"] == .keepBoth { continue }
                let state = choice == .keepBoth ? incoming : current
                let sourceAssets = choice == .keepBoth ? archive.assets : library.assets
                guard let original = sourceAssets.first(where: { $0.id == state.stateAssetID }) else { continue }
                let bytes: BackupRestoreFile
                if choice == .keepBoth {
                    guard let file = archived(original.relativePath) else { throw LibraryBackupError.missingFile(original.relativePath) }
                    bytes = file
                } else {
                    guard let saved = savedBytes(original) else {
                        notes.append("The library's state \(current.displayName) was missing or damaged, so no before restore copy was kept.")
                        continue
                    }
                    bytes = saved
                }
                let id = UUID()
                let assetID = copyAsset(original, path: try store.managedRelativePath(for: store.stateURL(stateID: id)), bytes: bytes)
                var thumbnailID: UUID?
                if let oldID = state.screenshotAssetID, let thumbnail = sourceAssets.first(where: { $0.id == oldID }),
                   let bytes = choice == .keepBoth ? archived(thumbnail.relativePath) : savedBytes(thumbnail) {
                    thumbnailID = copyAsset(thumbnail, path: restoredPath(thumbnail), bytes: bytes)
                }
                result.states.append(state.backupCopy(id: id, assetID: assetID, thumbnailID: thumbnailID,
                    asManual: true, label: "\(state.displayName)\(choice == .keepBoth ? " from backup" : " before restore")"))
            }
        }
        // Library states come first, so a backup state that takes an occupied slot or a second
        // Quick State place for the same Build and profile is kept as a manual state.
        for index in result.states.indices {
            let state = result.states[index]
            let occupied = result.states[..<index].contains { other in
                guard other.buildID == state.buildID, other.saveProfileID == state.saveProfileID else { return false }
                switch state.kind {
                case .slot: return other.slot == state.slot
                case .quick: return other.kind == .quick
                default: return false
                }
            }
            guard occupied else { continue }
            result.states[index] = state.backupCopy(asManual: true, label: state.displayName + " from backup")
        }
        result.assets = assets.filter { result.referencedAssetIDs.contains($0.id) }
        let paths = Set(result.assets.map(\.relativePath))
        files = files.filter { paths.contains($0.key) }
        do {
            try BackupSnapshotCodec.validate(result, allowExternalLineage: !replacing,
                retainedIDs: replacing ? [] : library.retained.recordIDs)
        } catch LibraryBackupError.invalidArchive(let reason) {
            throw LibraryBackupError.conflictingChoices(reason)
        }
        return BackupRestorePlan(snapshot: result, files: files, notes: notes)
    }

    private func validFile(_ asset: ManagedAsset) -> Bool {
        guard let url = try? store.managedURL(relativePath: asset.relativePath), store.fileExists(at: url),
              let hash = try? store.hashFile(at: url) else { return false }
        return hash == asset.contentSHA256
    }

    private func restoredPath(_ asset: ManagedAsset) -> String {
        let folder = asset.storageClass == .source ? "Source" : asset.storageClass == .cache ? "Cache" : "UserData"
        return "\(folder)/Restored/\(UUID().uuidString.lowercased())/\((asset.relativePath as NSString).lastPathComponent)"
    }

    private func availableProfileName(_ name: String, gameID: UUID, in snapshot: LibraryBackupSnapshot) -> String {
        let names = Set(snapshot.profiles.filter { $0.gameID == gameID }.map(\.displayName))
        var candidate = name
        var number = 2
        while names.contains(candidate) { candidate = "\(name) \(number)"; number += 1 }
        return candidate
    }
}

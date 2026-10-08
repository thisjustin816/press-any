import EmulatorApplication
import EmulatorDomain
import Foundation

struct BackupMerge {
    let archive: LibraryBackupSnapshot
    let library: LibraryBackupSnapshot
    var added = 0
    var skipped = 0
    var conflicts: [LibraryRestoreConflict] = []

    mutating func records<T: Equatable>(
        _ incoming: [T], _ existing: [T], kind: String,
        key: (T) -> String, name: (T) -> String, date: (T) -> Date,
        equivalent: (T, T) -> Bool = { $0 == $1 },
        keepBoth: Bool = false, explicit: Bool = false,
        choices: [String: RestoreChoice]? = nil
    ) throws -> [T] {
        var result = existing
        for value in incoming {
            let identity = "\(kind)/\(key(value))"
            guard let index = result.firstIndex(where: { key($0) == key(value) }) else {
                result.append(value)
                added += 1
                continue
            }
            let previous = result[index]
            if equivalent(value, previous) { skipped += 1; continue }
            conflicts.append(LibraryRestoreConflict(id: identity, kind: kind, name: name(value),
                suggestedChoice: date(value) > date(previous) ? .archive : .library,
                allowsKeepBoth: keepBoth, requiresExplicitChoice: explicit))
            guard let choices else { continue }
            guard let choice = choices[identity] else { throw LibraryBackupError.unresolvedConflict(name(value)) }
            switch choice {
            case .library, .keepBoth:
                if choice == .keepBoth && !keepBoth { throw LibraryBackupError.unsafeChoice(name(value)) }
            case .archive: result[index] = value
            }
        }
        return result
    }

    mutating func merged(choices: [String: RestoreChoice]? = nil) throws -> LibraryBackupSnapshot {
        var result = library
        let archive = archive, library = library
        func hash(_ id: UUID?, _ snapshot: LibraryBackupSnapshot) -> String? {
            snapshot.assets.first { $0.id == id }?.contentSHA256
        }
        result.games = try records(archive.games, library.games, kind: "Game", key: { $0.id.uuidString },
            name: { $0.primaryTitle }, date: { $0.modifiedAt }, equivalent: { a, b in
                a == b && hash(a.artworkAssetID, archive) == hash(b.artworkAssetID, library)
                    && archive.gameProvenance.first { $0.ownerID == a.id } == library.gameProvenance.first { $0.ownerID == b.id }
            }, choices: choices)
        result.builds = try records(archive.builds, library.builds, kind: "Build", key: { $0.id.uuidString },
            name: { $0.displayName }, date: { $0.modifiedAt }, equivalent: { a, b in
                a == b && archive.buildProvenance.first { $0.ownerID == a.id } == library.buildProvenance.first { $0.ownerID == b.id }
            }, choices: choices)
        result.profiles = try records(archive.profiles, library.profiles, kind: "Save Profile", key: { $0.id.uuidString },
            name: { $0.displayName }, date: { $0.modifiedAt }, equivalent: { a, b in
                a == b && hash(a.persistentSaveAssetID, archive) == hash(b.persistentSaveAssetID, library)
            }, keepBoth: true, explicit: true, choices: choices)
        result.states = try records(archive.states, library.states, kind: "Save State", key: { $0.id.uuidString },
            name: { $0.displayName }, date: { $0.createdAt }, equivalent: { a, b in
                a == b && hash(a.stateAssetID, archive) == hash(b.stateAssetID, library)
                    && hash(a.screenshotAssetID, archive) == hash(b.screenshotAssetID, library)
            }, keepBoth: true, explicit: true, choices: choices)
        result.recipes = try records(archive.recipes, library.recipes, kind: "Patch Recipe", key: { $0.id.uuidString },
            name: { $0.id.uuidString }, date: { $0.createdAt }, choices: choices)
        result.variableMaps = try records(archive.variableMaps, library.variableMaps, kind: "Variable Map", key: { $0.id.uuidString },
            name: { $0.originalFilename }, date: { $0.attachedAt }, choices: choices)
        result.reports = try records(archive.reports, library.reports, kind: "Toolchain Report", key: { $0.identity },
            name: { $0.report.detector }, date: { $0.detectedAt }, choices: choices)
        result.declarations = try records(archive.declarations, library.declarations, kind: "Save Declaration",
            key: BackupSnapshotCodec.declarationID, name: BackupSnapshotCodec.declarationID,
            date: { _ in .distantPast }, choices: choices)
        result.settings = try records(archive.settings, library.settings, kind: "Setting", key: { $0.identity },
            name: { $0.identity }, date: { _ in .distantPast }, choices: choices)
        result.gameProvenance = ownerProvenance(archive.gameProvenance, library.gameProvenance, kind: "Game", choices: choices)
        result.buildProvenance = ownerProvenance(archive.buildProvenance, library.buildProvenance, kind: "Build", choices: choices)
        return result
    }

    private func ownerProvenance(_ incoming: [BackupProvenance], _ existing: [BackupProvenance],
                                 kind: String, choices: [String: RestoreChoice]?) -> [BackupProvenance] {
        var result = existing
        let ownerIDs: [UUID] = kind == "Game" ? archive.games.map(\.id) : archive.builds.map(\.id)
        let existingIDs = Set(kind == "Game" ? library.games.map(\.id) : library.builds.map(\.id))
        for id in ownerIDs where !existingIDs.contains(id) || choices?["\(kind)/\(id.uuidString)"] == .archive {
            result.removeAll { $0.ownerID == id }
            result += incoming.filter { $0.ownerID == id }
        }
        return result
    }
}

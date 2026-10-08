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
        let names = RecordNames(archive: archive, library: library)
        func hash(_ id: UUID?, _ snapshot: LibraryBackupSnapshot) -> String? {
            snapshot.assets.first { $0.id == id }?.contentSHA256
        }
        // A backup cannot carry pointers into Recently Deleted, so the library side is compared
        // the way it would be exported. The library keeps its pointers when nothing changes.
        let exported = library.backupOmittingExternalLineage()
        let exportedGames = Dictionary(exported.games.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let exportedBuilds = Dictionary(exported.builds.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let exportedProfiles = Dictionary(exported.profiles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        result.games = try records(archive.games, library.games, kind: "Game", key: { $0.id.uuidString },
            name: { $0.primaryTitle }, date: { $0.modifiedAt }, equivalent: { a, b in
                a == (exportedGames[b.id] ?? b) && hash(a.artworkAssetID, archive) == hash(b.artworkAssetID, library)
                    && archive.gameProvenance.first { $0.ownerID == a.id } == library.gameProvenance.first { $0.ownerID == b.id }
                    && archive.manualPositions.first { $0.gameID == a.id } == library.manualPositions.first { $0.gameID == b.id }
            }, choices: choices)
        result.manualPositions = library.manualPositions
        let existingGameIDs = Set(library.games.map(\.id))
        for game in archive.games where !existingGameIDs.contains(game.id) || choices?["Game/\(game.id.uuidString)"] == .archive {
            result.manualPositions.removeAll { $0.gameID == game.id }
            result.manualPositions += archive.manualPositions.filter { $0.gameID == game.id }
        }
        result.builds = try records(archive.builds, library.builds, kind: "Build", key: { $0.id.uuidString },
            name: { $0.displayName }, date: { $0.modifiedAt }, equivalent: { a, b in
                a == (exportedBuilds[b.id] ?? b) && archive.buildProvenance.first { $0.ownerID == a.id } == library.buildProvenance.first { $0.ownerID == b.id }
            }, choices: choices)
        result.profiles = try records(archive.profiles, library.profiles, kind: "Save Profile", key: { $0.id.uuidString },
            name: { $0.displayName }, date: { $0.modifiedAt }, equivalent: { a, b in
                a == (exportedProfiles[b.id] ?? b)
                    && hash(a.persistentSaveAssetID, archive) == hash(b.persistentSaveAssetID, library)
            }, keepBoth: true, explicit: true, choices: choices)
        result.states = try records(archive.states, library.states, kind: "Save State", key: { $0.id.uuidString },
            name: { $0.displayName }, date: { $0.createdAt }, equivalent: { a, b in
                a == b && hash(a.stateAssetID, archive) == hash(b.stateAssetID, library)
                    && hash(a.screenshotAssetID, archive) == hash(b.screenshotAssetID, library)
            }, keepBoth: true, explicit: true, choices: choices)
        result.recipes = try records(archive.recipes, library.recipes, kind: "Patch Recipe", key: { $0.id.uuidString },
            name: { "Recipe for \(names.build($0.resultBuildID))" }, date: { $0.createdAt }, choices: choices)
        result.variableMaps = try records(archive.variableMaps, library.variableMaps, kind: "Variable Map", key: { $0.id.uuidString },
            name: { $0.originalFilename }, date: { $0.attachedAt }, choices: choices)
        result.reports = try records(archive.reports, library.reports, kind: "Toolchain Report", key: { $0.identity },
            name: { "\($0.report.detector) for \(names.build($0.buildID))" }, date: { $0.detectedAt }, choices: choices)
        result.declarations = try records(archive.declarations, library.declarations, kind: "Save Declaration",
            key: BackupSnapshotCodec.declarationID, name: { [names.build($0.firstBuildID), names.build($0.secondBuildID)].sorted().joined(separator: " and ") },
            date: { _ in .distantPast }, choices: choices)
        result.settings = try records(archive.settings, library.settings, kind: "Setting", key: { $0.identity },
            name: names.setting, date: { _ in .distantPast }, choices: choices)
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

/// Player-facing names for conflicts, looked up in both snapshots.
private struct RecordNames {
    let archive: LibraryBackupSnapshot
    let library: LibraryBackupSnapshot

    func build(_ id: UUID) -> String {
        (archive.builds + library.builds).first { $0.id == id }?.displayName ?? "a Build"
    }

    /// "Skip boot animation (Moon Garden)" for a stored key such as `skipBootAnimation`.
    func setting(_ setting: BackupSetting) -> String {
        var words = ""
        for character in setting.key {
            if character == "." || character == "_" {
                words.append(" ")
            } else if character.isUppercase, !words.isEmpty, words.last != " " {
                words.append(" ")
                words.append(contentsOf: character.lowercased())
            } else {
                words.append(character)
            }
        }
        let label = words.prefix(1).uppercased() + words.dropFirst()
        let scope: String
        switch setting.scopeType {
        case "app": scope = "App"
        case "system": scope = setting.scopeID == GameSystem.gameBoyColor.rawValue ? "Game Boy Color" : "Game Boy"
        case "game":
            let id = UUID(uuidString: setting.scopeID)
            scope = (archive.games + library.games).first { $0.id == id }?.primaryTitle ?? "a Game"
        case "build": scope = UUID(uuidString: setting.scopeID).map(build) ?? "a Build"
        default: scope = setting.scopeType
        }
        return "\(label) (\(scope))"
    }
}

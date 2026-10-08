import EmulatorApplication
import EmulatorDomain
import Foundation

enum BackupSnapshotCodec {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func records(_ snapshot: LibraryBackupSnapshot) throws -> [String: Data] {
        let encoder = encoder()
        return [
            "games.json": try encoder.encode(snapshot.games),
            "manual-positions.json": try encoder.encode(snapshot.manualPositions),
            "builds.json": try encoder.encode(snapshot.builds),
            "profiles.json": try encoder.encode(snapshot.profiles),
            "states.json": try encoder.encode(snapshot.states),
            "recipes.json": try encoder.encode(snapshot.recipes),
            "variable-maps.json": try encoder.encode(snapshot.variableMaps),
            "cheats.json": try encoder.encode(snapshot.cheats),
            "managed-assets.json": try encoder.encode(snapshot.assets),
            "game-provenance.json": try encoder.encode(snapshot.gameProvenance),
            "build-provenance.json": try encoder.encode(snapshot.buildProvenance),
            "toolchain-reports.json": try encoder.encode(snapshot.reports),
            "save-declarations.json": try encoder.encode(snapshot.declarations),
            "settings.json": try encoder.encode(snapshot.settings),
        ]
    }

    static let recordFilenames: Set<String> = [
        "games.json", "manual-positions.json", "builds.json", "profiles.json", "states.json", "recipes.json",
        "variable-maps.json", "cheats.json", "managed-assets.json", "game-provenance.json", "build-provenance.json",
        "toolchain-reports.json", "save-declarations.json", "settings.json",
    ]

    static func decode(_ files: [String: Data], migrationID: String) throws -> LibraryBackupSnapshot {
        let decoder = JSONDecoder()
        func values<T: Decodable>(_ type: [T].Type, _ filename: String) throws -> [T] {
            guard let bytes = files[filename] else { return [] }
            return try decoder.decode(type, from: bytes)
        }
        var snapshot = LibraryBackupSnapshot(migrationID: migrationID)
        snapshot.games = try values([Game].self, "games.json")
        snapshot.manualPositions = try values([BackupManualPosition].self, "manual-positions.json")
        snapshot.builds = try values([Build].self, "builds.json")
        snapshot.profiles = try values([SaveProfile].self, "profiles.json")
        snapshot.states = try values([SaveState].self, "states.json")
        snapshot.recipes = try values([PatchRecipe].self, "recipes.json")
        snapshot.variableMaps = try values([BuildVariableMap].self, "variable-maps.json")
        snapshot.cheats = try values([BuildCheat].self, "cheats.json")
        snapshot.assets = try values([ManagedAsset].self, "managed-assets.json")
        snapshot.gameProvenance = try values([BackupProvenance].self, "game-provenance.json")
        snapshot.buildProvenance = try values([BackupProvenance].self, "build-provenance.json")
        snapshot.reports = try values([BackupToolchainReport].self, "toolchain-reports.json")
        snapshot.declarations = try values([BuildSaveDeclaration].self, "save-declarations.json")
        snapshot.settings = try values([BackupSetting].self, "settings.json")
        return snapshot
    }

    static func counts(_ snapshot: LibraryBackupSnapshot) -> [String: Int] {
        ["games": snapshot.games.count, "manualPositions": snapshot.manualPositions.count, "builds": snapshot.builds.count,
         "profiles": snapshot.profiles.count, "states": snapshot.states.count,
         "recipes": snapshot.recipes.count, "variableMaps": snapshot.variableMaps.count, "cheats": snapshot.cheats.count,
         "assets": snapshot.assets.count, "gameProvenance": snapshot.gameProvenance.count,
         "buildProvenance": snapshot.buildProvenance.count, "reports": snapshot.reports.count,
         "declarations": snapshot.declarations.count, "settings": snapshot.settings.count]
    }

    static func canonical(_ snapshot: LibraryBackupSnapshot) throws -> [String: Data] {
        var snapshot = snapshot
        snapshot.games.sort { $0.id.uuidString < $1.id.uuidString }
        snapshot.manualPositions.sort { $0.gameID.uuidString < $1.gameID.uuidString }
        snapshot.builds.sort { $0.id.uuidString < $1.id.uuidString }
        snapshot.profiles.sort { $0.id.uuidString < $1.id.uuidString }
        snapshot.states.sort { $0.id.uuidString < $1.id.uuidString }
        snapshot.recipes.sort { $0.id.uuidString < $1.id.uuidString }
        snapshot.variableMaps.sort { $0.id.uuidString < $1.id.uuidString }
        snapshot.cheats.sort { $0.id.uuidString < $1.id.uuidString }
        snapshot.assets.sort { $0.id.uuidString < $1.id.uuidString }
        snapshot.gameProvenance.sort { $0.ownerID.uuidString < $1.ownerID.uuidString }
        snapshot.buildProvenance.sort { $0.ownerID.uuidString < $1.ownerID.uuidString }
        snapshot.reports.sort { $0.identity < $1.identity }
        snapshot.declarations.sort { declarationID($0) < declarationID($1) }
        snapshot.settings.sort { $0.identity < $1.identity }
        return try records(snapshot)
    }

    static func declarationID(_ declaration: BuildSaveDeclaration) -> String {
        "\(declaration.firstBuildID.uuidString)/\(declaration.secondBuildID.uuidString)"
    }

    /// `allowExternalLineage` accepts copy and Game lineage that leads outside the snapshot.
    /// Optional pointers may also lead to `retainedIDs`, the destination's Recently Deleted records.
    static func validate(_ snapshot: LibraryBackupSnapshot, allowExternalLineage: Bool = false,
                         retainedIDs: Set<UUID> = []) throws {
        func unique<T>(_ values: [T], _ key: (T) -> String) throws {
            guard Set(values.map(key)).count == values.count else {
                throw LibraryBackupError.invalidArchive("duplicate record identities")
            }
        }
        try unique(snapshot.games) { $0.id.uuidString }
        try unique(snapshot.manualPositions) { $0.gameID.uuidString }
        try unique(snapshot.builds) { $0.id.uuidString }
        for game in snapshot.games {
            let images = snapshot.builds.filter { $0.gameID == game.id }.map(\.imageSHA256)
            guard Set(images).count == images.count else {
                throw LibraryBackupError.invalidArchive("\(game.primaryTitle) would have two Builds of the same ROM")
            }
        }
        try unique(snapshot.builds) { "\($0.gameID)/\($0.imageSHA256)" }
        try unique(snapshot.profiles) { $0.id.uuidString }
        try unique(snapshot.states) { $0.id.uuidString }
        try unique(snapshot.recipes) { $0.id.uuidString }
        try unique(snapshot.recipes) { $0.resultBuildID.uuidString }
        try unique(snapshot.variableMaps) { $0.id.uuidString }
        try unique(snapshot.cheats) { $0.id.uuidString }
        try unique(snapshot.assets) { $0.id.uuidString }
        try unique(snapshot.assets) { $0.relativePath.lowercased() }
        try unique(snapshot.gameProvenance) { $0.ownerID.uuidString }
        try unique(snapshot.buildProvenance) { $0.ownerID.uuidString }
        try unique(snapshot.reports) { $0.identity }
        try unique(snapshot.settings) { $0.identity }
        try unique(snapshot.declarations, declarationID)
        let games = Set(snapshot.games.map(\.id))
        let builds = Set(snapshot.builds.map(\.id))
        let profiles = Set(snapshot.profiles.map(\.id))
        let assets = Dictionary(uniqueKeysWithValues: snapshot.assets.map { ($0.id, $0) })
        func require(_ valid: Bool, _ reason: @autoclosure () -> String = "broken record references or invalid values") throws {
            guard valid else { throw LibraryBackupError.invalidArchive(reason()) }
        }
        func points(_ id: UUID?, into ids: Set<UUID>) -> Bool {
            id.map { ids.contains($0) || retainedIDs.contains($0) } ?? true
        }
        func asset(_ id: UUID?, kind: ManagedAssetKind? = nil) throws {
            guard let id else { return }
            try require(assets[id] != nil && (kind == nil || assets[id]?.kind == kind))
        }
        for value in snapshot.manualPositions {
            try require(games.contains(value.gameID) && value.position >= 0)
        }
        for game in snapshot.games {
            try asset(game.artworkAssetID, kind: .artwork)
            try require(allowExternalLineage || (game.lineage?.sourceGameID.map { games.contains($0) } ?? true))
            try require(points(game.preferredBuildID, into: Set(snapshot.builds.filter { $0.gameID == game.id }.map(\.id))),
                "the preferred Build of \(game.primaryTitle) would belong to another Game")
            try require(points(game.preferredSaveProfileID, into: Set(snapshot.profiles.filter { $0.gameID == game.id }.map(\.id))),
                "the preferred Save Profile of \(game.primaryTitle) would belong to another Game")
        }
        for build in snapshot.builds {
            try require(games.contains(build.gameID) && build.totalPlaytimeSeconds.isFinite && build.totalPlaytimeSeconds >= 0)
            try asset(build.imageAssetID, kind: build.sourceKind == .importedImage ? .sourceImage : .generatedImage)
            try require(assets[build.imageAssetID]?.contentSHA256 == build.imageSHA256)
            try require(points(build.parentBuildID, into: builds))
            try require(points(build.preferredSaveProfileID, into: profiles))
        }
        for profile in snapshot.profiles {
            try require(allowExternalLineage || (profile.copiedFromProfileID.map { profiles.contains($0) } ?? true))
            try require(games.contains(profile.gameID) && profile.totalPlaytimeSeconds.isFinite && profile.totalPlaytimeSeconds >= 0 && profile.sessionCount >= 0)
            try asset(profile.persistentSaveAssetID, kind: .persistentSave)
            try require(points(profile.saveWrittenByBuildID, into: builds))
        }
        for state in snapshot.states {
            try require(builds.contains(state.buildID) && profiles.contains(state.saveProfileID) && state.kind != .crashRecovery,
                "the state \(state.displayName) would lose its Build or Save Profile")
            try asset(state.stateAssetID, kind: .saveState)
            try asset(state.screenshotAssetID, kind: .stateThumbnail)
            try require(state.slot.map { state.kind == .slot && $0 > 0 } ?? true)
        }
        for recipe in snapshot.recipes {
            try require(builds.contains(recipe.resultBuildID) && builds.contains(recipe.baseBuildID) && recipe.resultBuildID != recipe.baseBuildID,
                "a patched Build would lose its base Build")
            try unique(recipe.items) { String($0.position) }
            for item in recipe.items {
                try asset(item.patchAssetID, kind: .sourcePatch)
                try require(item.position >= 0)
            }
        }
        for build in snapshot.builds where build.sourceKind == .patchRecipe {
            try require(snapshot.recipes.contains { $0.resultBuildID == build.id && $0.expectedResultSHA256 == build.imageSHA256 })
            var visited: Set<UUID> = [build.id]
            var cursor = build.id
            while let recipe = snapshot.recipes.first(where: { $0.resultBuildID == cursor }) {
                try require(visited.insert(recipe.baseBuildID).inserted)
                cursor = recipe.baseBuildID
            }
        }
        for map in snapshot.variableMaps {
            try require(builds.contains(map.buildID))
            try asset(map.assetID, kind: .variableMap)
        }
        for cheat in snapshot.cheats {
            try require(builds.contains(cheat.buildID), "the cheat \(cheat.name) would lose its Build")
            try require(cheat.position >= 0 && !cheat.codes.isEmpty
                && cheat.codes.allSatisfy { !$0.isEmpty && !$0.contains(where: \.isNewline) })
        }
        for value in snapshot.gameProvenance { try require(games.contains(value.ownerID)) }
        for value in snapshot.buildProvenance { try require(builds.contains(value.ownerID)) }
        for value in snapshot.reports { try require(builds.contains(value.buildID)) }
        for value in snapshot.declarations {
            try require(builds.contains(value.firstBuildID) && builds.contains(value.secondBuildID) && value.firstBuildID.uuidString < value.secondBuildID.uuidString)
        }
        for value in snapshot.assets {
            try require(value.byteLength >= 0 && value.contentSHA256.count == 64 && value.contentSHA256.allSatisfy { "0123456789abcdef".contains($0) })
            try require(value.storageClass != .temporary && value.kind != .quickPlayImage)
            let parts = value.relativePath.split(separator: "/", omittingEmptySubsequences: false)
            try require(parts.count > 1 && ["Source", "UserData", "Cache"].contains(String(parts[0])) && !parts.contains("") && !parts.contains(".") && !parts.contains("..") && !value.relativePath.contains("\\") && !value.relativePath.contains("\0"))
        }
        for value in snapshot.settings {
            try require(!value.key.isEmpty && !value.scopeType.isEmpty && !value.scopeID.isEmpty)
            switch value.scopeType {
            case "app": try require(value.scopeID == "app")
            case "system": try require(GameSystem(rawValue: value.scopeID) != nil)
            case "game": try require(UUID(uuidString: value.scopeID).map { games.contains($0) } ?? false)
            case "build": try require(UUID(uuidString: value.scopeID).map { builds.contains($0) } ?? false)
            default: throw LibraryBackupError.invalidArchive("unknown settings scope; update the app")
            }
            try require(!BackupSetting.excludedKeys.contains(value.key))
            _ = try JSONSerialization.jsonObject(with: Data(value.valueJSON.utf8), options: [.fragmentsAllowed])
        }
        for game in snapshot.games {
            try require(snapshot.builds.filter { $0.gameID == game.id && $0.isBase }.count <= 1,
                "\(game.primaryTitle) would have two Base Builds")
        }
    }
}

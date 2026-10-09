import EmulatorApplication
import EmulatorDomain
import Foundation

extension AssetStore {
    /// A managed URL that stays inside the managed folder after following links.
    func backupManagedURL(_ path: String) throws -> URL {
        let url = try managedURL(relativePath: path)
        let root = rootURL.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        guard url.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(root) else {
            throw LibraryBackupError.invalidArchive("an asset path leaves the managed folder")
        }
        return url
    }
}

extension ManagedAsset {
    func backupCopy(id: UUID? = nil, path: String? = nil) -> ManagedAsset {
        ManagedAsset(id: id ?? self.id, kind: kind, storageClass: storageClass,
            contentSHA256: contentSHA256, byteLength: byteLength, relativePath: path ?? relativePath,
            originalFilename: originalFilename, provenanceJSON: provenanceJSON,
            integrityStatus: integrityStatus, createdAt: createdAt)
    }
}

extension SaveProfile {
    func backupCopy(id: UUID, name: String, assetID: UUID?) -> SaveProfile {
        SaveProfile(id: id, gameID: gameID, displayName: name, badge: badge,
            persistentSaveAssetID: assetID, saveWrittenByBuildID: saveWrittenByBuildID,
            copiedFromProfileID: self.id, rtcContextJSON: rtcContextJSON,
            totalPlaytimeSeconds: totalPlaytimeSeconds, sessionCount: sessionCount,
            lastPlayedAt: lastPlayedAt, createdAt: createdAt, modifiedAt: modifiedAt)
    }
}

extension SaveState {
    func backupCopy(id: UUID? = nil, profileID: UUID? = nil, assetID: UUID? = nil,
                    thumbnailID: UUID? = nil, asManual: Bool = false, label: String? = nil) -> SaveState {
        SaveState(id: id ?? self.id, buildID: buildID, saveProfileID: profileID ?? saveProfileID,
            core: core, stateSerializationVersion: stateSerializationVersion,
            stateAssetID: assetID ?? stateAssetID, screenshotAssetID: thumbnailID ?? screenshotAssetID,
            kind: asManual ? .manual : kind, slot: asManual ? nil : slot,
            isPinned: asManual ? true : isPinned, isTimed: isTimed, autoSequence: asManual ? nil : autoSequence,
            label: label ?? self.label, playtimeSeconds: playtimeSeconds, createdAt: createdAt)
    }
}

extension LibraryBackupSnapshot {
    func scoped(to gameID: UUID?) throws -> LibraryBackupSnapshot {
        guard let gameID else { return self }
        guard games.contains(where: { $0.id == gameID }) else {
            throw LibraryBackupError.invalidArchive("the Game is no longer in the library")
        }
        var result = self
        var buildIDs = Set(builds.filter { $0.gameID == gameID }.map(\.id))
        var previous = Set<UUID>()
        while previous != buildIDs {
            previous = buildIDs
            for recipe in recipes where buildIDs.contains(recipe.resultBuildID) { buildIDs.insert(recipe.baseBuildID) }
            for build in builds where buildIDs.contains(build.id) {
                if let parent = build.parentBuildID { buildIDs.insert(parent) }
            }
        }
        result.builds = builds.filter { buildIDs.contains($0.id) }
        let gameIDs = Set(result.builds.map(\.gameID)).union([gameID])
        result.games = games.filter { gameIDs.contains($0.id) }
        result.manualPositions = manualPositions.filter { gameIDs.contains($0.gameID) }
        let selectedProfiles = Set(result.builds.compactMap(\.preferredSaveProfileID))
        result.profiles = profiles.filter { $0.gameID == gameID || selectedProfiles.contains($0.id) }
        let profileIDs = Set(result.profiles.map(\.id))
        result.games = result.games.map { game in
            var game = game
            if let id = game.preferredBuildID, !buildIDs.contains(id) { game.preferredBuildID = nil }
            if let id = game.preferredSaveProfileID, !profileIDs.contains(id) { game.preferredSaveProfileID = nil }
            if let id = game.lineage?.sourceGameID, !gameIDs.contains(id) { game.lineage?.sourceGameID = nil }
            return game
        }
        result.profiles = result.profiles.map { profile in
            var profile = profile
            if let id = profile.copiedFromProfileID, !profileIDs.contains(id) {
                profile = profile.backupWithoutCopyLineage()
            }
            if let id = profile.saveWrittenByBuildID, !buildIDs.contains(id) { profile.saveWrittenByBuildID = nil }
            return profile
        }
        result.states = states.filter { buildIDs.contains($0.buildID) && profileIDs.contains($0.saveProfileID) }
        result.recipes = recipes.filter { buildIDs.contains($0.resultBuildID) }
        result.variableMaps = variableMaps.filter { buildIDs.contains($0.buildID) }
        // A patch's base Build travels only so the patch can be rebuilt; its cheats stay behind.
        let ownBuildIDs = Set(builds.filter { $0.gameID == gameID }.map(\.id))
        result.cheats = cheats.filter { ownBuildIDs.contains($0.buildID) }
        result.gameProvenance = gameProvenance.filter { gameIDs.contains($0.ownerID) }
        result.buildProvenance = buildProvenance.filter { buildIDs.contains($0.ownerID) }
        result.reports = reports.filter { buildIDs.contains($0.buildID) }
        result.declarations = declarations.filter { buildIDs.contains($0.firstBuildID) && buildIDs.contains($0.secondBuildID) }
        result.settings = settings.filter { setting in
            switch setting.scopeType {
            case "game": UUID(uuidString: setting.scopeID).map { gameIDs.contains($0) } ?? false
            case "build": UUID(uuidString: setting.scopeID).map { buildIDs.contains($0) } ?? false
            case "saveProfile": UUID(uuidString: setting.scopeID).map { profileIDs.contains($0) } ?? false
            default: false
            }
        }
        result.assets = assets.filter { result.referencedAssetIDs.contains($0.id) }
        return result
    }

    /// Drops records the library keeps in Recently Deleted or deleted for good, with everything
    /// that depends on them, and names the dropped records the player would recognize.
    func leavingOut(_ deletedIDs: Set<UUID>) -> (snapshot: LibraryBackupSnapshot, leftAlone: [String]) {
        var leftAlone: [String] = []
        leftAlone += games.filter { deletedIDs.contains($0.id) }.map { "\($0.primaryTitle) (Game)" }
        leftAlone += builds.filter { deletedIDs.contains($0.id) }.map { "\($0.displayName) (Build)" }
        leftAlone += profiles.filter { deletedIDs.contains($0.id) }.map { "\($0.displayName) (Save Profile)" }
        leftAlone += states.filter { deletedIDs.contains($0.id) }.map { "\($0.displayName) (Save State)" }
        guard !leftAlone.isEmpty || recipes.contains(where: { deletedIDs.contains($0.id) })
                || variableMaps.contains(where: { deletedIDs.contains($0.id) })
                || cheats.contains(where: { deletedIDs.contains($0.id) || deletedIDs.contains($0.buildID) }) else {
            return (self, [])
        }
        var result = self
        result.games = games.filter { !deletedIDs.contains($0.id) }
        var gameIDs = Set(result.games.map(\.id))
        result.builds = builds.filter { !deletedIDs.contains($0.id) && gameIDs.contains($0.gameID) }
        result.recipes = recipes.filter { !deletedIDs.contains($0.id) }
        // A patched Build cannot stay without its recipe, nor a recipe without both Builds.
        while true {
            let buildIDs = Set(result.builds.map(\.id))
            result.recipes = result.recipes.filter { buildIDs.contains($0.resultBuildID) && buildIDs.contains($0.baseBuildID) }
            let resultIDs = Set(result.recipes.map(\.resultBuildID))
            let kept = result.builds.filter { $0.sourceKind != .patchRecipe || resultIDs.contains($0.id) }
            if kept.count == result.builds.count { break }
            result.builds = kept
        }
        gameIDs = Set(result.games.map(\.id))
        let buildIDs = Set(result.builds.map(\.id))
        result.manualPositions = manualPositions.filter { gameIDs.contains($0.gameID) }
        result.profiles = profiles.filter { !deletedIDs.contains($0.id) && gameIDs.contains($0.gameID) }
        let profileIDs = Set(result.profiles.map(\.id))
        result.states = states.filter {
            !deletedIDs.contains($0.id) && buildIDs.contains($0.buildID) && profileIDs.contains($0.saveProfileID)
        }
        result.variableMaps = variableMaps.filter { !deletedIDs.contains($0.id) && buildIDs.contains($0.buildID) }
        result.cheats = cheats.filter { !deletedIDs.contains($0.id) && buildIDs.contains($0.buildID) }
        let keptCheats = Set(result.cheats.map(\.id))
        leftAlone += cheats.filter { !keptCheats.contains($0.id) }.map { "\($0.name) (Cheat)" }
        result.gameProvenance = gameProvenance.filter { gameIDs.contains($0.ownerID) }
        result.buildProvenance = buildProvenance.filter { buildIDs.contains($0.ownerID) }
        result.reports = reports.filter { buildIDs.contains($0.buildID) }
        result.declarations = declarations.filter { buildIDs.contains($0.firstBuildID) && buildIDs.contains($0.secondBuildID) }
        result.settings = settings.filter { setting in
            switch setting.scopeType {
            case "game": UUID(uuidString: setting.scopeID).map { gameIDs.contains($0) } ?? false
            case "build": UUID(uuidString: setting.scopeID).map { buildIDs.contains($0) } ?? false
            default: true
            }
        }
        result = result.backupOmittingExternalLineage()
        result.assets = assets.filter { result.referencedAssetIDs.contains($0.id) }
        return (result, leftAlone)
    }

    /// Names an asset by what uses it, for messages and the report.
    func describe(_ asset: ManagedAsset) -> String {
        func game(_ id: UUID) -> String { games.first { $0.id == id }?.primaryTitle ?? "a Game" }
        if let profile = profiles.first(where: { $0.persistentSaveAssetID == asset.id }) {
            return "The save for \(profile.displayName) in \(game(profile.gameID))"
        }
        if let state = states.first(where: { $0.stateAssetID == asset.id || $0.screenshotAssetID == asset.id }) {
            let build = builds.first { $0.id == state.buildID }
            let owner = build.map { " in \(game($0.gameID))" } ?? ""
            return state.stateAssetID == asset.id ? "The state \(state.displayName)\(owner)" : "The picture for state \(state.displayName)\(owner)"
        }
        if let owner = games.first(where: { $0.artworkAssetID == asset.id }) { return "The artwork for \(owner.primaryTitle)" }
        if let build = builds.first(where: { $0.imageAssetID == asset.id }) { return "The ROM for \(build.displayName) in \(game(build.gameID))" }
        if let map = variableMaps.first(where: { $0.assetID == asset.id }) { return "The variable map \(map.originalFilename)" }
        return asset.originalFilename.map { "The file \($0)" } ?? "A library file"
    }

    var referencedAssetIDs: Set<UUID> {
        Set(games.compactMap(\.artworkAssetID))
            .union(builds.map(\.imageAssetID))
            .union(profiles.compactMap(\.persistentSaveAssetID))
            .union(states.map(\.stateAssetID))
            .union(states.compactMap(\.screenshotAssetID))
            .union(recipes.flatMap { $0.items.map(\.patchAssetID) })
            .union(variableMaps.map(\.assetID))
    }
}

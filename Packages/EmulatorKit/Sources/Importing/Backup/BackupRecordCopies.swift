import EmulatorApplication
import EmulatorDomain
import Foundation

extension ManagedAsset {
    func backupCopy(id: UUID? = nil, path: String? = nil) -> ManagedAsset {
        ManagedAsset(id: id ?? self.id, kind: kind, storageClass: storageClass,
            contentSHA256: contentSHA256, byteLength: byteLength, relativePath: path ?? relativePath,
            originalFilename: originalFilename, provenanceJSON: provenanceJSON,
            integrityStatus: integrityStatus, createdAt: createdAt)
    }
}

extension Build {
    func backupCopy(imageAssetID: UUID) -> Build {
        Build(id: id, gameID: gameID, system: system, displayName: displayName,
            imageAssetID: imageAssetID, imageSHA256: imageSHA256, imageSHA1: imageSHA1,
            sourceKind: sourceKind, parentBuildID: parentBuildID,
            isBase: isBase, region: region, language: language, revision: revision,
            versionString: versionString, versionSortKey: versionSortKey,
            baseGameReference: baseGameReference, baseTitle: baseTitle, hackTitle: hackTitle,
            author: author, translation: translation, status: status, notes: notes,
            totalPlaytimeSeconds: totalPlaytimeSeconds, preferredSaveProfileID: preferredSaveProfileID,
            corePin: corePin, createdAt: createdAt, modifiedAt: modifiedAt)
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
            isPinned: asManual ? true : isPinned, autoSequence: asManual ? nil : autoSequence,
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

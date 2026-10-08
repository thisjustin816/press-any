import EmulatorDomain
import Foundation

extension SaveProfile {
    public func backupWithoutCopyLineage() -> SaveProfile {
        SaveProfile(id: id, gameID: gameID, displayName: displayName, badge: badge,
            persistentSaveAssetID: persistentSaveAssetID, saveWrittenByBuildID: saveWrittenByBuildID,
            copiedFromProfileID: nil, rtcContextJSON: rtcContextJSON, totalPlaytimeSeconds: totalPlaytimeSeconds,
            sessionCount: sessionCount, lastPlayedAt: lastPlayedAt, createdAt: createdAt, modifiedAt: modifiedAt)
    }
}

extension Build {
    public func backupCopy(imageAssetID: UUID, parentBuildID: UUID?) -> Build {
        Build(id: id, gameID: gameID, system: system, displayName: displayName,
            imageAssetID: imageAssetID, imageSHA256: imageSHA256, imageSHA1: imageSHA1,
            sourceKind: sourceKind, parentBuildID: parentBuildID,
            isBase: isBase, region: region, language: language, revision: revision,
            versionString: versionString, versionSortKey: versionSortKey,
            baseGameReference: baseGameReference, baseTitle: baseTitle, hackTitle: hackTitle,
            author: author, translation: translation, status: status, notes: notes,
            totalPlaytimeSeconds: totalPlaytimeSeconds, preferredSaveProfileID: preferredSaveProfileID,
            corePin: corePin, cheatsEnabled: cheatsEnabled, createdAt: createdAt, modifiedAt: modifiedAt)
    }
}

// Pointers can lead into Recently Deleted, which never travels in a backup. Export, the
// comparison that verifies a safety backup, and merge's identical-record check all use this.
extension LibraryBackupSnapshot {
    public func backupOmittingExternalLineage() -> LibraryBackupSnapshot {
        var result = self
        let profileIDs = Set(profiles.map(\.id))
        let gameIDs = Set(games.map(\.id))
        let buildIDs = Set(builds.map(\.id))
        let buildGames = Dictionary(builds.map { ($0.id, $0.gameID) }, uniquingKeysWith: { first, _ in first })
        let profileGames = Dictionary(profiles.map { ($0.id, $0.gameID) }, uniquingKeysWith: { first, _ in first })
        result.profiles = profiles.map { profile in
            var profile = profile
            if let id = profile.copiedFromProfileID, !profileIDs.contains(id) { profile = profile.backupWithoutCopyLineage() }
            if let id = profile.saveWrittenByBuildID, !buildIDs.contains(id) { profile.saveWrittenByBuildID = nil }
            return profile
        }
        result.builds = builds.map { build in
            var build = build
            if let id = build.parentBuildID, !buildIDs.contains(id) {
                build = build.backupCopy(imageAssetID: build.imageAssetID, parentBuildID: nil)
            }
            if let id = build.preferredSaveProfileID, !profileIDs.contains(id) { build.preferredSaveProfileID = nil }
            return build
        }
        result.games = games.map { game in
            var game = game
            if let id = game.lineage?.sourceGameID, !gameIDs.contains(id) { game.lineage?.sourceGameID = nil }
            if let id = game.preferredBuildID, buildGames[id] != game.id { game.preferredBuildID = nil }
            if let id = game.preferredSaveProfileID, profileGames[id] != game.id { game.preferredSaveProfileID = nil }
            return game
        }
        result.declarations = declarations.filter { buildIDs.contains($0.firstBuildID) && buildIDs.contains($0.secondBuildID) }
        return result
    }
}

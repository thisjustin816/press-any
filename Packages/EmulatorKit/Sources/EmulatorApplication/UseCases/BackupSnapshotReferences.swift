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

// Lineage can point into Recently Deleted, which never travels in a backup.
extension LibraryBackupSnapshot {
    public func backupOmittingExternalLineage() -> LibraryBackupSnapshot {
        var result = self
        let profileIDs = Set(profiles.map(\.id))
        let gameIDs = Set(games.map(\.id))
        result.profiles = profiles.map { profile in
            if let id = profile.copiedFromProfileID, !profileIDs.contains(id) {
                return profile.backupWithoutCopyLineage()
            }
            return profile
        }
        result.games = games.map { game in
            var game = game
            if let id = game.lineage?.sourceGameID, !gameIDs.contains(id) { game.lineage?.sourceGameID = nil }
            return game
        }
        return result
    }
}

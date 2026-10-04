import Foundation

public struct SaveProfile: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var gameID: UUID
    public var displayName: String
    public var badge: String?
    public var persistentSaveAssetID: UUID?
    /// The Build that last wrote the battery save, so a different Build can be checked before it
    /// uses the save. Nil when that isn't known, as for an imported `.sav`.
    public var saveWrittenByBuildID: UUID?
    public let copiedFromProfileID: UUID?
    public var rtcContextJSON: String?
    public var totalPlaytimeSeconds: Double
    public var sessionCount: Int
    public var lastPlayedAt: Date?
    public let createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID,
        gameID: UUID,
        displayName: String,
        badge: String? = nil,
        persistentSaveAssetID: UUID? = nil,
        saveWrittenByBuildID: UUID? = nil,
        copiedFromProfileID: UUID? = nil,
        rtcContextJSON: String? = nil,
        totalPlaytimeSeconds: Double = 0,
        sessionCount: Int = 0,
        lastPlayedAt: Date? = nil,
        createdAt: Date,
        modifiedAt: Date
    ) {
        self.id = id
        self.gameID = gameID
        self.displayName = displayName
        self.badge = badge
        self.persistentSaveAssetID = persistentSaveAssetID
        self.saveWrittenByBuildID = saveWrittenByBuildID
        self.copiedFromProfileID = copiedFromProfileID
        self.rtcContextJSON = rtcContextJSON
        self.totalPlaytimeSeconds = totalPlaytimeSeconds
        self.sessionCount = sessionCount
        self.lastPlayedAt = lastPlayedAt
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

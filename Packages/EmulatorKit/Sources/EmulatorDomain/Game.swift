import Foundation

/// Where a Game split off from: the Game a Build was promoted out of. The title is kept so the
/// lineage still reads after that Game is gone.
public struct GameLineage: Codable, Equatable, Sendable {
    /// Nil once the source Game is deleted.
    public var sourceGameID: UUID?
    public var sourceTitle: String

    public init(sourceGameID: UUID?, sourceTitle: String) {
        self.sourceGameID = sourceGameID
        self.sourceTitle = sourceTitle
    }
}

public struct Game: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var primaryTitle: String
    public let systemFamily: String
    public var preferredBuildID: UUID?
    public var preferredSaveProfileID: UUID?
    /// Manually assigned cover art, a user-data asset.
    public var artworkAssetID: UUID?
    public var lineage: GameLineage?
    public let createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID,
        primaryTitle: String,
        systemFamily: String,
        preferredBuildID: UUID? = nil,
        preferredSaveProfileID: UUID? = nil,
        artworkAssetID: UUID? = nil,
        lineage: GameLineage? = nil,
        createdAt: Date,
        modifiedAt: Date
    ) {
        self.id = id
        self.primaryTitle = primaryTitle
        self.systemFamily = systemFamily
        self.preferredBuildID = preferredBuildID
        self.preferredSaveProfileID = preferredSaveProfileID
        self.artworkAssetID = artworkAssetID
        self.lineage = lineage
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

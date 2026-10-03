import Foundation

public struct Game: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var primaryTitle: String
    public let systemFamily: String
    public var preferredBuildID: UUID?
    public var preferredSaveProfileID: UUID?
    /// Manually assigned cover art, a user-data asset.
    public var artworkAssetID: UUID?
    public let createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID,
        primaryTitle: String,
        systemFamily: String,
        preferredBuildID: UUID? = nil,
        preferredSaveProfileID: UUID? = nil,
        artworkAssetID: UUID? = nil,
        createdAt: Date,
        modifiedAt: Date
    ) {
        self.id = id
        self.primaryTitle = primaryTitle
        self.systemFamily = systemFamily
        self.preferredBuildID = preferredBuildID
        self.preferredSaveProfileID = preferredSaveProfileID
        self.artworkAssetID = artworkAssetID
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

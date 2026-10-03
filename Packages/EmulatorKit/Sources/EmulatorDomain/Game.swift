import Foundation

public struct Game: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var primaryTitle: String
    public let systemFamily: String
    public var preferredBuildID: UUID?
    public var preferredSaveProfileID: UUID?
    public let createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID,
        primaryTitle: String,
        systemFamily: String,
        preferredBuildID: UUID? = nil,
        preferredSaveProfileID: UUID? = nil,
        createdAt: Date,
        modifiedAt: Date
    ) {
        self.id = id
        self.primaryTitle = primaryTitle
        self.systemFamily = systemFamily
        self.preferredBuildID = preferredBuildID
        self.preferredSaveProfileID = preferredSaveProfileID
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

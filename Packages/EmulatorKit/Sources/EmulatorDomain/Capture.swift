import Foundation

/// What a Captures item holds. Screenshots join prints later.
public enum CaptureKind: String, Codable, Sendable {
    case print
}

/// A print kept in its Game's Captures. It belongs to the Game: the Build and Save Profile it was
/// made with are kept for filtering, and either may since have been deleted. Its paper is stored
/// as the printer's own rows in the managed file `assetID` names, so any background can be chosen
/// when it is exported.
public struct Capture: Identifiable, Codable, Equatable, Sendable {
    /// Unpinned prints a Game keeps; older ones go to Recently Deleted.
    public static let keepCount = 50

    public let id: UUID
    public let gameID: UUID
    public let buildID: UUID?
    public let saveProfileID: UUID?
    public let kind: CaptureKind
    public let assetID: UUID
    public var isPinned: Bool
    public let createdAt: Date
    /// Changes when a print that leaves its paper attached gets more paper.
    public var modifiedAt: Date

    public init(
        id: UUID,
        gameID: UUID,
        buildID: UUID?,
        saveProfileID: UUID?,
        kind: CaptureKind,
        assetID: UUID,
        isPinned: Bool = false,
        createdAt: Date,
        modifiedAt: Date
    ) {
        self.id = id
        self.gameID = gameID
        self.buildID = buildID
        self.saveProfileID = saveProfileID
        self.kind = kind
        self.assetID = assetID
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

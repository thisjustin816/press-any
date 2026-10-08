import Foundation

/// A cheat belongs to one Build, because its codes depend on that Build's exact ROM. All of its
/// codes apply together.
public struct BuildCheat: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let buildID: UUID
    public var name: String
    /// Game Genie or GameShark codes, one per line as the player typed them.
    public var codes: [String]
    public var isEnabled: Bool
    /// Its place in the Build's list, counted from 0.
    public var position: Int
    public let createdAt: Date
    public var modifiedAt: Date

    public init(id: UUID, buildID: UUID, name: String, codes: [String], isEnabled: Bool = true,
                position: Int, createdAt: Date, modifiedAt: Date) {
        self.id = id
        self.buildID = buildID
        self.name = name
        self.codes = codes
        self.isEnabled = isEnabled
        self.position = position
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

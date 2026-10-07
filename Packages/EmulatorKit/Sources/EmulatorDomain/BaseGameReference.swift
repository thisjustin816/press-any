import Foundation

/// A player-confirmed base game, even when its ROM is absent. No image or patch compatibility is implied.
public struct BaseGameReference: Codable, Equatable, Sendable {
    public let title: String
    public let system: GameSystem
    public let familyName: String?
    public let releaseName: String?
    public let libraryGameID: UUID?

    public init(title: String, system: GameSystem, familyName: String? = nil, releaseName: String? = nil, libraryGameID: UUID? = nil) {
        self.title = title
        self.system = system
        self.familyName = familyName
        self.releaseName = releaseName
        self.libraryGameID = libraryGameID
    }
}

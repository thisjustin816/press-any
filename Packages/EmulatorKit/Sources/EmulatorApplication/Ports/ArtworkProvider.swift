import EmulatorDomain
import Foundation

public struct ArtworkLookup: Equatable, Sendable {
    public let system: GameSystem
    public let releaseNames: [String]
    public let inherited: Bool

    public init(system: GameSystem, releaseNames: [String], inherited: Bool) {
        self.system = system
        self.releaseNames = releaseNames
        self.inherited = inherited
    }
}

/// Kept with the selected managed asset, including in backups and copies between Games.
public struct ArtworkProvenance: Codable, Equatable, Sendable {
    public let provider: String
    public let sourceURL: URL
    public let fetchedAt: Date
    public let rights: String
    public let inheritedFrom: String?

    public init(provider: String, sourceURL: URL, fetchedAt: Date, rights: String, inheritedFrom: String? = nil) {
        self.provider = provider
        self.sourceURL = sourceURL
        self.fetchedAt = fetchedAt
        self.rights = rights
        self.inheritedFrom = inheritedFrom
    }
}

public struct ProvidedArtwork: Sendable {
    public let data: Data
    public let fileExtension: String
    public let provenance: ArtworkProvenance

    public init(data: Data, fileExtension: String, provenance: ArtworkProvenance) {
        self.data = data
        self.fileExtension = fileExtension
        self.provenance = provenance
    }
}

public protocol ArtworkProvider: Sendable {
    /// Returns only the selected image. A missing match returns nil; service failures throw.
    func artwork(for lookup: ArtworkLookup) async throws -> ProvidedArtwork?
}

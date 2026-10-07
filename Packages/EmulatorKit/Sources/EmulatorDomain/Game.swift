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
    public var aliases: [String]
    public var hasPlayerTitle: Bool
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
        aliases: [String] = [],
        hasPlayerTitle: Bool = false,
        preferredBuildID: UUID? = nil,
        preferredSaveProfileID: UUID? = nil,
        artworkAssetID: UUID? = nil,
        lineage: GameLineage? = nil,
        createdAt: Date,
        modifiedAt: Date
    ) {
        self.id = id
        self.primaryTitle = primaryTitle
        self.aliases = aliases
        self.hasPlayerTitle = hasPlayerTitle
        self.systemFamily = systemFamily
        self.preferredBuildID = preferredBuildID
        self.preferredSaveProfileID = preferredSaveProfileID
        self.artworkAssetID = artworkAssetID
        self.lineage = lineage
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try values.decode(UUID.self, forKey: .id),
            primaryTitle: try values.decode(String.self, forKey: .primaryTitle),
            systemFamily: try values.decode(String.self, forKey: .systemFamily),
            aliases: try values.decodeIfPresent([String].self, forKey: .aliases) ?? [],
            hasPlayerTitle: try values.decodeIfPresent(Bool.self, forKey: .hasPlayerTitle) ?? true,
            preferredBuildID: try values.decodeIfPresent(UUID.self, forKey: .preferredBuildID),
            preferredSaveProfileID: try values.decodeIfPresent(UUID.self, forKey: .preferredSaveProfileID),
            artworkAssetID: try values.decodeIfPresent(UUID.self, forKey: .artworkAssetID),
            lineage: try values.decodeIfPresent(GameLineage.self, forKey: .lineage),
            createdAt: try values.decode(Date.self, forKey: .createdAt),
            modifiedAt: try values.decode(Date.self, forKey: .modifiedAt)
        )
    }

    public mutating func addAliases(_ titles: [String]) {
        var seen = Set(aliases.map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) })
        for title in titles {
            let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let key = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            if seen.insert(key).inserted { aliases.append(title) }
        }
    }

    public func matchesSearch(_ query: String) -> Bool {
        ([primaryTitle] + aliases).contains { $0.localizedStandardContains(query) }
    }

}

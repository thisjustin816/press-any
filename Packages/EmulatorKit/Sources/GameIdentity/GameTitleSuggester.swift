import EmulatorApplication
import EmulatorDomain
import Foundation

public struct GameTitleSuggestion: Identifiable, Equatable, Sendable {
    public let gameID: UUID
    public let currentTitle: String
    public let proposedTitle: String
    public let region: String?
    public var id: UUID { gameID }
}

public struct GameTitleSuggester: Sendable {
    private let games: any GameRepository
    private let builds: any BuildRepository
    private let index: KnownDumpIndex
    private let preference: ReleasePreference

    public init(games: any GameRepository, builds: any BuildRepository, index: KnownDumpIndex, preference: ReleasePreference) {
        self.games = games
        self.builds = builds
        self.index = index
        self.preference = preference
    }

    public func suggestions() throws -> [GameTitleSuggestion] {
        try games.fetchGames().compactMap { game in
            let releases = try builds.fetchBuilds(gameID: game.id)
                .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
                .compactMap { build -> ReleaseTitle? in
                    guard let dump = build.imageSHA1.flatMap({ index.dump(sha1: $0) }) else { return nil }
                    return dump.releaseTitle(for: build)
                }
            guard let best = preference.preferredTitle(among: releases, currentTitle: game.primaryTitle),
                  best.title != game.primaryTitle else { return nil }
            return GameTitleSuggestion(gameID: game.id, currentTitle: game.primaryTitle, proposedTitle: best.title, region: best.region)
        }.sorted { $0.currentTitle.localizedCaseInsensitiveCompare($1.currentTitle) == .orderedAscending }
    }
}

import EmulatorDomain
import Foundation

public struct GameStatistics: Equatable, Sendable {
    public private(set) var totalPlaytimeSeconds: Double = 0
    public private(set) var sessionCount: Int = 0
    public private(set) var lastPlayedAt: Date?
    /// When the newest of the Game's live Builds was added or last changed.
    public private(set) var lastBuildChangeAt: Date?
    public let addedAt: Date

    public init(game: Game) {
        addedAt = game.createdAt
    }

    public var hasBeenPlayed: Bool {
        totalPlaytimeSeconds > 0 || sessionCount > 0 || lastPlayedAt != nil
    }

    public static func rollup(games: [Game], builds: [Build], profiles: [SaveProfile]) -> [UUID: GameStatistics] {
        var result = Dictionary(uniqueKeysWithValues: games.map { ($0.id, GameStatistics(game: $0)) })
        for build in builds {
            guard var statistics = result[build.gameID] else { continue }
            statistics.totalPlaytimeSeconds += build.totalPlaytimeSeconds
            let changedAt = max(build.createdAt, build.modifiedAt)
            if statistics.lastBuildChangeAt.map({ changedAt > $0 }) ?? true {
                statistics.lastBuildChangeAt = changedAt
            }
            result[build.gameID] = statistics
        }
        for profile in profiles {
            guard var statistics = result[profile.gameID] else { continue }
            statistics.sessionCount += profile.sessionCount
            if let date = profile.lastPlayedAt, statistics.lastPlayedAt.map({ date > $0 }) ?? true {
                statistics.lastPlayedAt = date
            }
            result[profile.gameID] = statistics
        }
        return result
    }
}

public struct FetchGameStatistics: Sendable {
    private let games: any GameRepository
    private let builds: any BuildRepository
    private let profiles: any SaveProfileRepository

    public init(games: any GameRepository, builds: any BuildRepository, profiles: any SaveProfileRepository) {
        self.games = games
        self.builds = builds
        self.profiles = profiles
    }

    public func execute() throws -> [UUID: GameStatistics] {
        try execute(games: games.fetchGames(), builds: builds.fetchAllBuilds())
    }

    /// Reuses the library's Build read, which also supplies each Game's system.
    public func execute(games: [Game], builds: [Build]) throws -> [UUID: GameStatistics] {
        GameStatistics.rollup(games: games, builds: builds, profiles: try profiles.fetchAllSaveProfiles())
    }
}

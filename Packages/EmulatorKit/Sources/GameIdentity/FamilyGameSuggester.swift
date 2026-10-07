import EmulatorApplication
import EmulatorDomain
import Foundation

public struct FamilyGameSuggestion: Identifiable, Equatable, Sendable {
    public let system: GameSystem
    public let familyName: String
    public let games: [Game]
    public var id: String { "\(system.rawValue):\(familyName)" }
}

public struct FamilyGameSuggester: Sendable {
    private let games: any GameRepository
    private let builds: any BuildRepository
    private let index: KnownDumpIndex

    public init(games: any GameRepository, builds: any BuildRepository, index: KnownDumpIndex) {
        self.games = games
        self.builds = builds
        self.index = index
    }

    public func suggestions() throws -> [FamilyGameSuggestion] {
        let library = try games.fetchGames()
        var groups: [String: (GameSystem, String, [Game])] = [:]
        for game in library {
            var seen = Set<String>()
            for build in try builds.fetchBuilds(gameID: game.id) {
                let verification = index.verification(of: build, sha1: { $0.imageSHA1 }, lookup: { try? builds.fetchBuild(id: $0) })
                let dump: KnownDump
                switch verification {
                case .verified(let match), .badDump(let match), .modified(let match): dump = match
                case .unknown: continue
                }
                let root = dump.parent ?? dump.name
                let key = "\(dump.system.rawValue):\(root)"
                guard seen.insert(key).inserted else { continue }
                var group = groups[key] ?? (dump.system, root, [])
                group.2.append(game)
                groups[key] = group
            }
        }
        return groups.values.filter { $0.2.count > 1 }.map {
            FamilyGameSuggestion(system: $0.0, familyName: $0.1, games: $0.2.sorted { $0.primaryTitle < $1.primaryTitle })
        }.sorted { $0.id < $1.id }
    }
}

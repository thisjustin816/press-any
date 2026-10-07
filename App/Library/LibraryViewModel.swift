import Combine
import EmulatorApplication
import EmulatorDomain
import Foundation

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var games: [Game] = []
    /// Each Game's system, from the Build it plays.
    @Published private(set) var systems: [UUID: GameSystem] = [:]
    @Published var searchText = ""
    @Published private(set) var errorMessage: String?

    private let gameRepository: any GameRepository
    private let buildRepository: any BuildRepository
    private let launchResolver: ResolvePreferredLaunchContext

    init(
        gameRepository: any GameRepository,
        buildRepository: any BuildRepository,
        launchResolver: ResolvePreferredLaunchContext
    ) {
        self.gameRepository = gameRepository
        self.buildRepository = buildRepository
        self.launchResolver = launchResolver
    }

    func system(of game: Game) -> GameSystem {
        systems[game.id] ?? .gameBoy
    }

    var visibleGames: [Game] {
        let sorted = games.sorted {
            $0.primaryTitle.localizedCaseInsensitiveCompare($1.primaryTitle) == .orderedAscending
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sorted }
        return sorted.filter { $0.matchesSearch(query) }
    }

    func reload() {
        do {
            games = try gameRepository.fetchGames()
            var systems: [UUID: GameSystem] = [:]
            for game in games {
                let builds = try buildRepository.fetchBuilds(gameID: game.id)
                systems[game.id] = (builds.first { $0.id == game.preferredBuildID } ?? builds.first)?.system
            }
            self.systems = systems
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func launchContext(for game: Game) throws -> LaunchContext {
        try launchResolver.execute(gameID: game.id)
    }

    /// Shown in the library's alert. A reload clears it, so report after reloading, never before.
    func report(_ message: String) {
        errorMessage = message
    }

    func clearError() {
        errorMessage = nil
    }
}

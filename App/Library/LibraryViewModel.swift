import Combine
import EmulatorApplication
import EmulatorDomain
import Foundation

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var games: [Game] = []
    @Published var searchText = ""
    @Published private(set) var errorMessage: String?

    private let gameRepository: any GameRepository
    private let launchResolver: ResolvePreferredLaunchContext

    init(
        gameRepository: any GameRepository,
        launchResolver: ResolvePreferredLaunchContext
    ) {
        self.gameRepository = gameRepository
        self.launchResolver = launchResolver
    }

    var visibleGames: [Game] {
        let sorted = games.sorted {
            $0.primaryTitle.localizedCaseInsensitiveCompare($1.primaryTitle) == .orderedAscending
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sorted }
        return sorted.filter { $0.primaryTitle.localizedCaseInsensitiveContains(query) }
    }

    func reload() {
        do {
            games = try gameRepository.fetchGames()
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

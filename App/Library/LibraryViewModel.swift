import Combine
import EmulatorApplication
import EmulatorDomain
import Foundation

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var games: [Game] = []
    /// Each Game's system, from the Build it plays.
    @Published private(set) var systems: [UUID: GameSystem] = [:]
    @Published var selection = ItemSelection<UUID>()
    @Published var pendingBatchDeletion: BatchDeletionPlan?
    @Published var searchText = "" {
        didSet { selection.reconcile(with: Set(visibleGames.map(\.id))) }
    }
    @Published var favoritesOnly = false {
        didSet { selection.reconcile(with: Set(visibleGames.map(\.id))) }
    }
    @Published private(set) var errorMessage: String?

    private let gameRepository: any GameRepository
    private let buildRepository: any BuildRepository
    private let launchResolver: ResolvePreferredLaunchContext
    private let buildOperations: BuildOperations
    private let deletion: LibraryDeletionOperations

    init(
        gameRepository: any GameRepository,
        buildRepository: any BuildRepository,
        launchResolver: ResolvePreferredLaunchContext,
        buildOperations: BuildOperations,
        deletion: LibraryDeletionOperations
    ) {
        self.gameRepository = gameRepository
        self.buildRepository = buildRepository
        self.launchResolver = launchResolver
        self.buildOperations = buildOperations
        self.deletion = deletion
    }

    func requestSelectedDeletion() {
        pendingBatchDeletion = deletion.planDeletion(of: visibleGames.filter { selection.ids.contains($0.id) }.map {
            LibraryDeletionTarget(kind: .game, id: $0.id)
        })
    }

    func confirm(_ batch: BatchDeletionPlan) {
        let result = deletion.delete(batch)
        reload()
        selection.ids = Set(result.skipped.map { $0.target.id }).intersection(Set(visibleGames.map(\.id)))
        NotificationCenter.default.post(name: .libraryDidChange, object: nil)
        if let message = result.failureMessage(after: batch) { report(message) }
    }

    func system(of game: Game) -> GameSystem {
        systems[game.id] ?? .gameBoy
    }

    var visibleGames: [Game] {
        let sorted = games.filter { !favoritesOnly || $0.isFavorite }.sorted {
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
            selection.reconcile(with: Set(visibleGames.map(\.id)))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Renames from the library's long-press menu, the same way Rename Game in Game Details does.
    func renameGame(_ game: Game, to title: String) {
        do {
            try buildOperations.renameGame(gameID: game.id, title: title)
            reload()
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
        } catch BuildOperationError.invalidGameTitle {
            report("A Game title can't be blank.")
        } catch {
            report(error.localizedDescription)
        }
    }

    func toggleFavorite(_ game: Game) {
        do {
            let current = try gameRepository.fetchGame(id: game.id)
            try buildOperations.setFavorite(gameID: game.id, isFavorite: !(current?.isFavorite ?? game.isFavorite))
            reload()
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
        } catch {
            report(error.localizedDescription)
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

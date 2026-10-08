import Combine
import EmulatorApplication
import EmulatorDomain
import Foundation

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var games: [Game] = []
    /// Each Game's system, from the Build it plays.
    @Published private(set) var systems: [UUID: GameSystem] = [:]
    @Published private(set) var statistics: [UUID: GameStatistics] = [:]
    /// The Build each Game plays, which Hack Author and Version sort by.
    @Published private(set) var preferredBuilds: [UUID: Build] = [:]
    @Published private(set) var manualPositions: [UUID: Int] = [:]
    @Published var sort: LibrarySort = .title
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
    private let fetchStatistics: FetchGameStatistics
    private let launchResolver: ResolvePreferredLaunchContext
    private let buildOperations: BuildOperations
    private let deletion: LibraryDeletionOperations

    init(
        gameRepository: any GameRepository,
        buildRepository: any BuildRepository,
        profiles: any SaveProfileRepository,
        launchResolver: ResolvePreferredLaunchContext,
        buildOperations: BuildOperations,
        deletion: LibraryDeletionOperations
    ) {
        self.gameRepository = gameRepository
        self.buildRepository = buildRepository
        self.fetchStatistics = FetchGameStatistics(games: gameRepository, builds: buildRepository, profiles: profiles)
        self.launchResolver = launchResolver
        self.buildOperations = buildOperations
        self.deletion = deletion
    }

    /// One Game from its long-press menu or swipe, confirmed the way a selection is.
    func requestDeletion(of game: Game) {
        pendingBatchDeletion = deletion.planDeletion(of: [LibraryDeletionTarget(kind: .game, id: game.id)])
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
        let sorted = ordered(by: sort).filter { !favoritesOnly || $0.isFavorite }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sorted }
        return sorted.filter { $0.matchesSearch(query) }
    }

    func reload() {
        do {
            let games = try gameRepository.fetchGames()
            let builds = try buildRepository.fetchAllBuilds()
            let statistics = try fetchStatistics.execute(games: games, builds: builds)
            let preferredBuilds = LibrarySort.preferredBuilds(games: games, builds: builds)
            let manualPositions = try gameRepository.fetchManualPositions()
            self.games = games
            self.systems = preferredBuilds.mapValues(\.system)
            self.statistics = statistics
            self.preferredBuilds = preferredBuilds
            self.manualPositions = manualPositions
            selection.reconcile(with: Set(visibleGames.map(\.id)))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Saves the order the player dragged the visible Games into. Games that search or Favorites
    /// Only hide keep their places among them.
    func reorder(visible: [UUID]) {
        let current = ordered(by: .manual).map(\.id)
        do {
            try gameRepository.setManualOrder(LibrarySort.manualOrder(current: current, rearrangedVisible: visible))
            reload()
        } catch {
            report(error.localizedDescription)
        }
    }

    private func ordered(by sort: LibrarySort) -> [Game] {
        sort.sorted(games: games, systems: systems, statistics: statistics, preferredBuilds: preferredBuilds,
                    manualPositions: manualPositions)
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

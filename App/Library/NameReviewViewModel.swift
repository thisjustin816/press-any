import Combine
import EmulatorApplication
import EmulatorDomain
import Foundation
import GameIdentity
import Importing

@MainActor
final class NameReviewViewModel: ObservableObject {
    struct GameItem: Identifiable {
        let suggestion: GameTitleSuggestion
        var title: String
        var accepted = true
        var id: UUID { suggestion.id }
    }

    struct BuildItem: Identifiable {
        let suggestion: BuildNameSuggestion
        var name: String
        var accepted = true
        var id: UUID { suggestion.id }
    }

    @Published var gameItems: [GameItem] = []
    @Published var buildItems: [BuildItem] = []
    @Published private(set) var loaded = false
    @Published private(set) var errorMessage: String?
    private let gameSuggester: GameTitleSuggester?
    private let buildSuggester: BuildNameSuggester
    private let operations: BuildOperations

    init(games: any GameRepository, builds: any BuildRepository, assets: any ManagedAssetRepository,
         index: KnownDumpIndex?, preference: ReleasePreference, operations: BuildOperations) {
        gameSuggester = index.map { GameTitleSuggester(games: games, builds: builds, index: $0, preference: preference) }
        buildSuggester = BuildNameSuggester(games: games, builds: builds, assets: assets)
        self.operations = operations
    }

    var isEmpty: Bool { gameItems.isEmpty && buildItems.isEmpty }

    var buildGameIDs: [UUID] {
        var seen = Set<UUID>()
        return buildItems.map(\.suggestion.gameID).filter { seen.insert($0).inserted }
    }

    var acceptedCount: Int {
        gameItems.filter { $0.accepted && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
            + buildItems.filter { $0.accepted && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    func load() {
        do {
            let gameSuggestions = try gameSuggester?.suggestions() ?? []
            let buildSuggestions = try buildSuggester.suggestions()
            gameItems = gameSuggestions.map { GameItem(suggestion: $0, title: $0.proposedTitle) }
            buildItems = buildSuggestions.map { BuildItem(suggestion: $0, name: $0.suggestedName) }
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
        loaded = true
    }

    /// Completed renames leave the review after a failure, so a retry applies only the remaining choices.
    func apply() -> Bool {
        var renamedGames = Set<UUID>()
        var renamedBuilds = Set<UUID>()
        defer {
            gameItems.removeAll { renamedGames.contains($0.id) }
            buildItems.removeAll { renamedBuilds.contains($0.id) }
            if !renamedGames.isEmpty || !renamedBuilds.isEmpty {
                NotificationCenter.default.post(name: .libraryDidChange, object: nil)
            }
        }
        errorMessage = nil
        for item in gameItems where item.accepted {
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            do {
                try operations.renameGame(gameID: item.id, title: title, hasPlayerTitle: title != item.suggestion.proposedTitle)
                renamedGames.insert(item.id)
            } catch {
                errorMessage = "Couldn’t rename “\(item.suggestion.currentTitle)”: \(error.localizedDescription)"
                return false
            }
        }
        for item in buildItems where item.accepted {
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name != item.suggestion.currentName else { continue }
            do {
                try operations.renameBuild(buildID: item.id, displayName: name,
                    source: name == item.suggestion.suggestedName ? .filename : .player)
                renamedBuilds.insert(item.id)
            } catch {
                errorMessage = "Couldn’t rename “\(item.suggestion.currentName)”: \(error.localizedDescription)"
                return false
            }
        }
        return true
    }
}

import Combine
import EmulatorApplication
import EmulatorDomain
import Foundation
import GameIdentity

@MainActor
final class FamilyMergeReviewViewModel: ObservableObject {
    struct Item: Identifiable {
        let suggestion: FamilyGameSuggestion
        var selected: Set<UUID>
        var survivorID: UUID
        var title: String
        var accepted = false
        var id: String { suggestion.id }
    }

    @Published var items: [Item] = []
    @Published private(set) var errorMessage: String?
    private let suggester: FamilyGameSuggester?
    private let operations: BuildOperations
    private let builds: any BuildRepository

    init(games: any GameRepository, builds: any BuildRepository, index: KnownDumpIndex?, operations: BuildOperations) {
        suggester = index.map { FamilyGameSuggester(games: games, builds: builds, index: $0) }
        self.operations = operations
        self.builds = builds
    }

    func load() {
        do {
            guard let suggester else {
                errorMessage = "No-Intro data is unavailable."
                return
            }
            items = try suggester.suggestions().map {
                Item(suggestion: $0, selected: Set($0.games.map(\.id)), survivorID: $0.games[0].id, title: $0.games[0].primaryTitle)
            }
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    var canMerge: Bool {
        items.contains { $0.accepted && $0.selected.union([$0.survivorID]).count > 1 && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    func confirm() {
        guard canMerge else { return }
        var changed = false
        defer {
            if changed { NotificationCenter.default.post(name: .libraryDidChange, object: nil) }
        }
        do {
            for item in items where item.accepted {
                let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { throw BuildOperationError.invalidGameTitle }
                let selected = item.selected.union([item.survivorID])
                guard selected.count > 1 else { continue }
                guard let current = try suggester?.suggestions().first(where: { $0.id == item.id }),
                      selected.isSubset(of: Set(current.games.map(\.id))) else {
                    throw FamilyMergeReviewError.libraryChanged
                }
                // Refuse overlapping images before moving any Game in this group.
                var images = Set<String>()
                for game in current.games where selected.contains(game.id) {
                    for build in try builds.fetchBuilds(gameID: game.id) {
                        guard images.insert(build.imageSHA256).inserted else {
                            throw BuildOperationError.duplicateImagesInTarget(buildIDs: [build.id])
                        }
                    }
                }
                for game in current.games where selected.contains(game.id) && game.id != item.survivorID {
                    let carry = try operations.suggestedCarryOver(merging: game.id, into: item.survivorID)
                    try operations.mergeGame(sourceGameID: game.id, into: item.survivorID, mode: .move, carryOver: carry)
                    changed = true
                }
                // Renaming marks the title as the player's, which ends regional title proposals, so
                // only a changed title is a rename.
                if title != current.games.first(where: { $0.id == item.survivorID })?.primaryTitle {
                    try operations.renameGame(gameID: item.survivorID, title: title)
                }
            }
            load()
        } catch {
            // Refresh removes completed moves, so retrying cannot repeat them.
            load()
            switch error {
            case BuildOperationError.duplicateImagesInTarget:
                errorMessage = "Games with the same ROM image cannot be moved together. Review them in Game Details."
            case BuildOperationError.invalidGameTitle:
                errorMessage = "A surviving Game title can't be blank."
            default:
                errorMessage = error.localizedDescription
            }
        }
    }
}

private enum FamilyMergeReviewError: LocalizedError {
    case libraryChanged
    var errorDescription: String? { "The library changed. Review the remaining Games before merging." }
}

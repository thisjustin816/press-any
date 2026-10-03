import Combine
import EmulatorApplication
import EmulatorDomain
import Foundation
import Importing

@MainActor
final class ImportReviewViewModel: ObservableObject {
    enum Destination: Hashable {
        case newGame
        case existing(UUID)
    }

    @Published var destination: Destination
    @Published var gameTitle: String
    @Published var buildDisplayName: String
    @Published var markAsBase: Bool
    @Published private(set) var errorMessage: String?

    let analysis: ROMImportAnalysis
    let games: [Game]

    private let coordinator: ImportCoordinator

    init(analysis: ROMImportAnalysis, games: [Game], coordinator: ImportCoordinator) {
        self.analysis = analysis
        self.games = games.sorted {
            $0.primaryTitle.localizedCaseInsensitiveCompare($1.primaryTitle) == .orderedAscending
        }
        self.coordinator = coordinator

        if let suggested = analysis.suggestedGameID {
            destination = .existing(suggested)
            markAsBase = false
        } else {
            destination = .newGame
            markAsBase = true
        }
        gameTitle = analysis.filenameMetadata.suggestedTitle.isEmpty
            ? analysis.header.title
            : analysis.filenameMetadata.suggestedTitle
        buildDisplayName = analysis.exactExistingBuildID == nil ? "Original" : "Existing"
    }

    var isExactDuplicate: Bool { analysis.exactExistingBuildID != nil }
    var shortHash: String { String(analysis.sha256.prefix(12)) }

    func commit() throws -> ROMImportResult {
        do {
            let disposition: ROMImportDisposition
            if let existing = analysis.exactExistingBuildID {
                disposition = .duplicateExisting(buildID: existing)
            } else {
                switch destination {
                case .newGame:
                    disposition = .createGame(title: gameTitle.trimmingCharacters(in: .whitespacesAndNewlines))
                case .existing(let gameID):
                    disposition = .addBuild(gameID: gameID)
                }
            }
            let result = try coordinator.committer.commit(
                ROMImportPlan(
                    analysis: analysis,
                    disposition: disposition,
                    buildDisplayName: buildDisplayName.trimmingCharacters(in: .whitespacesAndNewlines),
                    markAsBase: markAsBase
                )
            )
            errorMessage = nil
            return result
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func cancel() {
        coordinator.discard(analysis)
    }
}

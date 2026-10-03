import Combine
import EmulatorDomain
import Foundation
import Importing
import QuickPlay

/// Promotion runs through the same review as an import, plus what happens to the session's save.
@MainActor
final class QuickPlayPromotionViewModel: ObservableObject {
    enum SaveChoice: Hashable {
        case newProfile
        case replaceSource
        case discard
    }

    @Published var saveChoice: SaveChoice
    @Published var newProfileName = "Quick Play"
    @Published private(set) var errorMessage: String?

    let review: ImportReviewViewModel
    let session: QuickPlaySession
    let sourceProfile: SaveProfile?
    let hasSave: Bool

    private let container: AppContainer

    init(session: QuickPlaySession, container: AppContainer) throws {
        self.session = session
        self.container = container
        sourceProfile = try session.sourceSaveProfileID.flatMap {
            try container.repositories.saveProfiles.fetchSaveProfile(id: $0)
        }
        let battery = try container.quickPlayWorkspace.temporaryBatteryData(sessionID: session.id)
        hasSave = !(battery?.isEmpty ?? true)
        saveChoice = hasSave ? .newProfile : .discard

        let analysis = try container.quickPlayPromoter.analyze(session, targetGameID: sourceProfile?.gameID)
        review = ImportReviewViewModel(
            analysis: analysis,
            games: try container.repositories.games.fetchGames(),
            coordinator: ImportCoordinator(
                analyzer: container.importAnalyzer,
                committer: container.importCommitter,
                assetStore: container.fileStore
            )
        )
        // The sandbox copy is always rom.bin, so name things after the file that was picked.
        let name = URL(fileURLWithPath: session.originalFilename).deletingPathExtension().lastPathComponent
        review.gameTitle = name
        review.buildDisplayName = name
    }

    /// Replacing is offered only for the profile the session copied, and only when the Build
    /// lands in that profile's Game.
    var canReplaceSource: Bool {
        guard hasSave, let sourceProfile else { return false }
        return targetGameID == sourceProfile.gameID
    }

    var effectiveSaveChoice: SaveChoice {
        saveChoice == .replaceSource && !canReplaceSource ? .newProfile : saveChoice
    }

    private var targetGameID: UUID? {
        switch review.plan.disposition {
        case .createGame:
            nil
        case .addBuild(let gameID):
            gameID
        case .duplicateExisting(let buildID):
            (try? container.repositories.builds.fetchBuild(id: buildID))?.gameID
        }
    }

    func promote() throws -> QuickPlayPromotionResult {
        try promote(choosing: effectiveSaveChoice)
    }

    private func promote(choosing choice: SaveChoice) throws -> QuickPlayPromotionResult {
        let disposition: QuickPlaySaveDisposition
        switch choice {
        case .newProfile:
            disposition = .createProfile(name: newProfileName.trimmingCharacters(in: .whitespacesAndNewlines))
        case .replaceSource:
            guard let sourceProfile else { return try promote(choosing: .newProfile) }
            disposition = .replaceExisting(profileID: sourceProfile.id)
        case .discard:
            disposition = .keepExisting
        }
        do {
            let result = try container.quickPlayPromoter.promote(
                session: session,
                plan: review.plan,
                saveDisposition: disposition
            )
            errorMessage = nil
            return result
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func cancel() {
        review.cancel()
    }
}

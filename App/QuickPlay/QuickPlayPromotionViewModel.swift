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
    /// Set when the Build was added but a later step didn't finish, to tell the player before
    /// the review closes.
    @Published var shortfallNotice: String?
    /// The import already happened, so this review's analysis is spent; a retry starts over.
    @Published private(set) var needsFreshReview = false

    let review: ImportReviewViewModel
    let session: QuickPlaySession
    let sourceProfile: SaveProfile?
    let hasBattery: Bool
    /// An autosave promotion would keep. A game with no battery save can have one, and it's then
    /// the session's only progress.
    let hasResumePoint: Bool
    var hasProgress: Bool { hasBattery || hasResumePoint }

    private let container: AppContainer

    init(session: QuickPlaySession, container: AppContainer) throws {
        self.session = session
        self.container = container
        sourceProfile = try session.sourceSaveProfileID.flatMap {
            try container.repositories.saveProfiles.fetchSaveProfile(id: $0)
        }
        let battery = try container.quickPlayWorkspace.temporaryBatteryData(sessionID: session.id)
        hasBattery = !(battery?.isEmpty ?? true)
        hasResumePoint = session.hasResumePoint(files: container.fileStore)
        saveChoice = hasBattery || hasResumePoint ? .newProfile : .discard

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
    }

    /// Replacing is offered only for the profile the session copied, and only when the Build
    /// lands in that profile's Game.
    var canReplaceSource: Bool {
        guard hasBattery, let sourceProfile else { return false }
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
            shortfallNotice = Self.notice(for: result.shortfalls)
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
            return result
        } catch let error as PromoteQuickPlayError {
            if case .importedButSaveFailed = error {
                needsFreshReview = true
                NotificationCenter.default.post(name: .libraryDidChange, object: nil)
                errorMessage = "The Build was added, but its save couldn’t be stored. The session is kept: go back and choose Add to Library again to retry the save."
            } else {
                errorMessage = error.localizedDescription
            }
            throw error
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func cancel() {
        review.cancel()
    }

    private static func notice(for shortfalls: Set<QuickPlayPromotionShortfall>) -> String? {
        var lines: [String] = []
        if shortfalls.contains(.resumePointNotMoved) {
            lines.append("Where you left off couldn’t be moved to the library, so the Quick Play session is kept. You can still continue it from Quick Play.")
        }
        if shortfalls.contains(.buildDefaultSaveNotSet) {
            lines.append("The Build couldn’t be set to play the kept save. Choose it from the Build’s menu.")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n\n")
    }
}

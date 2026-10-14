import Combine
import Foundation

@MainActor
final class MissingArtworkReviewViewModel: ObservableObject {
    struct Item: Identifiable {
        let proposal: AppContainer.MissingArtworkProposal
        var accepted = true
        var id: UUID { proposal.id }
    }

    @Published var items: [Item] = []
    @Published private(set) var progress: AppContainer.MissingArtworkProgress?
    @Published private(set) var loaded = false
    @Published private(set) var errorMessage: String?
    private let container: AppContainer
    let proposalDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("artwork-review-\(UUID())")

    init(container: AppContainer) { self.container = container }

    deinit { try? FileManager.default.removeItem(at: proposalDirectory) }

    var acceptedCount: Int { items.filter(\.accepted).count }

    func search() async {
        guard !loaded else { return }
        defer { loaded = true }
        do {
            let result = try await container.findMissingArtwork(proposalDirectory: proposalDirectory) { progress = $0 }
            try Task.checkCancellation()
            progress = result.progress
            items = result.proposals.map { Item(proposal: $0) }
        } catch is CancellationError {
            discard()
        } catch { errorMessage = error.localizedDescription }
    }

    func apply() -> Bool {
        var completed = Set<UUID>()
        var saved = false
        var changed = false
        defer {
            items.removeAll { completed.contains($0.id) }
            if saved { NotificationCenter.default.post(name: .libraryDidChange, object: nil) }
        }
        errorMessage = nil
        for item in items where item.accepted {
            do {
                if try container.applyMissingArtwork(item.proposal) { saved = true }
                else { changed = true }
                completed.insert(item.id)
                try? FileManager.default.removeItem(at: item.proposal.imageURL)
            } catch {
                errorMessage = "Could not save artwork for \(item.proposal.gameTitle): \(error.localizedDescription)"
                return false
            }
        }
        if changed { errorMessage = "Some Games changed during review. Their artwork was left unchanged." }
        return !changed
    }

    func discard() {
        items = []
        try? FileManager.default.removeItem(at: proposalDirectory)
    }
}

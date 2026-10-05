import SwiftUI

struct SharedFileView: View {
    let file: SharedFile
    let container: AppContainer
    let onFinished: () -> Void
    let onQuickPlay: (QuickPlayRequest) -> Void

    @State private var review: ImportReviewViewModel?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if file.kind == .patch {
                SharedPatchView(file: file, container: container, onFinished: onFinished)
            } else if let review {
                ImportReviewView(model: review, onImported: { _ in
                    NotificationCenter.default.post(name: .libraryDidChange, object: nil)
                    onFinished()
                }, onCancel: onFinished)
            } else {
                NavigationStack {
                    Form {
                        Section {
                            Text(file.originalFilename)
                            Button("Quick Play", systemImage: "play.circle") {
                                onQuickPlay(QuickPlayRequest(
                                    url: file.url,
                                    copiedSaveProfileID: nil,
                                    chosenAt: DispatchTime.now().uptimeNanoseconds
                                ))
                            }
                            Button("Import to Library", systemImage: "square.and.arrow.down") {
                                prepareReview()
                            }
                        } footer: {
                            Text("Quick Play keeps a temporary session. Import to Library lets you review the Game and Build first.")
                        }
                        if let errorMessage {
                            Section { Text(errorMessage).foregroundStyle(.red) }
                        }
                    }
                    .navigationTitle("Open ROM")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel", action: onFinished)
                        }
                    }
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private func prepareReview() {
        let coordinator = ImportCoordinator(
            analyzer: container.importAnalyzer,
            committer: container.importCommitter,
            assetStore: container.fileStore
        )
        do {
            review = ImportReviewViewModel(
                analysis: try coordinator.analyzeROM(at: file.url),
                games: try container.repositories.games.fetchGames(),
                coordinator: coordinator
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

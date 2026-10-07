import EmulatorApplication
import EmulatorDomain
import SwiftUI

struct SharedFileView: View {
    let file: SharedFile
    let container: AppContainer
    /// A game is running, which Quick Play closes first.
    var quickPlayClosesGame = false
    let onFinished: () -> Void
    let onQuickPlay: (QuickPlayRequest) -> Void

    @State private var review: ImportReviewViewModel?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if file.kind == .patch {
                SharedPatchView(file: file, container: container, onFinished: onFinished)
            } else if file.kind == .save {
                SharedSaveView(file: file, container: container, onFinished: onFinished)
            } else if let review {
                ImportReviewView(model: review, onImported: { _ in
                    NotificationCenter.default.post(name: .libraryDidChange, object: nil)
                    onFinished()
                }, onCancel: onFinished)
            } else if file.opensImportReview && errorMessage == nil {
                ProgressView().task { prepareReview() }
            } else {
                NavigationStack {
                    Form {
                        Section {
                            Text(file.originalFilename)
                            Button(quickPlayClosesGame ? "Close Game and Quick Play" : "Quick Play", systemImage: "play.circle") {
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
            let games = try container.repositories.games.fetchGames()
            let analysis = try coordinator.analyzeROM(at: file.url)
            review = ImportReviewViewModel(
                analysis: analysis,
                games: games,
                coordinator: coordinator,
                existingBuilds: { container.builds(in: $0) },
                setArtwork: { _ = try container.gameArtwork.set(gameID: $0, imageData: $1, fileExtension: $2) },
                knownDumps: container.knownDumps,
                releasePreference: (try? ReleasePreferenceStore(store: container.repositories.settings).load()) ?? ReleasePreference()
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

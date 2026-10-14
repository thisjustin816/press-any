import SwiftUI

struct MissingArtworkSearchView: View {
    let container: AppContainer
    @Environment(\.dismiss) private var dismiss
    @State private var progress: AppContainer.MissingArtworkProgress?
    @State private var running = true
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if running {
                        if let progress {
                            ProgressView(value: Double(progress.checked), total: Double(max(progress.total, 1)))
                            Text("Checked \(progress.checked) of \(progress.total) Games")
                        } else {
                            ProgressView("Preparing Search...")
                        }
                    } else if let progress {
                        if progress.total == 0 {
                            Text("No missing artwork.")
                        } else {
                            Text("Checked \(progress.checked) Games.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let progress, progress.total > 0 {
                        Text("Added artwork to \(progress.added) Games.")
                        if progress.failed > 0 {
                            Text("Could not update \(progress.failed) Games. Try again later.")
                                .foregroundStyle(.red)
                        }
                    }
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                } footer: {
                    Text("Checks the whole library, including Games hidden by search and filters. Existing artwork stays, and previously removed artwork stays blank. Cancel keeps artwork already found.")
                }
                Section {
                    Text("Searches Libretro using recognized release names, even when Find Artwork on Import is off. Games with no match or available image stay unchanged.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Find Missing Artwork")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if running {
                        Button("Cancel") {
                            searchTask?.cancel()
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !running { Button("Done") { dismiss() } }
                }
            }
            .onAppear {
                guard searchTask == nil else { return }
                searchTask = Task { await search() }
            }
            .onDisappear { searchTask?.cancel() }
        }
    }

    private func search() async {
        do {
            progress = try await container.findMissingArtwork { progress = $0 }
        } catch is CancellationError {
            return
        } catch { errorMessage = error.localizedDescription }
        running = false
    }
}

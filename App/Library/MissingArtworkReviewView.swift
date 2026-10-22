import SwiftUI

struct MissingArtworkReviewView: View {
    @StateObject private var model: MissingArtworkReviewViewModel
    @Environment(\.dismiss) private var dismiss

    init(container: AppContainer) {
        _model = StateObject(wrappedValue: MissingArtworkReviewViewModel(container: container))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if !model.loaded {
                        if let progress = model.progress {
                            ProgressView(value: Double(progress.checked), total: Double(max(progress.total, 1)))
                            Text("Checked \(progress.checked) of \(progress.total) Games")
                        } else { ProgressView("Finding Artwork...") }
                    } else if model.items.isEmpty, model.errorMessage == nil {
                        Text("No artwork proposals found.")
                    }
                    if let progress = model.progress {
                        Text("Found artwork for \(progress.found) Games.")
                        if progress.failed > 0 {
                            Text("Could not check \(progress.failed) Games. Try again later.")
                                .foregroundStyle(.red)
                        }
                    }
                } footer: {
                    Text("Checks the whole library, including Games hidden by search and filters. Existing artwork stays. Previously removed artwork is proposed again and stays blank unless you accept it. Use Artwork saves accepted proposals; Cancel discards them.")
                }
                ForEach($model.items) { $item in
                    Section(item.proposal.gameTitle) {
                        AsyncImage(url: item.proposal.imageURL) { image in
                            image.resizable().scaledToFit()
                        } placeholder: { ProgressView() }
                            .frame(maxWidth: .infinity, maxHeight: 240)
                            .accessibilityLabel("Proposed artwork for \(item.proposal.gameTitle)")
                        Toggle("Use This Artwork", isOn: $item.accepted)
                            .accessibilityLabel("Use artwork for \(item.proposal.gameTitle)")
                        if let base = item.proposal.provenance.inheritedFrom {
                            Text("Artwork from the base game: \(base)")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Link("View Source", destination: item.proposal.provenance.sourceURL)
                        Text(item.proposal.provenance.rights)
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let error = model.errorMessage {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .scrollOverflowCue()
            .navigationTitle("Find Missing Artwork")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.loaded && model.items.isEmpty ? "Done" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use Artwork (\(model.acceptedCount))") { if model.apply() { dismiss() } }
                        .disabled(!model.loaded || model.acceptedCount == 0)
                }
            }
            .task { await model.search() }
            .onDisappear { model.discard() }
        }
    }
}

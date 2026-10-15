import EmulatorApplication
import SwiftUI
import UIKit

/// A manual check keeps its download in memory until the player chooses it.
struct ArtworkReviewView: View {
    let gameID: UUID
    let container: AppContainer
    @Environment(\.dismiss) private var dismiss
    @State private var provided: ProvidedArtwork?
    @State private var loading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if loading {
                    Section { ProgressView("Finding Artwork...") }
                } else if let provided, let image = UIImage(data: provided.data) {
                    if let game = try? container.repositories.games.fetchGame(id: gameID),
                       let url = container.artworkURL(for: game) {
                        Section("Current Artwork") {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFit()
                            } placeholder: { ProgressView() }
                            .frame(maxWidth: .infinity, maxHeight: 220)
                            .accessibilityLabel("Current artwork")
                        }
                    }
                    Section {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 300)
                            .accessibilityLabel("Artwork from Libretro")
                    } header: { Text("From Libretro") } footer: {
                        if provided.provenance.inheritedFrom != nil {
                            Text("From this Build's base game. Choosing it replaces any current artwork.")
                        } else {
                            Text("Choosing this image replaces any current artwork.")
                        }
                    }
                    Section {
                        Link("View Source", destination: provided.provenance.sourceURL)
                        Text(provided.provenance.rights).font(.footnote).foregroundStyle(.secondary)
                    }
                } else if errorMessage == nil {
                    Section {
                        Text("No artwork found. Libretro lookups need a recognized release or a confirmed base game. You can choose artwork from Photos or Files.")
                    }
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle("Check for New Artwork")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use Artwork", action: useArtwork).disabled(provided == nil || loading)
                }
            }
            .task { await findArtwork() }
        }
    }

    private func findArtwork() async {
        do {
            let result = try await container.findArtwork(gameID: gameID)
            try Task.checkCancellation()
            if let result {
                let prepared = try ArtworkImage.downscaled(result.data, fileExtension: result.fileExtension)
                provided = ProvidedArtwork(data: prepared.data, fileExtension: prepared.fileExtension, provenance: result.provenance)
            }
        } catch is CancellationError {
            return
        } catch { errorMessage = error.localizedDescription }
        loading = false
    }

    private func useArtwork() {
        guard let provided else { return }
        do {
            try container.gameArtwork.set(gameID: gameID, imageData: provided.data,
                fileExtension: provided.fileExtension, provenance: provided.provenance)
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

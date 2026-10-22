import EmulatorApplication
import SwiftUI

struct ArtworkSettingsView: View {
    let store: any SettingsStore
    @Environment(\.libraryStorageContext) private var libraryStorageContext
    @State private var automatic = true
    @State private var showReview = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Toggle("Find Artwork on Import", isOn: Binding(get: { automatic }, set: { save($0) }))
            } footer: {
                Text("Finds box art from Libretro for recognized games after import. Existing artwork stays. Check one Game from its Artwork menu.")
            }
            if libraryStorageContext != nil {
                Section {
                    Button("Find Missing Artwork") { showReview = true }
                        .accessibilityIdentifier("settings.artwork.findMissing")
                } footer: {
                    Text("Review proposed images for empty slots, including artwork you removed. Nothing is saved until you accept. Works with Find Artwork on Import off, and existing artwork stays.")
                }
            }
            Section {
                Text("Libretro receives the recognized game's release name and your network address. ROM files, saves, and names you edit are never sent.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .scrollOverflowCue()
        .navigationTitle("Artwork")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showReview) {
            if let context = libraryStorageContext { MissingArtworkReviewView(container: context.container) }
        }
        .task {
            do { automatic = try AutomaticArtworkSetting(store: store).load() }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func save(_ enabled: Bool) {
        do {
            try AutomaticArtworkSetting(store: store).save(enabled)
            automatic = enabled
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
}

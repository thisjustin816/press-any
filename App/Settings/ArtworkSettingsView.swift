import EmulatorApplication
import SwiftUI

struct ArtworkSettingsView: View {
    let store: any SettingsStore
    @State private var automatic = true
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Toggle("Find Artwork on Import", isOn: Binding(get: { automatic }, set: save))
            } footer: {
                Text("Finds box art from Libretro for recognized games after import. Existing artwork stays. You can check from a Game's Artwork menu at any time.")
            }
            Section {
                Text("Libretro receives the recognized game's release name and your network address. ROM files, saves, and names you edit are never sent.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .navigationTitle("Artwork")
        .navigationBarTitleDisplayMode(.inline)
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

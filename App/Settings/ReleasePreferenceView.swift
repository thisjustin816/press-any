import EmulatorApplication
import EmulatorDomain
import SwiftUI

struct ReleasePreferenceView: View {
    let store: any SettingsStore
    @State private var preference = ReleasePreference()
    @State private var newRegion = ""
    @State private var newLanguage = ""
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                ForEach(preference.regions, id: \.self) { Text($0) }
                    .onMove { preference.regions.move(fromOffsets: $0, toOffset: $1); save() }
                    .onDelete { preference.regions.remove(atOffsets: $0); save() }
                HStack {
                    TextField("Add region", text: $newRegion)
                    Button("Add") { add(newRegion, toRegions: true); newRegion = "" }
                }
            } header: { Text("Regions") } footer: {
                Text("The first available region suggests the Game title and Preferred Build during import. Existing Games change only when you confirm a review; titles you set are kept.")
            }
            Section("Languages") {
                ForEach(preference.languages, id: \.self) { Text($0) }
                    .onMove { preference.languages.move(fromOffsets: $0, toOffset: $1); save() }
                    .onDelete { preference.languages.remove(atOffsets: $0); save() }
                HStack {
                    TextField("Add language code (En, Ja…)", text: $newLanguage)
                    Button("Add") { add(newLanguage, toRegions: false); newLanguage = "" }
                }
            }
            Button("Restore Defaults") { preference = ReleasePreference(); save() }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Regions and Languages")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do { preference = try ReleasePreferenceStore(store: store).load() }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func add(_ value: String, toRegions: Bool) {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let values = toRegions ? preference.regions : preference.languages
        guard !values.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) else { return }
        if toRegions { preference.regions.append(value) } else { preference.languages.append(value) }
        save()
    }

    private func save() {
        do { try ReleasePreferenceStore(store: store).save(preference); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
}

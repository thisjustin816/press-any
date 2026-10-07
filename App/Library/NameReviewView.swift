import EmulatorApplication
import EmulatorDomain
import SwiftUI

struct NameReviewView: View {
    @StateObject private var model: NameReviewViewModel
    @Environment(\.dismiss) private var dismiss

    init(container: AppContainer) {
        _model = StateObject(wrappedValue: NameReviewViewModel(
            games: container.repositories.games,
            builds: container.repositories.builds,
            assets: container.repositories.assets,
            index: container.knownDumps,
            preference: (try? ReleasePreferenceStore(store: container.repositories.settings).load()) ?? ReleasePreference(),
            operations: container.buildOperations
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                if model.loaded, model.isEmpty, model.errorMessage == nil {
                    ContentUnavailableView(
                        "Names Look Right",
                        systemImage: "checkmark.circle",
                        description: Text("Game titles and Build names look right.")
                    )
                }
                if !model.gameItems.isEmpty {
                    Section {
                        ForEach($model.gameItems) { $item in
                            Toggle(isOn: $item.accepted) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.suggestion.currentTitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .strikethrough(item.accepted)
                                    TextField("Game title", text: $item.title)
                                        .disabled(!item.accepted)
                                    Text("Release region: \(item.suggestion.region ?? "Unknown")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("Game Titles")
                    } footer: {
                        Text("Accept a regional title to follow your region and language order during later imports. An edited title stays yours. Preferred Builds stay as they are.")
                    }
                }
                ForEach(model.buildGameIDs, id: \.self) { gameID in
                    Section(model.buildItems.first { $0.suggestion.gameID == gameID }?.suggestion.gameTitle ?? "") {
                        ForEach($model.buildItems) { $item in
                            if item.suggestion.gameID == gameID {
                                Toggle(isOn: $item.accepted) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.suggestion.currentName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .strikethrough(item.accepted)
                                        TextField("Build name", text: $item.name)
                                            .disabled(!item.accepted)
                                    }
                                }
                            }
                        }
                    }
                }
                if let error = model.errorMessage {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Suggest Names")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Rename (\(model.acceptedCount))") { if model.apply() { dismiss() } }
                        .disabled(model.acceptedCount == 0)
                }
            }
            .task { model.load() }
        }
    }
}

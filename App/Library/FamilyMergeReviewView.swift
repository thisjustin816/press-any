import SwiftUI

struct FamilyMergeReviewView: View {
    @StateObject private var model: FamilyMergeReviewViewModel
    @Environment(\.dismiss) private var dismiss

    init(container: AppContainer) {
        _model = StateObject(wrappedValue: FamilyMergeReviewViewModel(
            games: container.repositories.games,
            builds: container.repositories.builds,
            index: container.knownDumps,
            operations: container.buildOperations
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                if model.items.isEmpty, model.errorMessage == nil {
                    ContentUnavailableView("No Matching Games", systemImage: "checkmark.circle", description: Text("No No-Intro family is split across Games."))
                }
                ForEach($model.items) { $item in
                    Section(item.suggestion.familyName) {
                        Toggle("Merge This Family", isOn: $item.accepted)
                        ForEach(item.suggestion.games) { game in
                            Toggle(game.primaryTitle, isOn: Binding(
                                get: { item.selected.contains(game.id) || item.survivorID == game.id },
                                set: { if $0 { item.selected.insert(game.id) } else { item.selected.remove(game.id) } }
                            ))
                            .disabled(game.id == item.survivorID)
                        }
                        Picker("Keep Game", selection: $item.survivorID) {
                            ForEach(item.suggestion.games) { game in Text(game.primaryTitle).tag(game.id) }
                        }
                        .onChange(of: item.survivorID) { _, id in
                            item.selected.insert(id)
                            item.title = item.suggestion.games.first { $0.id == id }?.primaryTitle ?? item.title
                        }
                        TextField("Surviving Title", text: $item.title)
                    }
                }
                Section {
                    Text("Selected Games move into the Game you keep. Build lineage, Save Profiles and save states follow; its artwork stays, or the first available artwork fills it. Nothing changes until you choose Merge.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Suggest Game Merges")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Merge") { model.confirm() }.disabled(!model.canMerge) }
            }
            .task { model.load() }
        }
    }
}

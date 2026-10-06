import Importing
import SwiftUI

/// Suggests names for existing Builds under the import naming rules. Each suggestion is the player's
/// to accept, edit or skip; nothing is renamed until they choose Rename.
struct BuildNameReviewView: View {
    let container: AppContainer

    @Environment(\.dismiss) private var dismiss
    @State private var items: [Item] = []
    @State private var loaded = false
    @State private var errorMessage: String?

    struct Item: Identifiable {
        let suggestion: BuildNameSuggestion
        var name: String
        var accepted = true
        var id: UUID { suggestion.id }
    }

    var body: some View {
        NavigationStack {
            Form {
                if loaded, items.isEmpty {
                    ContentUnavailableView(
                        "Build Names Look Right",
                        systemImage: "checkmark.circle",
                        description: Text("No Build has an escaped, filename-only or repeated name.")
                    )
                }
                ForEach(gameIDs, id: \.self) { gameID in
                    Section(items.first { $0.suggestion.gameID == gameID }?.suggestion.gameTitle ?? "") {
                        ForEach($items) { $item in
                            if item.suggestion.gameID == gameID {
                                row($item)
                            }
                        }
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Suggest Build Names")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Rename (\(acceptedCount))") { apply() }
                        .disabled(acceptedCount == 0)
                }
            }
            .task { load() }
        }
    }

    private func row(_ item: Binding<Item>) -> some View {
        Toggle(isOn: item.accepted) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.wrappedValue.suggestion.currentName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .strikethrough(item.wrappedValue.accepted)
                TextField("Build name", text: item.name)
                    .disabled(!item.wrappedValue.accepted)
            }
        }
    }

    private var gameIDs: [UUID] {
        var seen = Set<UUID>()
        return items.map(\.suggestion.gameID).filter { seen.insert($0).inserted }
    }

    private var acceptedCount: Int {
        items.filter { $0.accepted && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    private func load() {
        let suggester = BuildNameSuggester(
            games: container.repositories.games,
            builds: container.repositories.builds,
            assets: container.repositories.assets
        )
        do {
            items = try suggester.suggestions().map { Item(suggestion: $0, name: $0.suggestedName) }
        } catch {
            errorMessage = error.localizedDescription
        }
        loaded = true
    }

    private func apply() {
        for item in items where item.accepted {
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name != item.suggestion.currentName else { continue }
            do {
                try container.buildOperations.renameBuild(buildID: item.suggestion.buildID, displayName: name)
            } catch {
                errorMessage = "Couldn’t rename “\(item.suggestion.currentName)”: \(error.localizedDescription)"
                return
            }
        }
        NotificationCenter.default.post(name: .libraryDidChange, object: nil)
        dismiss()
    }
}

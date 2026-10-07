import GameIdentity
import SwiftUI

struct MatchGameView: View {
    @ObservedObject var model: ImportReviewViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private struct Result: Identifiable {
        let dump: KnownDump
        var id: String { "\(dump.system.rawValue):\(dump.name)" }
    }

    private var results: [Result] { (model.knownDumps?.search(query) ?? []).map { Result(dump: $0) } }

    var body: some View {
        NavigationStack {
            List {
                Section("Library") {
                    ForEach(model.games.filter { query.isEmpty || $0.matchesSearch(query) }) { game in
                        Button(game.primaryTitle) {
                            model.matchGame(game)
                            dismiss()
                        }
                    }
                }
                Section("No-Intro") {
                    ForEach(results, id: \.id) { result in
                        let dump = result.dump
                        Button(dump.name) {
                            model.matchGame(dump)
                            dismiss()
                        }
                    }
                    if query.isEmpty { Text("Search for a base game, including games you haven't imported.") }
                }
            }
            .searchable(text: $query, prompt: "Search base games")
            .navigationTitle("Match Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

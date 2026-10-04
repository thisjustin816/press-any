import Importing
import SwiftUI

struct ImportReviewView: View {
    @ObservedObject var model: ImportReviewViewModel
    let onImported: (ROMImportResult) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("ROM") {
                    LabeledContent("File", value: model.analysis.originalFilename)
                    LabeledContent("Header title", value: model.analysis.header.title.isEmpty ? "Unknown" : model.analysis.header.title)
                    LabeledContent("System", value: model.analysis.header.system.displayName)
                    LabeledContent("SHA-256", value: model.shortHash + "…")
                    if !model.analysis.header.headerChecksumValid {
                        Label("Header checksum is not valid", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }

                ToolchainSection(reports: model.analysis.toolchainReports)

                ImportDestinationSection(model: model)

                if let message = model.errorMessage {
                    Section {
                        Text(message)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Import Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        model.cancel()
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        do {
                            let result = try model.commit()
                            onImported(result)
                            dismiss()
                        } catch {
                            // The model owns the visible error message.
                        }
                    }
                    .disabled(!model.canCommit)
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

/// Where an analyzed image goes: a new Game, a Build of an existing one, or nowhere for an exact
/// duplicate. Shared by import and Quick Play promotion.
struct ImportDestinationSection: View {
    @ObservedObject var model: ImportReviewViewModel

    var body: some View {
        if model.isExactDuplicate {
            Section {
                Label("This exact ROM is already in your library.", systemImage: "checkmark.circle")
            }
        } else {
            Section("Destination") {
                Picker("Import as", selection: $model.destination) {
                    Text("New Game").tag(ImportReviewViewModel.Destination.newGame)
                    ForEach(model.games) { game in
                        Text("Add Build to \(game.primaryTitle)")
                            .tag(ImportReviewViewModel.Destination.existing(game.id))
                    }
                }

                if model.destination == .newGame {
                    TextField("Game title", text: $model.gameTitle)
                }
                TextField("Build name", text: $model.buildDisplayName)
                Toggle("Base Build", isOn: $model.markAsBase)
            }
        }
    }
}

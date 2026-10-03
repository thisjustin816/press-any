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
                    LabeledContent("System", value: model.analysis.header.system == .gameBoyColor ? "Game Boy Color" : "Game Boy")
                    LabeledContent("SHA-256", value: model.shortHash + "...")
                    if !model.analysis.header.headerChecksumValid {
                        Label("Header checksum is not valid", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }

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
                    .disabled(!model.isExactDuplicate && model.buildDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

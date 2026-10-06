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
                // First, as in Quick Play promotion, so choosing an existing Game isn't missed below the ROM details.
                ImportDestinationSection(model: model)

                Section {
                    LabeledContent("File", value: model.analysis.originalFilename)
                    LabeledContent("Suggested Filename", value: model.normalizedFilename)
                    LabeledContent("Header title", value: model.analysis.header.title.isEmpty ? "Unknown" : model.analysis.header.title)
                    LabeledContent("System", value: model.analysis.header.system.displayName)
                    LabeledContent("SHA-256", value: model.shortHash + "…")
                    if !model.analysis.header.headerChecksumValid {
                        Label("Header checksum is not valid", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("ROM")
                } footer: {
                    if !model.analysis.header.headerChecksumValid {
                        Text("The checksum covers the title and cartridge details at the start of the ROM. Homebrew and patched ROMs sometimes leave it wrong, and an original Game Boy won’t start them.")
                    }
                }

                ToolchainSection(reports: model.analysis.toolchainReports)

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
            Section {
                Picker("Import as", selection: $model.destination) {
                    Text("New Game").tag(ImportReviewViewModel.Destination.newGame)
                    ForEach(model.games) { game in
                        Text("Add Build to \(game.primaryTitle)")
                            .tag(ImportReviewViewModel.Destination.existing(game.id))
                    }
                }
                .onChange(of: model.destination) { _, _ in model.destinationChanged() }

                if model.destination == .newGame {
                    LabeledContent("Game Title") {
                        TextField("Game Title", text: $model.gameTitle)
                            .multilineTextAlignment(.trailing)
                    }
                }
                LabeledContent("Build Name") {
                    TextField("Build Name", text: $model.buildDisplayName)
                        .multilineTextAlignment(.trailing)
                }
                Toggle("Base Build", isOn: $model.markAsBase)
                if model.destination == .newGame {
                    LabeledContent("Preferred Build", value: "Yes — first Build")
                } else {
                    Toggle("Preferred Build", isOn: $model.markAsPreferred)
                }
            } header: {
                Text("Destination")
            } footer: {
                Text("A Base Build is a clean, unmodified ROM that patches are applied to. A Game can have one for each revision or region.")
            }
            Section {
                metadataField("Region", text: $model.region)
                metadataField("Language", text: $model.language)
                metadataField("Revision", text: $model.revision)
                metadataField("Version", text: $model.version)
                metadataField("Base Title", text: $model.baseTitle)
                metadataField("Hack Title", text: $model.hackTitle)
                metadataField("Author", text: $model.author)
                metadataField("Translation", text: $model.translation)
                metadataField("Status", text: $model.status)
            } header: {
                Text("Build Details")
            } footer: {
                Text("\(model.namingEvidence). Correct or clear any detail before importing.")
            }
        }
    }

    private func metadataField(_ label: String, text: Binding<String>) -> some View {
        LabeledContent(label) {
            TextField("Optional", text: text)
                .accessibilityLabel(label)
                .multilineTextAlignment(.trailing)
        }
    }
}

import Importing
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ImportReviewView: View {
    @ObservedObject var model: ImportReviewViewModel
    let onImported: (ROMImportResult) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    /// The import that succeeded while its artwork couldn't be saved, held until the alert is read.
    @State private var importedWithoutArtwork: ROMImportResult?

    var body: some View {
        NavigationStack {
            Form {
                // First, as in Quick Play promotion, so choosing an existing Game isn't missed below the ROM details.
                ImportDestinationSection(model: model)

                if model.canChooseArtwork {
                    ImportArtworkSection(model: model)
                }

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
                            if model.artworkFailure == nil {
                                onImported(result)
                                dismiss()
                            } else {
                                importedWithoutArtwork = result
                            }
                        } catch {
                            // The model owns the visible error message.
                        }
                    }
                    .disabled(!model.canCommit)
                }
            }
        }
        .interactiveDismissDisabled()
        .alert(
            "Imported Without Artwork",
            isPresented: Binding(get: { importedWithoutArtwork != nil }, set: { if !$0 { finishWithoutArtwork() } })
        ) {
            Button("OK") { finishWithoutArtwork() }
        } message: {
            Text("The ROM is in your library, but its artwork couldn’t be saved: \(model.artworkFailure ?? ""). You can add it from the Game.")
        }
    }

    private func finishWithoutArtwork() {
        guard let result = importedWithoutArtwork else { return }
        importedWithoutArtwork = nil
        onImported(result)
        dismiss()
    }
}

/// Cover art for the Game the ROM lands in, from Photos or Files. It's set once the import
/// succeeds; the Game's own artwork menu changes it later.
struct ImportArtworkSection: View {
    @ObservedObject var model: ImportReviewViewModel

    @State private var photoItem: PhotosPickerItem?
    @State private var showsFileImporter = false

    var body: some View {
        Section {
            if let artwork = model.artwork, let image = UIImage(data: artwork.data) {
                HStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel("Chosen artwork")
                    Spacer()
                    Button("Remove", role: .destructive) { model.removeArtwork() }
                }
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(model.artwork == nil ? "Choose from Photos" : "Replace from Photos", systemImage: "photo")
            }
            Button {
                showsFileImporter = true
            } label: {
                Label(model.artwork == nil ? "Choose from Files" : "Replace from Files", systemImage: "folder")
            }
        } header: {
            Text("Artwork")
        } footer: {
            if model.replacesArtwork, model.artwork != nil {
                Text("Replaces this Game’s current artwork.")
            } else {
                Text("Optional. Shown on the library tile and the Game.")
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                model.chooseArtwork(data, fileExtension: item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg")
            }
        }
        .fileImporter(isPresented: $showsFileImporter, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result { model.chooseArtwork(fileAt: url) }
        }
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
                Text("A Base Build is the clean, unmodified ROM that patches are applied to. Choosing it replaces this Game’s previous Base Build.")
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

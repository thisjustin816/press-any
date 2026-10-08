import EmulatorApplication
import Importing
import SwiftUI

struct LibraryBackupView: View {
    @StateObject private var model: LibraryBackupViewModel
    @Environment(\.dismiss) private var dismiss

    init(container: AppContainer, gameID: UUID? = nil) {
        _model = StateObject(wrappedValue: LibraryBackupViewModel(service: container.libraryBackup,
            directory: container.exportsDirectory, gameID: gameID))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Include ROMs", isOn: $model.includeROMs)
                        .disabled(model.isExporting)
                } footer: {
                    Text(model.includeROMs
                         ? "This backup includes ROMs. It is personal and should not be shared."
                         : "ROM files stay out of the backup. Saves, states, patches, artwork, metadata, and settings are included.")
                }
                if let summary = model.summary {
                    BackupCountsSection(counts: summary.recordCounts)
                    Section {
                        LabeledContent("Approximate Size", value: ByteCountFormatter.string(fromByteCount: summary.approximateByteLength, countStyle: .file))
                    }
                }
                if model.isLoading { ProgressView("Reading library...") }
                if model.isExporting { ProgressView("Writing backup...", value: model.progress) }
                if let url = model.exportedURL {
                    Section {
                        Text(url.lastPathComponent)
                        ShareLink("Share Backup", item: url)
                    } footer: { Text("Saved in the Exports folder in Files.") }
                }
                if let message = model.errorMessage { Section { Text(message).foregroundStyle(.red) } }
            }
            .navigationTitle(model.gameID == nil ? "Back Up Library" : "Export Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.disabled(model.isExporting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.gameID == nil ? "Back Up" : "Export") { Task { await model.export() } }
                        .disabled(!model.canExport)
                }
            }
            .task { await model.loadSummary() }
            .onChange(of: model.includeROMs) { _, _ in Task { await model.loadSummary() } }
            .interactiveDismissDisabled(model.isExporting)
        }
    }
}

struct BackupCountsSection: View {
    let counts: [String: Int]
    private let labels = ["games": "Games", "manualPositions": "Games in Manual Order", "builds": "Builds", "profiles": "Save Profiles",
                          "states": "Save States", "recipes": "Patch Recipes", "variableMaps": "Variable Maps",
                          "reports": "Toolchain Reports", "declarations": "Save Declarations", "settings": "Settings"]

    var body: some View {
        Section("Contents") {
            ForEach(["games", "manualPositions", "builds", "profiles", "states", "recipes", "variableMaps", "reports", "declarations", "settings"], id: \.self) { key in
                LabeledContent(labels[key] ?? key, value: "\(counts[key] ?? 0)")
            }
        }
    }
}

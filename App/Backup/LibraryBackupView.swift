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
                    } footer: {
                        if summary.isTooLarge {
                            Text("A backup can hold up to \(ByteCountFormatter.string(fromByteCount: LibraryBackupService.maximumArchiveBytes, countStyle: .file)). Turn off Include ROMs, or export Games one at a time.")
                                .foregroundStyle(.red)
                        }
                    }
                }
                if model.isLoading { ProgressView("Reading library...") }
            }
            .scrollOverflowCue()
            // The outcome sits outside the list, so it is on screen however far the list is scrolled.
            .safeAreaInset(edge: .bottom) { statusCard }
            .sensoryFeedback(.success, trigger: model.exportedURL) { _, new in new != nil }
            .sensoryFeedback(.error, trigger: model.errorMessage) { _, new in new != nil }
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

extension LibraryBackupView {
    /// What the last Back Up did: its progress, the saved file, or why it failed.
    @ViewBuilder fileprivate var statusCard: some View {
        if model.isExporting {
            card { ProgressView(model.gameID == nil ? "Writing backup..." : "Writing export...", value: model.progress) }
        } else if let url = model.exportedURL {
            card {
                Label(model.gameID == nil ? "Backup saved" : "Game exported", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Text(url.lastPathComponent)
                    .font(.subheadline)
                Text("This copy is in the \(AppBrand.displayName) folder in Files, which belongs to the app. Deleting \(AppBrand.displayName) deletes it too. To keep it, share it to iCloud Drive or another place.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ShareLink("Share or Save a Copy", item: url)
                    .buttonStyle(.borderedProminent)
                    .tint(Color(uiColor: AppBrand.Colors.button))
            }
        } else if let message = model.errorMessage {
            card {
                Label(model.gameID == nil ? "Backup failed" : "Export failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
                Text(message)
                    .font(.subheadline)
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
            .padding(.bottom, 8)
    }
}

struct BackupCountsSection: View {
    let counts: [String: Int]
    private let labels = ["games": "Games", "manualPositions": "Games in Manual Order", "builds": "Builds", "profiles": "Save Profiles",
                          "states": "Save States", "recipes": "Patch Recipes", "variableMaps": "Variable Maps", "cheats": "Cheats",
                          "reports": "Toolchain Reports", "declarations": "Save Declarations", "settings": "Settings"]

    var body: some View {
        Section("Contents") {
            ForEach(["games", "manualPositions", "builds", "profiles", "states", "recipes", "variableMaps", "cheats", "reports", "declarations", "settings"], id: \.self) { key in
                LabeledContent(labels[key] ?? key, value: "\(counts[key] ?? 0)")
            }
        }
    }
}

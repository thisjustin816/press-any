import EmulatorApplication
import Importing
import SwiftUI

struct LibraryRestoreView: View {
    @StateObject private var model: LibraryRestoreViewModel
    private let onFinished: () -> Void

    init(container: AppContainer, url: URL, gameIsRunning: Bool = false, onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
        _model = StateObject(wrappedValue: LibraryRestoreViewModel(service: container.libraryBackup,
            url: url, directory: container.exportsDirectory,
            isSessionActive: { gameIsRunning || container.activeSession != nil }))
    }

    var body: some View {
        NavigationStack {
            Form {
                if let report = model.report {
                    RestoreReportSections(report: report)
                } else {
                    reviewSections
                }
                if model.isLoading { ProgressView("Verifying backup...") }
                if model.isMakingSafetyBackup { ProgressView("Backing up the current library...") }
                if model.isRestoring { ProgressView("Restoring...", value: model.progress) }
                if let message = model.errorMessage { Section { Text(message).foregroundStyle(.red) } }
            }
            .navigationTitle(model.report == nil ? "Restore Review" : "Migration Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.report == nil ? "Cancel" : "Done", action: onFinished).disabled(model.isBusy)
                }
                if model.report == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Merge") { Task { await model.merge() } }.disabled(!model.canRestore)
                    }
                }
            }
            .task { await model.load() }
            .confirmationDialog("Replace Entire Library?", isPresented: $model.isReplacementConfirmationPresented, titleVisibility: .visible) {
                Button("Replace Entire Library", role: .destructive) { Task { await model.confirmReplacement() } }
                Button("Cancel", role: .cancel) { model.cancelReplacement() }
            } message: {
                Text("The current library will be replaced. Its automatic backup is in Exports: \(model.safetyBackupURL?.lastPathComponent ?? "").")
            }
            .interactiveDismissDisabled(model.isBusy)
        }
    }

    @ViewBuilder
    private var reviewSections: some View {
        if let prepared = model.prepared, let review = model.review {
            BackupCountsSection(counts: prepared.manifest.recordCounts)
            Section {
                LabeledContent("Will Be Added", value: "\(review.added)")
                LabeledContent("Already Identical", value: "\(review.skipped)")
                LabeledContent("Conflicts", value: "\(review.conflicts.count)")
            } header: { Text("Merge") } footer: { Text("Merge keeps library items that are absent from the backup.") }
            if !review.conflicts.isEmpty {
                Section {
                    ForEach(review.conflicts) { conflict in
                        VStack(alignment: .leading) {
                            Text(conflict.name)
                            Text(conflict.kind).font(.caption).foregroundStyle(.secondary)
                            Picker("Keep", selection: Binding<RestoreChoice?>(
                                get: { model.choices[conflict.id] },
                                set: { model.choose($0, for: conflict.id) }
                            )) {
                                Text("Choose...").tag(Optional<RestoreChoice>.none)
                                Text("Library").tag(Optional(RestoreChoice.library))
                                Text("Backup").tag(Optional(RestoreChoice.archive))
                                if conflict.allowsKeepBoth { Text("Both").tag(Optional(RestoreChoice.keepBoth)) }
                            }
                            Text("Suggested: \(conflict.suggestedChoice == .archive ? "Backup" : "Library")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: { Text("Conflicts") } footer: { Text("Replacing a save keeps its current version as before restore. Both creates a separate copy.") }
            }
            MissingROMSection(builds: review.missingROMs)
            if !prepared.manifest.isGamePackage {
                Section {
                    Button("Replace Entire Library...", role: .destructive) { Task { await model.prepareReplacement() } }
                        .disabled(!model.canReplaceLibrary)
                } footer: {
                    Text("Writes an automatic backup first, then asks to replace every Game, Build, and save in this library.")
                }
            }
            if model.sessionIsActive { Section { Text("Close the current game before restoring.") } }
        }
    }
}

struct MissingROMSection: View {
    let builds: [RestoreMissingROM]
    var body: some View {
        if !builds.isEmpty {
            Section {
                ForEach(builds) { build in Text(build.name) }
            } header: { Text("Builds Needing ROMs (\(builds.count))") } footer: { Text("These Builds will be kept. Import the same ROM later to restore its file.") }
        }
    }
}

struct RestoreReportView: View {
    let report: RestoreReport
    var body: some View {
        Form { RestoreReportSections(report: report) }
            .navigationTitle("Last Restore")
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct RestoreReportSections: View {
    let report: RestoreReport
    var body: some View {
        Section("Results") {
            LabeledContent("Added", value: "\(report.added)")
            LabeledContent("Skipped", value: "\(report.skipped)")
            LabeledContent("Conflicts Resolved", value: "\(report.resolutions.count)")
            Text(report.restoredAt, style: .date)
        }
        if !report.resolutions.isEmpty {
            Section("Resolutions") {
                ForEach(Array(report.resolutions.enumerated()), id: \.offset) { _, resolution in
                    LabeledContent(resolution.record, value: resolution.choice == .archive ? "Backup" : resolution.choice == .keepBoth ? "Both" : "Library")
                }
            }
        }
        MissingROMSection(builds: report.missingROMs)
        if let name = report.safetyBackupFilename { Section("Automatic Backup") { Text(name) } }
        if !report.notCarriedOver.isEmpty {
            Section("Not Carried Over") { ForEach(report.notCarriedOver, id: \.self) { Text($0) } }
        }
    }
}

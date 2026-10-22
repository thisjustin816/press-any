import AssetStorage
import EmulatorApplication
import EmulatorDomain
import SwiftUI
import UniformTypeIdentifiers

struct LibrarySettingsView: View {
    let store: any SettingsStore
    let integrityChecker: ManagedAssetIntegrityChecker?
    let libraryDeletion: LibraryDeletionOperations?
    let games: (any GameRepository)?
    let onCloseSettings: () -> Void
    @Environment(\.libraryStorageContext) private var libraryStorageContext

    @State private var showBackup = false
    @State private var showBackupPicker = false
    @State private var restoreSelection: BackupSelection?
    @State private var lastRestore: RestoreReport?
    @State private var backupError: String?
    @State private var showNameReview = false
    @State private var showFamilyMergeReview = false

    var body: some View {
        Form {
            Section("Preferences") {
                NavigationLink("Artwork") { ArtworkSettingsView(store: store) }
                NavigationLink("Regions and Languages") { ReleasePreferenceView(store: store) }
            }
            if libraryStorageContext != nil {
                Section("Organization") {
                    Button("Suggest Names") { showNameReview = true }
                    Button("Suggest Game Merges") { showFamilyMergeReview = true }
                }
            }
            Section("Files") {
                if let context = libraryStorageContext {
                    NavigationLink("Storage") {
                        StorageView(container: context.container) { session in
                            onCloseSettings()
                            context.onResumeQuickPlay(session)
                        }
                    }
                }
                if let integrityChecker {
                    NavigationLink("Check Library Files") {
                        Form { LibraryCheckSection(checker: integrityChecker) }
                            .scrollOverflowCue()
                            .navigationTitle("Check Library Files")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                }
                if let libraryDeletion, let games {
                    NavigationLink("Recently Deleted") {
                        RecentlyDeletedView(operations: libraryDeletion, games: games)
                    }
                }
            }
            if libraryStorageContext != nil {
                Section("Backup and Restore") {
                    Button("Back Up Library...") { showBackup = true }
                    Button("Restore from Backup...") { showBackupPicker = true }
                    if let lastRestore {
                        NavigationLink("Last Restore") { RestoreReportView(report: lastRestore) }
                    }
                }
            }
        }
        .scrollOverflowCue()
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showBackup) {
            if let context = libraryStorageContext { LibraryBackupView(container: context.container) }
        }
        .sheet(item: $restoreSelection, onDismiss: loadLastRestore) { selection in
            if let context = libraryStorageContext {
                LibraryRestoreView(container: context.container, url: selection.url,
                    onFinished: { restoreSelection = nil })
            }
        }
        .fileImporter(isPresented: $showBackupPicker, allowedContentTypes: [.zip]) { result in
            do { restoreSelection = BackupSelection(url: try result.get()) }
            catch { backupError = error.localizedDescription }
        }
        .alert("Backup", isPresented: Binding(get: { backupError != nil }, set: { if !$0 { backupError = nil } })) {
            Button("OK") { backupError = nil }
        } message: { Text(backupError ?? "") }
        .task { loadLastRestore() }
        .onReceive(NotificationCenter.default.publisher(for: .libraryDidChange)) { _ in loadLastRestore() }
        .sheet(isPresented: $showNameReview) {
            if let context = libraryStorageContext { NameReviewView(container: context.container) }
        }
        .sheet(isPresented: $showFamilyMergeReview) {
            if let context = libraryStorageContext { FamilyMergeReviewView(container: context.container) }
        }
    }

    private struct BackupSelection: Identifiable {
        let id = UUID()
        let url: URL
    }

    private func loadLastRestore() {
        guard let context = libraryStorageContext else { return }
        lastRestore = try? context.container.repositories.backup.lastRestoreReport()
    }
}

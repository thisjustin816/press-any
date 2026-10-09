import AssetStorage
import EmulatorApplication
import EmulatorDomain
import Foundation
import UniformTypeIdentifiers
import SwiftUI

/// App-wide settings, grouped into pages. Values are stored at the app scope, so a System, Game or
/// Build override still wins for that launch.
struct AppSettingsView: View {
    private let store: any SettingsStore
    @ObservedObject private var plus: PlusStore
    private let integrityChecker: ManagedAssetIntegrityChecker?
    private let libraryDeletion: LibraryDeletionOperations?
    private let games: (any GameRepository)?

    @State private var showBackup = false
    @State private var showBackupPicker = false
    @State private var restoreSelection: BackupSelection?
    @State private var lastRestore: RestoreReport?
    @State private var backupError: String?
    @State private var showNameReview = false
    @State private var showFamilyMergeReview = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.libraryStorageContext) private var libraryStorageContext

    init(
        store: any SettingsStore,
        plus: PlusStore,
        integrityChecker: ManagedAssetIntegrityChecker? = nil,
        libraryDeletion: LibraryDeletionOperations? = nil,
        games: (any GameRepository)? = nil
    ) {
        self.store = store
        _plus = ObservedObject(wrappedValue: plus)
        self.integrityChecker = integrityChecker
        self.libraryDeletion = libraryDeletion
        self.games = games
    }

    var body: some View {
        NavigationStack {
            Form {
                // The same order as a system's, Game's or Build's settings.
                Section {
                    NavigationLink {
                        DisplaySettingsPage(storage: storage, plus: plus)
                    } label: {
                        Label("Display", systemImage: "display")
                    }
                    NavigationLink {
                        ControlsSettingsPage(storage: storage)
                    } label: {
                        Label("Controls", systemImage: "gamecontroller")
                    }
                    NavigationLink {
                        PlayingSettingsPage(storage: storage, plus: plus)
                    } label: {
                        Label("Playing", systemImage: "play.circle")
                    }
                    NavigationLink {
                        AppIconSettingsPage(plus: plus)
                    } label: {
                        HStack(spacing: 6) {
                            Label("App Icon", systemImage: "paintpalette")
                            if !plus.isUnlocked { PlusBadge() }
                        }
                    }
                }

                Section {
                    ForEach(GameSystem.allCases, id: \.self) { system in
                        NavigationLink(system.displayName) {
                            ScopedSettingsView(
                                title: "\(system.displayName) Settings",
                                scope: .system(system),
                                system: system,
                                gameID: nil,
                                buildID: nil,
                                store: store,
                                plus: plus,
                                inSheet: false
                            )
                        }
                    }
                } header: {
                    Text("Systems")
                } footer: {
                    Text("Settings for every game on one system, including its Screen Colors. A Game or Build can still set its own.")
                }

                if (libraryDeletion != nil && games != nil) || integrityChecker != nil || libraryStorageContext != nil {
                    Section("Library") {
                        NavigationLink("Regions and Languages") { ReleasePreferenceView(store: store) }
                        if let libraryDeletion, let games {
                            NavigationLink("Recently Deleted") {
                                RecentlyDeletedView(operations: libraryDeletion, games: games)
                            }
                        }
                        if let integrityChecker {
                            NavigationLink("Check Library Files") {
                                Form { LibraryCheckSection(checker: integrityChecker) }
                                    .navigationTitle("Check Library Files")
                                    .navigationBarTitleDisplayMode(.inline)
                            }
                        }
                        if let context = libraryStorageContext {
                            Button("Back Up Library...") { showBackup = true }
                            Button("Restore from Backup...") { showBackupPicker = true }
                            if let lastRestore {
                                NavigationLink("Last Restore") { RestoreReportView(report: lastRestore) }
                            }
                            NavigationLink("Storage") {
                                StorageView(container: context.container) { session in
                                    dismiss()
                                    context.onResumeQuickPlay(session)
                                }
                            }
                            // Reviews open as sheets: each is a task with its own Cancel and confirm.
                            Button("Suggest Names") { showNameReview = true }
                            Button("Suggest Game Merges") { showFamilyMergeReview = true }
                        }
                    }
                }

                Section {
                    NavigationLink {
                        PlusView(store: plus)
                    } label: {
                        Label(PlusProduct.name, systemImage: "plus.circle")
                    }
                }

                Section("About") {
                    NavigationLink("How \(AppBrand.displayName) Works") { WelcomeView() }
                    if let privacyURL = URL(string: "https://github.com/thisjustin816/press-any/blob/main/PRIVACY.md") {
                        Link("Privacy Policy", destination: privacyURL)
                    }
                    NavigationLink("Acknowledgements") { AcknowledgementsView() }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
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
    }

    private struct BackupSelection: Identifiable {
        let id = UUID()
        let url: URL
    }

    private func loadLastRestore() {
        guard let context = libraryStorageContext else { return }
        lastRestore = try? context.container.repositories.backup.lastRestoreReport()
    }

    private var storage: AppSettingsStorage { AppSettingsStorage(store: store) }
}

import AssetStorage
import EmulatorApplication
import EmulatorDomain
import Foundation
import SwiftUI

/// App-wide settings, grouped into pages. Values are stored at the app scope, so a System, Game or
/// Build override still wins for that launch.
struct AppSettingsView: View {
    private let store: any SettingsStore
    private let integrityChecker: ManagedAssetIntegrityChecker?
    private let libraryDeletion: LibraryDeletionOperations?
    private let games: (any GameRepository)?

    @State private var systemSettings: SystemSettingsTarget?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.libraryStorageContext) private var libraryStorageContext

    init(
        store: any SettingsStore,
        integrityChecker: ManagedAssetIntegrityChecker? = nil,
        libraryDeletion: LibraryDeletionOperations? = nil,
        games: (any GameRepository)? = nil
    ) {
        self.store = store
        self.integrityChecker = integrityChecker
        self.libraryDeletion = libraryDeletion
        self.games = games
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        ControlsSettingsPage(storage: storage)
                    } label: {
                        Label("Controls", systemImage: "gamecontroller")
                    }
                    NavigationLink {
                        DisplaySettingsPage(storage: storage)
                    } label: {
                        Label("Display", systemImage: "display")
                    }
                    NavigationLink {
                        PlayingSettingsPage(storage: storage)
                    } label: {
                        Label("Playing", systemImage: "play.circle")
                    }
                }

                Section {
                    ForEach(GameSystem.allCases, id: \.self) { system in
                        Button {
                            systemSettings = SystemSettingsTarget(system: system)
                        } label: {
                            LabeledContent(system.displayName) {
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .foregroundStyle(.primary)
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
                            NavigationLink("Storage") {
                                StorageView(container: context.container) { session in
                                    dismiss()
                                    context.onResumeQuickPlay(session)
                                }
                            }
                        }
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
            .sheet(item: $systemSettings) { target in
                ScopedSettingsView(
                    title: "\(target.system.displayName) Settings",
                    scope: .system(target.system),
                    system: target.system,
                    gameID: nil,
                    buildID: nil,
                    store: store
                )
            }
        }
    }

    private var storage: AppSettingsStorage { AppSettingsStorage(store: store) }
}

private struct SystemSettingsTarget: Identifiable {
    let system: GameSystem
    var id: GameSystem { system }
}

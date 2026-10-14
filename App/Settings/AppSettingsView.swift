import AssetStorage
import EmulatorApplication
import EmulatorDomain
import Foundation
import SwiftUI

/// App-wide settings, grouped into pages. Values are stored at the app scope, so a System, Game or
/// Build override still wins for that launch.
struct AppSettingsView: View {
    private let store: any SettingsStore
    @ObservedObject private var plus: PlusStore
    private let integrityChecker: ManagedAssetIntegrityChecker?
    private let libraryDeletion: LibraryDeletionOperations?
    private let games: (any GameRepository)?

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
                    Section {
                        NavigationLink("Library") {
                            LibrarySettingsView(store: store, integrityChecker: integrityChecker,
                                libraryDeletion: libraryDeletion, games: games, onCloseSettings: { dismiss() })
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
        }
    }

    private var storage: AppSettingsStorage { AppSettingsStorage(store: store) }
}

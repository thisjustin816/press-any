import EmulatorDomain
import Importing
import SwiftUI

/// A battery save opened from Files or shared by another app. It becomes a new Save Profile in the
/// chosen Game, so no existing save changes.
struct SharedSaveView: View {
    let file: SharedFile
    let container: AppContainer
    let onFinished: () -> Void

    @State private var games: [Game] = []
    @State private var gameID: UUID?
    @State private var profileName = ""
    @State private var errorMessage: String?
    @State private var importedProfile: SaveProfile?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("File", value: file.originalFilename)
                    Picker("Game", selection: $gameID) {
                        Text("Choose a Game").tag(nil as UUID?)
                        ForEach(games) { game in
                            Text(game.primaryTitle).tag(Optional(game.id))
                        }
                    }
                    .accessibilityIdentifier("sharedSave.gamePicker")
                    LabeledContent("Save Profile") {
                        TextField("New profile name", text: $profileName)
                            .accessibilityLabel("New profile name")
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text(games.isEmpty
                         ? "Import the game's ROM into your library first, then open this save again."
                         : "The save becomes a new Save Profile in this Game. Existing saves aren't changed.")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
                Section {
                    Button("Import Save") { importSave() }
                        .disabled(gameID == nil || profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Open Save")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onFinished)
                }
            }
            .task { load() }
            .alert("Save Imported", isPresented: Binding(
                get: { importedProfile != nil },
                set: { if !$0 { importedProfile = nil } }
            ), presenting: importedProfile) { _ in
                Button("Done", action: onFinished)
            } message: { profile in
                Text("“\(profile.displayName)” is ready in \(games.first { $0.id == profile.gameID }?.primaryTitle ?? "your library").")
            }
        }
        .interactiveDismissDisabled()
    }

    private func load() {
        profileName = (file.originalFilename as NSString).deletingPathExtension
        do {
            games = try container.repositories.games.fetchGames().sorted {
                $0.primaryTitle.localizedCaseInsensitiveCompare($1.primaryTitle) == .orderedAscending
            }
            var romFilenames: [(gameID: UUID, filename: String)] = []
            for game in games {
                for build in container.builds(in: game.id) {
                    if let filename = try container.repositories.assets.fetchAsset(id: build.imageAssetID)?.originalFilename {
                        romFilenames.append((game.id, filename))
                    }
                }
            }
            gameID = SaveFileMatcher.matchingGameID(
                forSaveNamed: file.originalFilename,
                games: games,
                romFilenames: romFilenames
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importSave() {
        guard let gameID else { return }
        do {
            importedProfile = try container.importBatterySave.execute(
                gameID: gameID,
                sourceURL: file.url,
                name: profileName.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            errorMessage = nil
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

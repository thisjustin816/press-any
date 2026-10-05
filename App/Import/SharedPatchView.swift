import EmulatorDomain
import Patching
import SwiftUI

struct SharedPatchView: View {
    let file: SharedFile
    let container: AppContainer
    let onFinished: () -> Void

    @State private var games: [Game] = []
    @State private var builds: [Build] = []
    @State private var gameID: UUID?
    @State private var buildID: UUID?
    @State private var displayName = ""
    @State private var errorMessage: String?
    @State private var mismatchedBuild: Build?
    @State private var createdBuild: Build?

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
                    Picker("Base Build", selection: $buildID) {
                        Text("Choose a Build").tag(nil as UUID?)
                        ForEach(builds) { build in
                            Text(build.displayName).tag(Optional(build.id))
                        }
                    }
                    .disabled(gameID == nil)
                    TextField("New Build name", text: $displayName)
                        .accessibilityLabel("New Build name")
                } footer: {
                    Text(games.isEmpty
                         ? "Import the original ROM into your library first, then open this patch again."
                         : "Choose the ROM this patch was made for. Applying it creates a new Build and keeps the original.")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
                Section {
                    Button("Apply Patch") { apply() }
                        .disabled(buildID == nil || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Open Patch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onFinished)
                }
            }
            .task {
                displayName = file.url.deletingPathExtension().lastPathComponent
                do {
                    games = try container.repositories.games.fetchGames().sorted {
                        $0.primaryTitle.localizedCaseInsensitiveCompare($1.primaryTitle) == .orderedAscending
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            .onChange(of: gameID) { _, selected in
                buildID = nil
                builds = []
                guard let selected else { return }
                do {
                    builds = try container.repositories.builds.fetchBuilds(gameID: selected).sorted {
                        $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            .alert("This patch expects a different ROM", isPresented: Binding(
                get: { mismatchedBuild != nil },
                set: { if !$0 { mismatchedBuild = nil } }
            ), presenting: mismatchedBuild) { build in
                Button("Apply Anyway", role: .destructive) { apply(to: build, ignoringBaseMismatch: true) }
                Button("Cancel", role: .cancel) { mismatchedBuild = nil }
            } message: { build in
                Text("“\(build.displayName)” doesn’t match the patch’s expected base. Applying it anyway may produce a game that doesn’t work.")
            }
            .alert("Build Created", isPresented: Binding(
                get: { createdBuild != nil },
                set: { if !$0 { createdBuild = nil } }
            ), presenting: createdBuild) { _ in
                Button("Done", action: onFinished)
            } message: { build in
                Text("“\(build.displayName)” is ready in your library.")
            }
        }
        .interactiveDismissDisabled()
    }

    private func apply() {
        guard let build = builds.first(where: { $0.id == buildID }) else { return }
        apply(to: build)
    }

    private func apply(to build: Build, ignoringBaseMismatch: Bool = false) {
        mismatchedBuild = nil
        do {
            createdBuild = try container.patchCreator.execute(.init(
                gameID: build.gameID,
                baseBuildID: build.id,
                patches: [.init(url: file.url, ignoreBaseMismatch: ignoringBaseMismatch)],
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
            errorMessage = nil
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
        } catch PatchError.sourceCRC32Mismatch, PatchError.sourceSizeMismatch {
            mismatchedBuild = build
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

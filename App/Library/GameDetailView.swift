import EmulatorApplication
import EmulatorDomain
import SwiftUI

struct GameDetailView: View {
    @StateObject private var model: GameDetailViewModel
    @State private var newProfileName = "Main"
    @State private var showNewProfile = false

    let container: AppContainer
    let onPlay: (LaunchContext) -> Void

    init(container: AppContainer, gameID: UUID, onPlay: @escaping (LaunchContext) -> Void) {
        self.container = container
        self.onPlay = onPlay
        _model = StateObject(wrappedValue: GameDetailViewModel(
            gameID: gameID,
            games: container.repositories.games,
            builds: container.repositories.builds,
            profiles: container.repositories.saveProfiles,
            buildOperations: container.buildOperations,
            createBlank: container.createBlankSaveProfile,
            duplicateProfile: container.duplicateSaveProfile
        ))
    }

    var body: some View {
        List {
            Section {
                Button {
                    launch(build: model.preferredBuild)
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.preferredBuild == nil)
            }

            Section("Builds") {
                ForEach(model.builds) { build in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                Text(build.displayName)
                                if build.isBase {
                                    Text("BASE")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(String(build.imageSHA256.prefix(12)) + "...")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.game?.preferredBuildID == build.id {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                                .accessibilityLabel("Preferred Build")
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { launch(build: build) }
                    .contextMenu {
                        Button("Play") { launch(build: build) }
                        Button("Set as Preferred") { model.setPreferredBuild(build) }
                        Button("Make Separate Game") {
                            _ = try? model.promote(build, title: build.displayName, mode: .move)
                        }
                    }
                }
            }

            Section("Save Profiles") {
                ForEach(model.saveProfiles) { profile in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(profile.displayName)
                            if let parent = profile.copiedFromProfileID {
                                Text("Copied from \(String(parent.uuidString.prefix(8)))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if model.game?.preferredSaveProfileID == profile.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contextMenu {
                        Button("Play with This Save") {
                            do {
                                onPlay(try model.launchContext(saveProfile: profile))
                            } catch {}
                        }
                        Button("Duplicate") {
                            model.duplicate(profile, name: profile.displayName + " Copy")
                        }
                    }
                }

                Button {
                    newProfileName = "New Save"
                    showNewProfile = true
                } label: {
                    Label("New Blank Save", systemImage: "plus.circle")
                }
            }
        }
        .navigationTitle(model.game?.primaryTitle ?? "Game")
        .navigationBarTitleDisplayMode(.inline)
        .task { model.reload() }
        .alert("New Save Profile", isPresented: $showNewProfile) {
            TextField("Name", text: $newProfileName)
            Button("Create") {
                model.createBlankProfile(name: newProfileName)
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Game Error", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { _ in }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
    }

    private func launch(build: Build?) {
        do {
            onPlay(try model.launchContext(build: build))
        } catch {
            model.reload()
        }
    }
}

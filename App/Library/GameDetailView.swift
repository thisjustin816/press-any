import EmulatorApplication
import EmulatorDomain
import SwiftUI
import UniformTypeIdentifiers

struct GameDetailView: View {
    private enum FileRequest {
        case patch(Build)
        case batterySave

        var contentTypes: [UTType] {
            switch self {
            case .patch: [.ipsPatch, .bpsPatch]
            case .batterySave: [.gameBoySave]
            }
        }
    }

    @StateObject private var model: GameDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var newProfileName = "Main"
    @State private var showNewProfile = false
    @State private var fileRequest: FileRequest?
    @State private var showFileImporter = false
    @State private var promotion: Build?
    @State private var promotionTitle = ""
    @State private var showMerge = false
    @State private var settingsTarget: SettingsTarget?

    private struct SettingsTarget: Identifiable {
        let id = UUID()
        let title: String
        let scope: SettingsScope
        let system: GameSystem
        let buildID: UUID?
    }

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
            duplicateProfile: container.duplicateSaveProfile,
            importSave: container.importBatterySave,
            patchCreator: container.patchCreator,
            evictImage: container.evictGeneratedImage
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

            Section {
                ForEach(model.builds) { build in
                    buildRow(build)
                }
            } header: {
                Text("Builds")
            } footer: {
                Text("Touch and hold a Build to pick its save, apply a patch or move it to its own Game.")
            }

            Section("Save Profiles") {
                ForEach(model.saveProfiles) { profile in
                    profileRow(profile)
                }

                Button {
                    newProfileName = "New Save"
                    showNewProfile = true
                } label: {
                    Label("New Blank Save", systemImage: "plus.circle")
                }
                Button {
                    request(.batterySave)
                } label: {
                    Label("Import .sav", systemImage: "square.and.arrow.down")
                }
            }
        }
        .navigationTitle(model.game?.primaryTitle ?? "Game")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        settingsTarget = SettingsTarget(
                            title: "Game Settings",
                            scope: .game(model.gameID),
                            system: model.preferredBuild?.system ?? .gameBoy,
                            buildID: nil
                        )
                    } label: {
                        Label("Game Settings…", systemImage: "gearshape")
                    }
                    Button {
                        showMerge = true
                    } label: {
                        Label("Merge Into Another Game…", systemImage: "arrow.triangle.merge")
                    }
                    .disabled(model.otherGames.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task { model.reload() }
        .onChange(of: model.gameRemoved) { _, removed in
            if removed { dismiss() }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: fileRequest?.contentTypes ?? [],
            allowsMultipleSelection: { if case .patch = fileRequest { true } else { false } }()
        ) { result in
            handleFiles(result)
        }
        .sheet(item: $settingsTarget) { target in
            ScopedSettingsView(
                title: target.title,
                scope: target.scope,
                system: target.system,
                gameID: model.gameID,
                buildID: target.buildID,
                store: container.repositories.settings
            )
        }
        .sheet(isPresented: $showMerge) {
            MergeGameSheet(
                sourceTitle: model.game?.primaryTitle ?? "",
                targets: model.otherGames
            ) { target, mode in
                model.merge(into: target, mode: mode)
            }
        }
        .alert("New Save Profile", isPresented: $showNewProfile) {
            TextField("Name", text: $newProfileName)
            Button("Create") {
                model.createBlankProfile(name: newProfileName)
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Make Separate Game", isPresented: Binding(
            get: { promotion != nil },
            set: { if !$0 { promotion = nil } }
        ), presenting: promotion) { build in
            TextField("Game Title", text: $promotionTitle)
            Button("Move") { model.promote(build, title: promotionTitle, mode: .move) }
            Button("Copy") { model.promote(build, title: promotionTitle, mode: .copy) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Move takes this Build out of this Game. Copy leaves it here as well.")
        }
        .alert("Different Base ROM", isPresented: Binding(
            get: { model.baseMismatch != nil },
            set: { if !$0 { model.baseMismatch = nil } }
        ), presenting: model.baseMismatch) { pending in
            Button("Apply Anyway") {
                model.baseMismatch = nil
                model.applyPatches(pending.urls, to: pending.build, ignoringBaseMismatch: true)
            }
            Button("Cancel", role: .cancel) { model.baseMismatch = nil }
        } message: { pending in
            Text("This patch was made for a different ROM than \(pending.build.displayName). Applying it anyway may produce a Build that doesn’t work. The original ROM and patch are kept either way.")
        }
        .alert(model.errorMessage == nil ? "Done" : "Game Error", isPresented: Binding(
            get: { model.errorMessage != nil || model.infoMessage != nil },
            set: { if !$0 { model.clearMessages() } }
        )) {
            Button("OK", role: .cancel) { model.clearMessages() }
        } message: {
            Text(model.errorMessage ?? model.infoMessage ?? "")
        }
    }

    private func buildRow(_ build: Build) -> some View {
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
                if build.sourceKind == .patchRecipe, let parent = model.buildName(id: build.parentBuildID) {
                    Text("Patched from \(parent)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let save = model.profileName(id: build.preferredSaveProfileID) {
                    Text("Plays \(save)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            Menu("Play with Save") {
                ForEach(model.saveProfiles) { profile in
                    Button(profile.displayName) { launch(build: build, profile: profile) }
                }
            }
            Menu("Default Save") {
                Button {
                    model.setDefaultProfile(nil, for: build)
                } label: {
                    if build.preferredSaveProfileID == nil {
                        Label("Game Default", systemImage: "checkmark")
                    } else {
                        Text("Game Default")
                    }
                }
                ForEach(model.saveProfiles) { profile in
                    Button {
                        model.setDefaultProfile(profile, for: build)
                    } label: {
                        if build.preferredSaveProfileID == profile.id {
                            Label(profile.displayName, systemImage: "checkmark")
                        } else {
                            Text(profile.displayName)
                        }
                    }
                }
            }
            Button("Set as Preferred") { model.setPreferredBuild(build) }
            Button("Build Settings…") {
                settingsTarget = SettingsTarget(
                    title: "\(build.displayName) Settings",
                    scope: .build(build.id),
                    system: build.system,
                    buildID: build.id
                )
            }
            Divider()
            Button("Apply Patch…") { request(.patch(build)) }
            if build.sourceKind == .patchRecipe {
                Button("Remove Generated Image") { model.removeGeneratedImage(of: build) }
            }
            Button("Make Separate Game…") {
                promotionTitle = build.displayName
                promotion = build
            }
        }
    }

    private func profileRow(_ profile: SaveProfile) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(profile.displayName)
                if let parent = profile.copiedFromProfileID {
                    Text("Copied from \(model.profileName(id: parent) ?? String(parent.uuidString.prefix(8)))")
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
            Button("Play with This Save") { launch(build: model.preferredBuild, profile: profile) }
            Button("Duplicate") {
                model.duplicate(profile, name: profile.displayName + " Copy")
            }
        }
    }

    private func request(_ request: FileRequest) {
        fileRequest = request
        showFileImporter = true
    }

    private func handleFiles(_ result: Result<[URL], Error>) {
        defer { fileRequest = nil }
        guard case .success(let urls) = result, !urls.isEmpty else { return }
        switch fileRequest {
        case .patch(let build):
            model.applyPatches(urls, to: build)
        case .batterySave:
            if let url = urls.first { model.importSave(from: url) }
        case nil:
            break
        }
    }

    private func launch(build: Build?, profile: SaveProfile? = nil) {
        do {
            onPlay(try model.launchContext(build: build, saveProfile: profile))
        } catch {
            model.reload()
        }
    }
}

private struct MergeGameSheet: View {
    let sourceTitle: String
    let targets: [Game]
    let onMerge: (Game, ReorganizationMode) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mode: ReorganizationMode = .move

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Builds", selection: $mode) {
                        Text("Move").tag(ReorganizationMode.move)
                        Text("Copy").tag(ReorganizationMode.copy)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(mode == .move
                         ? "\(sourceTitle)’s Builds and Save Profiles move into the Game you pick, and \(sourceTitle) is removed."
                         : "Copies of \(sourceTitle)’s Builds are added to the Game you pick. \(sourceTitle) stays as it is.")
                }

                Section("Merge Into") {
                    ForEach(targets) { game in
                        Button(game.primaryTitle) {
                            onMerge(game, mode)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Merge \(sourceTitle)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

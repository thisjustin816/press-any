import EmulatorApplication
import EmulatorDomain
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct GameDetailView: View {
    private enum FileRequest {
        case patch(Build)
        case variableMap(Build)
        case batterySave
        case replacementSave(SaveProfile)
        case artwork

        var contentTypes: [UTType] {
            switch self {
            case .patch: UTType.patchFileTypes
            // `.i`, `.sym` and `.noi` files have no system type; the import checks the contents.
            case .variableMap: [.data]
            case .batterySave, .replacementSave: UTType.saveFileTypes
            case .artwork: [.image]
            }
        }
    }

    @StateObject private var model: GameDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var newProfileName = "Main"
    @State private var showNewProfile = false
    @State private var fileRequest: FileRequest?
    @State private var showFileImporter = false
    @State private var promotion: Build?
    @State private var showMerge = false
    @State private var settingsTarget: SettingsTarget?
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var buildDetails: Build?
    @State private var cheatsBuild: Build?
    @State private var pendingReplacement: PendingReplacement?
    @State private var badgeTarget: SaveProfile?
    @State private var statesProfile: SaveProfile?
    @State private var badgeText = ""
    @State private var renamingBuild: Build?
    @State private var buildName = ""
    @State private var showRenameGame = false
    @State private var showGameExport = false
    @State private var gameTitle = ""

    private struct SettingsTarget: Identifiable {
        let id = UUID()
        let title: String
        let scope: SettingsScope
        let system: GameSystem
        let buildID: UUID?
    }

    let container: AppContainer
    let onPlay: (LaunchContext, LaunchStart) -> Void

    init(container: AppContainer, gameID: UUID, onPlay: @escaping (LaunchContext, LaunchStart) -> Void) {
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
            badges: container.setSaveProfileBadge,
            deletion: container.libraryDeletion,
            importSave: container.importBatterySave,
            patchCreator: container.patchCreator,
            evictImage: container.evictGeneratedImage,
            artwork: container.gameArtwork,
            variableMaps: container.attachVariableMap,
            replaceSave: container.replaceBatterySave,
            exporter: container.exportFiles,
            exportsDirectory: container.exportsDirectory
        ))
    }

    var body: some View {
        withProfileAlerts(withAlerts(withPresentations(list)))
            .navigationTitle(model.game?.primaryTitle ?? "Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .selectionControls(selection: $model.selection, available: model.selectableItems) {
                model.requestSelectedDeletion()
            }
            .batchDeletionAlert(plan: $model.pendingBatchDeletion, noun: "Items", confirm: model.confirm)
            .task { model.reload() }
            .onReceive(NotificationCenter.default.publisher(for: .libraryDidChange)) { _ in model.reload() }
    }

    // The screen is split into pieces the compiler type-checks one at a time; as one expression
    // it does not type-check in reasonable time.
    private var list: some View {
        List(selection: model.selection.isSelecting ? $model.selection.ids : nil) {
            if !model.selection.isSelecting {
                artworkSection
                lineageSection
                baseGameSection
                playSection
            }
            buildsSection
            profilesSection
            if !model.selection.isSelecting {
                statisticsSection
            }
        }
    }

    @ViewBuilder
    private var artworkSection: some View {
        if let game = model.game, let artworkURL = container.artworkURL(for: game) {
            Section {
                AsyncImage(url: artworkURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    ProgressView()
                }
                .frame(maxWidth: .infinity, maxHeight: 220)
            }
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var lineageSection: some View {
        if let lineage = model.game?.lineage {
            Section {
                LabeledContent("Split From", value: lineage.sourceTitle)
            }
        }
    }

    @ViewBuilder
    private var baseGameSection: some View {
        let titles = Array(Set(model.builds.compactMap { $0.baseGameReference?.title })).sorted()
        if !titles.isEmpty {
            Section("Base Game") {
                ForEach(titles, id: \.self) { Text($0) }
            }
        }
    }

    private var playSection: some View {
        Section {
            Button {
                launch(build: model.preferredBuild)
            } label: {
                VStack(spacing: 2) {
                    Label("Play", systemImage: "play.fill")
                        .labelStyle(.titleAndIcon)
                    if let summary = model.playSummary {
                        Text(summary)
                            .font(.caption)
                            .opacity(0.85)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("game.play")
            .disabled(model.preferredBuild == nil)
            .contextMenu {
                Button("Start Over", systemImage: "arrow.counterclockwise") {
                    launch(build: model.preferredBuild, start: .startOver)
                }
            }
        }
    }

    @ViewBuilder
    private var statisticsSection: some View {
        if let statistics = model.statistics, statistics.hasBeenPlayed {
            Section("Statistics") {
                LabeledContent("Playtime", value: BuildPlaytime.formatted(statistics.totalPlaytimeSeconds))
                LabeledContent("Sessions", value: statistics.sessionCount.formatted())
                LabeledContent("Last Played", value: PlayStatisticsDisplay.lastPlayed(statistics.lastPlayedAt))
            }
            .accessibilityIdentifier("game.statistics")
        }
    }

    private var buildsSection: some View {
        Section {
            ForEach(model.builds) { build in
                buildRow(build).tag(LibraryDeletionTarget(kind: .build, id: build.id))
            }
        } header: {
            Text("Builds")
        } footer: {
            Text("\(Image(systemName: "star.fill")) Play starts this Build. BASE is a clean ROM patches apply to. Touch and hold for more.")
        }
    }

    private var profilesSection: some View {
        Section {
            ForEach(model.saveProfiles) { profile in
                profileRow(profile).tag(LibraryDeletionTarget(kind: .saveProfile, id: profile.id))
            }

            if !model.selection.isSelecting {
                Button {
                    newProfileName = "New Save"
                    showNewProfile = true
                } label: {
                    Label("New Blank Save…", systemImage: "plus.circle")
                }
                Button {
                    request(.batterySave)
                } label: {
                    Label("Import Save File…", systemImage: "square.and.arrow.down")
                }
            }
        } header: {
            Text("Save Profiles")
        } footer: {
            Text("\(Image(systemName: "star.fill")) The preferred save, which Play uses unless a Build picks its own. Touch and hold for more.")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if !model.selection.isSelecting {
                let isFavorite = model.game?.isFavorite ?? false
                Button {
                    model.setFavorite(!isFavorite)
                } label: {
                    Label(isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: isFavorite ? "star.fill" : "star")
                }
                .accessibilityIdentifier("game.favorite")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if !model.selection.isSelecting {
                Menu {
                    Button {
                        settingsTarget = SettingsTarget(
                            title: "Game Settings",
                            scope: .game(model.gameID),
                            system: model.preferredBuild?.system ?? .gameBoy,
                            buildID: nil
                        )
                    } label: {
                        Label("Game Settings", systemImage: "gearshape")
                    }
                    Button("Rename Game…", systemImage: "pencil") {
                        gameTitle = model.game?.primaryTitle ?? ""
                        showRenameGame = true
                    }
                    artworkMenu
                    Button("Export Game...", systemImage: "square.and.arrow.up") {
                        showGameExport = true
                    }
                    Button {
                        showMerge = true
                    } label: {
                        Label("Merge Into Another Game…", systemImage: "arrow.triangle.merge")
                    }
                    .disabled(model.otherGames.isEmpty)
                    Divider()
                    Button(role: .destructive) {
                        model.requestGameDeletion()
                    } label: {
                        Label("Delete Game", systemImage: "trash")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .accessibilityIdentifier("game.moreMenu")
            }
        }
    }

    private var artworkMenu: some View {
        Menu {
            Button {
                showPhotoPicker = true
            } label: {
                Label("From Photos…", systemImage: "photo")
            }
            Button {
                request(.artwork)
            } label: {
                Label("From Files…", systemImage: "folder")
            }
            if model.game?.artworkAssetID != nil {
                Button(role: .destructive) {
                    model.removeArtwork()
                } label: {
                    Label("Remove Artwork", systemImage: "trash")
                }
            }
        } label: {
            Label("Artwork", systemImage: "photo.on.rectangle")
        }
    }

    private func withPresentations(_ content: some View) -> some View {
        content
            .sheet(isPresented: $showGameExport) {
                LibraryBackupView(container: container, gameID: model.gameID)
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                photoItem = nil
                Task { await loadArtwork(item) }
            }
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
                    store: container.repositories.settings,
                    plus: container.plus
                )
            }
            .sheet(item: $buildDetails) { build in
                BuildDetailView(build: build, container: container)
            }
            .sheet(item: $cheatsBuild) { build in
                CheatListView(buildID: build.id, container: container)
            }
            .sheet(item: $statesProfile) { profile in
                SaveStatesView(profile: profile, container: container)
            }
            .sheet(isPresented: $showMerge) {
                MergeGameSheet(
                    source: model.game,
                    profiles: model.saveProfiles,
                    targets: model.otherGames,
                    suggest: { model.suggestedCarryOver(mergingInto: $0) }
                ) { target, mode, carryOver in
                    model.merge(into: target, mode: mode, carryOver: carryOver)
                }
            }
            .sheet(item: $promotion) { build in
                PromoteBuildSheet(
                    build: build,
                    sourceHasArtwork: model.game?.artworkAssetID != nil,
                    profiles: model.saveProfiles,
                    suggested: model.suggestedCarryOver(promoting: build)
                ) { title, mode, carryOver in
                    model.promote(build, title: title, mode: mode, carryOver: carryOver)
                }
            }
    }

    private func withProfileAlerts(_ content: some View) -> some View {
        content
            .alert("Badge", isPresented: Binding(
                get: { badgeTarget != nil },
                set: { if !$0 { badgeTarget = nil } }
            ), presenting: badgeTarget) { profile in
                TextField("Emoji", text: $badgeText)
                Button("Save") { model.setBadge(badgeText, of: profile) }
                if profile.badge != nil {
                    Button("Remove Badge", role: .destructive) { model.setBadge("", of: profile) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { profile in
                Text("One emoji shown beside \(profile.displayName).")
            }
            .alert(deletionTitle, isPresented: Binding(
                get: { model.pendingDeletion != nil },
                set: { if !$0 { model.pendingDeletion = nil } }
            ), presenting: model.pendingDeletion) { plan in
                Button("Delete \(plan.title)", role: .destructive) { model.confirm(plan) }
                Button("Cancel", role: .cancel) {}
            } message: { plan in
                Text(model.deletionMessage(for: plan))
            }
            .alert("Replace This Save?", isPresented: Binding(
                get: { pendingReplacement != nil },
                set: { if !$0 { pendingReplacement = nil } }
            ), presenting: pendingReplacement) { pending in
                Button("Replace", role: .destructive) { model.replaceSave(of: pending.profile, from: pending.url) }
                Button("Cancel", role: .cancel) {}
            } message: { pending in
                Text("\(pending.url.lastPathComponent) replaces the save in \(pending.profile.displayName). Its current save is copied to “\(pending.profile.displayName) before import” first.")
            }
    }

    private func withAlerts(_ content: some View) -> some View {
        content
            .alert("Rename Game", isPresented: $showRenameGame) {
                TextField("Game Title", text: $gameTitle)
                Button("Rename") { model.renameGame(to: gameTitle) }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Rename Build", isPresented: Binding(
                get: { renamingBuild != nil },
                set: { if !$0 { renamingBuild = nil } }
            ), presenting: renamingBuild) { build in
                TextField("Build Name", text: $buildName)
                Button("Rename") { model.rename(build, to: buildName) }
                Button("Cancel", role: .cancel) {}
            }
            .alert("New Save Profile", isPresented: $showNewProfile) {
                TextField("Name", text: $newProfileName)
                Button("Create") {
                    model.createBlankProfile(name: newProfileName)
                }
                Button("Cancel", role: .cancel) {}
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
                Text("This patch was made for a different ROM than \(pending.build.displayName).\n\n\(pending.details)\n\nApplying it anyway may produce a Build that doesn’t work. The original ROM and patch are kept either way.")
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

    private var deletionTitle: String {
        switch model.pendingDeletion?.kind {
        case .game: "Delete This Game?"
        case .build: "Delete This Build?"
        case .saveProfile, nil: "Delete This Save Profile?"
        case .saveState: "Delete This Save State?"
        }
    }

    @ViewBuilder
    private func buildRow(_ build: Build) -> some View {
        if model.selection.isSelecting {
            buildLabel(build)
        } else {
            buildLabel(build)
                .contentShape(Rectangle())
                .onTapGesture { launch(build: build) }
                .swipeActions(edge: .trailing) { SwipeDeleteButton { model.requestDeletion(of: build) } }
                .contextMenu { buildMenu(build) }
        }
    }

    private func buildLabel(_ build: Build) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                // At accessibility sizes BASE gets its own line, so the name isn't squeezed.
                let nameLayout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 3))
                    : AnyLayout(HStackLayout(spacing: 5))
                nameLayout {
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
                // Names alone can't tell these Builds apart.
                if model.builds.contains(where: {
                    $0.id != build.id && $0.displayName.caseInsensitiveCompare(build.displayName) == .orderedSame
                }) {
                    Text("Added \(build.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let save = model.profileName(id: build.preferredSaveProfileID) {
                    Text("Plays \(save)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if model.preferredBuild?.id == build.id {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("Preferred Build")
            }
        }
    }

    @ViewBuilder
    private func buildMenu(_ build: Build) -> some View {
        Section {
            Button("Play", systemImage: "play.fill") { launch(build: build) }
            Button("Start Over", systemImage: "arrow.counterclockwise") { launch(build: build, start: .startOver) }
            Menu {
                ForEach(model.saveProfiles) { profile in
                    Button(profile.title) { launch(build: build, profile: profile) }
                }
            } label: {
                Label("Play with Save", systemImage: "play.circle")
            }
        }
        Section {
            Button("Set as Preferred Build", systemImage: "star") { model.setPreferredBuild(build) }
                .disabled(model.preferredBuild?.id == build.id)
            preferredSaveMenu(build)
            if build.sourceKind != .patchRecipe {
                Button(build.isBase ? "Unmark as Base Build" : "Mark as Base Build", systemImage: "square.stack.3d.down.right") {
                    model.setBase(build, isBase: !build.isBase)
                }
            }
        }
        Section {
            Button("Rename Build…", systemImage: "pencil") {
                buildName = build.displayName
                renamingBuild = build
            }
            Button("Build Info", systemImage: "info.circle") { buildDetails = build }
            Button("Cheats", systemImage: "wand.and.stars") { cheatsBuild = build }
            Button("Build Settings", systemImage: "gearshape") {
                settingsTarget = SettingsTarget(
                    title: "\(build.displayName) Settings",
                    scope: .build(build.id),
                    system: build.system,
                    buildID: build.id
                )
            }
        }
        Section {
            Menu {
                Button("Apply Patch…", systemImage: "bandage") { request(.patch(build)) }
                Button("Attach Variable Map…", systemImage: "list.bullet.rectangle") { request(.variableMap(build)) }
                Button("Export ROM", systemImage: "square.and.arrow.up") { model.exportROM(of: build) }
                if build.sourceKind == .patchRecipe {
                    Button("Remove Generated Image", systemImage: "xmark.bin") { model.removeGeneratedImage(of: build) }
                }
            } label: {
                Label("ROM and Patches", systemImage: "doc.badge.gearshape")
            }
        }
        Section {
            Button("Make Separate Game…", systemImage: "rectangle.portrait.and.arrow.right") { promotion = build }
            Button(role: .destructive) { model.requestDeletion(of: build) } label: { Label("Delete Build", systemImage: "trash") }
        }
    }

    /// Which save this Build plays: the Game's preferred save, or one of its own.
    private func preferredSaveMenu(_ build: Build) -> some View {
        Menu {
            Button {
                model.setDefaultProfile(nil, for: build)
            } label: {
                let title = "Game's Preferred Save" + (model.defaultSaveProfile.map { " (\($0.title))" } ?? "")
                if build.preferredSaveProfileID == nil {
                    Label(title, systemImage: "checkmark")
                } else {
                    Text(title)
                }
            }
            ForEach(model.saveProfiles) { profile in
                Button {
                    model.setDefaultProfile(profile, for: build)
                } label: {
                    if build.preferredSaveProfileID == profile.id {
                        Label(profile.title, systemImage: "checkmark")
                    } else {
                        Text(profile.title)
                    }
                }
            }
        } label: {
            Label("Preferred Save", systemImage: "externaldrive")
        }
    }

    private func profileRow(_ profile: SaveProfile) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(profile.title)
                if profile.totalPlaytimeSeconds > 0 || profile.sessionCount > 0 || profile.lastPlayedAt != nil {
                    Text("\(BuildPlaytime.formatted(profile.totalPlaytimeSeconds)) · \(PlayStatisticsDisplay.played(profile.lastPlayedAt, hasBeenPlayed: true))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // A copy brought from another Game by a promote or merge has its original there.
                if let parent = model.profileName(id: profile.copiedFromProfileID) {
                    Text("Copied from \(parent)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if model.defaultSaveProfile?.id == profile.id {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("Preferred Save")
            }
        }
        .swipeActions(edge: .trailing) { SwipeDeleteButton { model.requestDeletion(of: profile) } }
        .contextMenu {
            if !model.selection.isSelecting {
                Button("Play with This Save", systemImage: "play.fill") { launch(build: model.preferredBuild, profile: profile) }
                Section {
                    Button("Save States", systemImage: "square.stack") { statesProfile = profile }
                    Button("Set as Preferred Save", systemImage: "star") { model.setPreferredSave(profile) }
                        .disabled(model.defaultSaveProfile?.id == profile.id)
                    Button("Badge…", systemImage: "face.smiling") {
                        badgeText = profile.badge ?? ""
                        badgeTarget = profile
                    }
                    Button("Duplicate", systemImage: "plus.square.on.square") {
                        model.duplicate(profile, name: profile.displayName + " Copy")
                    }
                }
                Section {
                    Button("Replace from File…", systemImage: "square.and.arrow.down") { request(.replacementSave(profile)) }
                    if profile.persistentSaveAssetID != nil {
                        Button("Export Save", systemImage: "square.and.arrow.up") { model.exportSave(of: profile) }
                    }
                }
                Button(role: .destructive) { model.requestDeletion(of: profile) } label: { Label("Delete Save Profile", systemImage: "trash") }
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
        case .variableMap(let build):
            if let url = urls.first { model.attachVariableMap(from: url, to: build) }
        case .batterySave:
            if let url = urls.first { model.importSave(from: url) }
        case .replacementSave(let profile):
            guard let url = urls.first else { break }
            // Replacing a blank profile loses nothing, so only a profile with a save asks first.
            if profile.persistentSaveAssetID == nil {
                model.replaceSave(of: profile, from: url)
            } else {
                pendingReplacement = PendingReplacement(profile: profile, url: url)
            }
        case .artwork:
            if let url = urls.first { model.setArtwork(from: url) }
        case nil:
            break
        }
    }

    private func loadArtwork(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let fileExtension = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
        model.setArtwork(data, fileExtension: fileExtension)
    }

    private func launch(build: Build?, profile: SaveProfile? = nil, start: LaunchStart = .resumeGames) {
        guard !model.selection.isSelecting else { return }
        do {
            onPlay(try model.launchContext(build: build, saveProfile: profile), start)
        } catch {
            model.report(error)
        }
    }
}

/// Promotes a Build to its own Game, with a review of what the new Game brings along.
private struct PromoteBuildSheet: View {
    let build: Build
    let sourceHasArtwork: Bool
    let profiles: [SaveProfile]
    let onPromote: (String, ReorganizationMode, GameCarryOver) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var mode: ReorganizationMode = .move
    @State private var carryOver: GameCarryOver

    init(
        build: Build,
        sourceHasArtwork: Bool,
        profiles: [SaveProfile],
        suggested: GameCarryOver,
        onPromote: @escaping (String, ReorganizationMode, GameCarryOver) -> Void
    ) {
        self.build = build
        self.sourceHasArtwork = sourceHasArtwork
        self.profiles = profiles
        self.onPromote = onPromote
        // A hack's own title names a Game better than its Build name, "v1.3".
        _title = State(initialValue: build.hackTitle.flatMap { $0.isEmpty ? nil : $0 } ?? build.displayName)
        _carryOver = State(initialValue: suggested)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Game Title", text: $title)
                }
                Section {
                    Picker("Build", selection: $mode) {
                        Text("Move").tag(ReorganizationMode.move)
                        Text("Copy").tag(ReorganizationMode.copy)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(mode == .move
                         ? "\(build.displayName) leaves this Game, with its save states and settings."
                         : "\(build.displayName) stays here, and a copy starts the new Game.")
                }
                CarryOverSection(
                    carryOver: $carryOver,
                    artworkLabel: sourceHasArtwork ? "Copy the Artwork" : nil,
                    profiles: profiles,
                    footer: "Chosen Save Profiles are copied; the originals stay here."
                )
            }
            .navigationTitle("Make Separate Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Make Game") {
                        onPromote(title, mode, carryOver)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

/// Merges this Game into another, with a review of the Game-level things that come along.
private struct MergeGameSheet: View {
    let source: Game?
    let profiles: [SaveProfile]
    let targets: [Game]
    let suggest: (Game) -> GameCarryOver
    let onMerge: (Game, ReorganizationMode, GameCarryOver) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mode: ReorganizationMode = .move
    @State private var target: Game?
    @State private var carryOver = GameCarryOver.nothing

    private var sourceTitle: String { source?.primaryTitle ?? "" }

    var body: some View {
        NavigationStack {
            Form {
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
                        Button {
                            target = game
                            carryOver = suggest(game)
                        } label: {
                            HStack {
                                Text(game.primaryTitle)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if target?.id == game.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }

                if let target {
                    if mode == .move {
                        // A move takes every profile, so only the artwork is a choice, and only
                        // when both Games have some.
                        if source?.artworkAssetID != nil, target.artworkAssetID != nil {
                            Section {
                                Toggle("Use \(sourceTitle)’s Artwork", isOn: $carryOver.artwork)
                            } header: {
                                Text("Bring Along")
                            } footer: {
                                Text("Otherwise \(target.primaryTitle) keeps its own.")
                            }
                        }
                    } else {
                        CarryOverSection(
                            carryOver: $carryOver,
                            artworkLabel: source?.artworkAssetID == nil ? nil
                                : target.artworkAssetID == nil ? "Copy the Artwork" : "Replace \(target.primaryTitle)’s Artwork",
                            profiles: profiles,
                            footer: "Chosen Save Profiles are copied; the originals stay in \(sourceTitle)."
                        )
                    }
                }
            }
            .navigationTitle("Merge \(sourceTitle)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Merge") {
                        if let target { onMerge(target, mode, carryOver) }
                        dismiss()
                    }
                    .disabled(target == nil)
                }
            }
        }
    }
}

/// The review step's choices: the artwork, and each Save Profile.
private struct CarryOverSection: View {
    @Binding var carryOver: GameCarryOver
    /// Nil when there's no artwork to bring.
    let artworkLabel: String?
    let profiles: [SaveProfile]
    let footer: String

    var body: some View {
        if artworkLabel != nil || !profiles.isEmpty {
            Section {
                if let artworkLabel {
                    Toggle(artworkLabel, isOn: $carryOver.artwork)
                }
                ForEach(profiles) { profile in
                    Toggle(profile.title, isOn: Binding(
                        get: { carryOver.saveProfileIDs.contains(profile.id) },
                        set: { isOn in
                            if isOn {
                                carryOver.saveProfileIDs.insert(profile.id)
                            } else {
                                carryOver.saveProfileIDs.remove(profile.id)
                            }
                        }
                    ))
                }
            } header: {
                Text("Bring Along")
            } footer: {
                Text(footer)
            }
        }
    }
}

private struct PendingReplacement {
    let profile: SaveProfile
    let url: URL
}

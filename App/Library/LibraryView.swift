import EmulatorApplication
import EmulatorDomain
import Importing
import QuickPlay
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    enum DisplayMode: String, CaseIterable {
        case grid
        case list
    }

    private enum FileAction {
        case importFiles
        /// Carries the library save the session gets a copy of, if any.
        case quickPlay(copiedSaveProfileID: UUID?)

        var isImport: Bool {
            if case .importFiles = self { true } else { false }
        }
    }

    @StateObject private var model: LibraryViewModel
    @State private var displayMode: DisplayMode = .grid
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showROMImporter = false
    @State private var pendingFileAction: FileAction = .importFiles
    @State private var importReview: ImportReviewPresentation?
    @State private var showSettings = false
    @State private var settingsGame: Game?
    @State private var showSaveChooser = false
    @State private var chosenQuickPlaySave: UUID?
    @State private var showQuickPlaySessions = false
    @State private var quickPlayToResume: QuickPlaySession?
    @State private var screenshotGameID: UUID?
    @State private var screenshotBuildInfo: Build?
    @State private var gameToRename: Game?
    @State private var renameTitle = ""
    /// Drag handles in the list, for the Manual sort.
    @State private var isReordering = false
    /// Off hides the titles under grid tiles, for libraries whose box art carries the name.
    @AppStorage("library.showsGridTitles") private var showsGridTitles = true
    @AppStorage("library.sort") private var sort: LibrarySort = .title

    let container: AppContainer
    let onPlay: (LaunchContext, LaunchStart) -> Void
    let onQuickPlay: (QuickPlayRequest) -> Void
    let onResumeQuickPlay: (QuickPlaySession) -> Void
    /// Files chosen with Import Files, handled as if shared to the app.
    let onImportFiles: ([URL]) -> Void

    private let importCoordinator: ImportCoordinator

    init(
        container: AppContainer,
        onPlay: @escaping (LaunchContext, LaunchStart) -> Void,
        onQuickPlay: @escaping (QuickPlayRequest) -> Void,
        onResumeQuickPlay: @escaping (QuickPlaySession) -> Void,
        onImportFiles: @escaping ([URL]) -> Void
    ) {
        self.container = container
        self.onPlay = onPlay
        self.onQuickPlay = onQuickPlay
        self.onResumeQuickPlay = onResumeQuickPlay
        self.onImportFiles = onImportFiles
        let coordinator = ImportCoordinator(
            analyzer: container.importAnalyzer,
            committer: container.importCommitter,
            assetStore: container.fileStore
        )
        importCoordinator = coordinator
        _model = StateObject(wrappedValue: LibraryViewModel(
            gameRepository: container.repositories.games,
            buildRepository: container.repositories.builds,
            profiles: container.repositories.saveProfiles,
            launchResolver: container.preferredLaunchResolver,
            buildOperations: container.buildOperations,
            deletion: container.libraryDeletion
        ))
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.visibleGames.isEmpty {
                    ContentUnavailableView {
                        Label("No Games", systemImage: "gamecontroller")
                    } description: {
                        Text(model.favoritesOnly
                             ? "No favorite games match this view."
                             : model.searchText.isEmpty
                             ? "Import a Game Boy or Game Boy Color ROM to get started."
                             : "No games match your search.")
                    } actions: {
                        if model.searchText.isEmpty && !model.favoritesOnly {
                            Button("Import Files…") {
                                pendingFileAction = .importFiles
                                showROMImporter = true
                            }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                } else if displayMode == .grid {
                    gameGrid
                } else {
                    gameList
                }
            }
            .navigationTitle(AppBrand.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $model.searchText, prompt: "Search games")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    WordmarkView(size: 26)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if isReordering {
                        Button("Done") { isReordering = false }
                    }
                    // Select and the view options live in this menu, as in Photos and Files: more
                    // toolbar buttons left the wordmark no room at larger text sizes.
                    Menu {
                        if !model.selection.isSelecting && !isReordering {
                            Section {
                                Button("Select", systemImage: "checkmark.circle") { model.selection.toggleMode() }
                                    .disabled(model.visibleGames.isEmpty)
                                // Dragging works in the list; the grid shows the same order.
                                if sort == .manual && displayMode == .list {
                                    Button("Reorder", systemImage: "line.3.horizontal") { isReordering = true }
                                        .disabled(model.visibleGames.count < 2)
                                        .accessibilityIdentifier("library.reorder")
                                }
                            }
                        }
                        // Grid and List as one row of icons, as Files shows its view styles.
                        Picker("Library View", selection: $displayMode) {
                            Label("Grid", systemImage: "square.grid.2x2").tag(DisplayMode.grid)
                            Label("List", systemImage: "list.bullet").tag(DisplayMode.list)
                        }
                        .pickerStyle(.palette)
                        Picker(selection: $sort) {
                            ForEach(LibrarySort.allCases, id: \.self) { order in
                                Text(order.displayName).tag(order)
                            }
                        } label: {
                            Label("Sort By", systemImage: "arrow.up.arrow.down")
                            Text(sort.displayName)
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("library.sortMenu")
                        if displayMode == .grid {
                            Toggle("Show Titles", isOn: $showsGridTitles)
                        }
                        Toggle("Favorites Only", isOn: $model.favoritesOnly)
                            .accessibilityIdentifier("library.favoritesOnly")
                    } label: {
                        Label("More", systemImage: "ellipsis")
                    }
                    .accessibilityIdentifier("library.viewMenu")

                    Menu {
                        Button {
                            pendingFileAction = .importFiles
                            showROMImporter = true
                        } label: {
                            Label("Import Files…", systemImage: "square.and.arrow.down")
                        }
                        Section("Quick Play") {
                            Button {
                                pendingFileAction = .quickPlay(copiedSaveProfileID: nil)
                                showROMImporter = true
                            } label: {
                                Label("Quick Play ROM…", systemImage: "play.circle")
                            }
                            Button {
                                showSaveChooser = true
                            } label: {
                                Label("Quick Play with a Save…", systemImage: "play.circle.fill")
                            }
                            Button {
                                showQuickPlaySessions = true
                            } label: {
                                Label("Quick Play Sessions", systemImage: "clock.arrow.circlepath")
                            }
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .accessibilityIdentifier("library.addMenu")
                }
            }
            .selectionControls(
                selection: $model.selection, available: Set(model.visibleGames.map(\.id)),
                selectAll: true, selectInToolbar: false
            ) {
                model.requestSelectedDeletion()
            }
            .batchDeletionAlert(plan: $model.pendingBatchDeletion, noun: "Games", confirm: model.confirm)
            .onAppear {
                model.sort = sort
                model.reload()
            }
            .onChange(of: sort) { _, value in
                model.sort = value
                if value != .manual { isReordering = false }
            }
            .onChange(of: displayMode) { _, mode in
                if mode != .list { isReordering = false }
            }
            .task { openScreenshotScene() }
            .navigationDestination(item: $screenshotGameID) { gameID in
                GameDetailView(container: container, gameID: gameID, onPlay: onPlay)
            }
            .sheet(item: $screenshotBuildInfo) { build in
                BuildTechnicalInfoView(build: build, container: container)
            }
            // Quick Play promotion adds Games from sheets this screen doesn't own.
            .onReceive(NotificationCenter.default.publisher(for: .libraryDidChange)) { _ in model.reload() }
            .refreshable { model.reload() }
            .fileImporter(
                isPresented: $showROMImporter,
                allowedContentTypes: pendingFileAction.isImport ? UTType.importFileTypes : UTType.romFileTypes,
                allowsMultipleSelection: pendingFileAction.isImport
            ) { result in
                handleImportSelection(result)
            }
            .sheet(isPresented: $showSaveChooser, onDismiss: {
                // The file picker opens after the chooser is gone, so choosing the file is the
                // last step before the session starts and its first-frame time stays clean.
                guard let profileID = chosenQuickPlaySave else { return }
                chosenQuickPlaySave = nil
                pendingFileAction = .quickPlay(copiedSaveProfileID: profileID)
                showROMImporter = true
            }) {
                QuickPlaySaveChooser(container: container) { profile in
                    chosenQuickPlaySave = profile.id
                }
            }
            .sheet(isPresented: $showQuickPlaySessions, onDismiss: {
                guard let session = quickPlayToResume else { return }
                quickPlayToResume = nil
                onResumeQuickPlay(session)
            }) {
                QuickPlaySessionsView(container: container) { session in
                    quickPlayToResume = session
                }
            }
            .sheet(item: $importReview) { presentation in
                ImportReviewView(
                    model: presentation.model,
                    onImported: { _ in model.reload() },
                    onCancel: {}
                )
            }
            .sheet(item: $settingsGame) { game in
                ScopedSettingsView(
                    title: "Game Settings",
                    scope: .game(game.id),
                    system: model.system(of: game),
                    gameID: game.id,
                    buildID: nil,
                    store: container.repositories.settings
                )
            }
            .sheet(isPresented: $showSettings) {
                AppSettingsView(
                    store: container.repositories.settings,
                    integrityChecker: container.integrityChecker,
                    libraryDeletion: container.libraryDeletion,
                    games: container.repositories.games
                )
            }
            .alert("Rename Game", isPresented: Binding(
                get: { gameToRename != nil },
                set: { if !$0 { gameToRename = nil } }
            ), presenting: gameToRename) { game in
                TextField("Game Title", text: $renameTitle)
                Button("Rename") { model.renameGame(game, to: renameTitle) }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Library Error", isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.clearError() } }
            )) {
                Button("OK", role: .cancel) { model.clearError() }
            } message: {
                Text(model.errorMessage ?? "Unknown error")
            }
        }
    }

    private var gameGrid: some View {
        ScrollView {
            // At accessibility text sizes two columns leave titles room for a word or two.
            let columns = typeSize.isAccessibilitySize
                ? [GridItem(.flexible(), alignment: .top)]
                : [GridItem(.adaptive(minimum: 145), spacing: 16, alignment: .top)]
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(model.visibleGames) { game in
                    if model.selection.isSelecting {
                        Button { model.selection.toggle(game.id) } label: {
                            gameTile(game)
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: model.selection.ids.contains(game.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.title2)
                                        .foregroundStyle(Color.accentColor)
                                        .padding(8)
                                        .background(.regularMaterial, in: Circle())
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(game.primaryTitle)
                        .accessibilityValue(model.selection.ids.contains(game.id) ? "Selected" : "Not selected")
                        .accessibilityAddTraits(model.selection.ids.contains(game.id) ? .isSelected : [])
                    } else {
                        NavigationLink {
                            GameDetailView(container: container, gameID: game.id, onPlay: onPlay)
                        } label: { gameTile(game) }
                        .buttonStyle(.plain)
                        .contextMenu { gameActions(game) }
                    }
                }
            }
            .padding()
        }
    }

    private func gameTile(_ game: Game) -> some View {
        GameLibraryTile(game: game, system: model.system(of: game), artworkURL: container.artworkURL(for: game), showsTitle: showsGridTitles)
    }

    private var gameList: some View {
        List(selection: model.selection.isSelecting ? $model.selection.ids : nil) {
            ForEach(model.visibleGames) { game in
                Group {
                    if model.selection.isSelecting || isReordering {
                        gameListLabel(game)
                    } else {
                        NavigationLink {
                            GameDetailView(container: container, gameID: game.id, onPlay: onPlay)
                        } label: { gameListLabel(game) }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button("Play") { launch(game) }.tint(.accentColor)
                        }
                        .swipeActions(edge: .trailing) { SwipeDeleteButton { model.requestDeletion(of: game) } }
                        .contextMenu { gameActions(game) }
                    }
                }
                .tag(game.id)
            }
            .onMove(perform: moveAction)
        }
        .listStyle(.plain)
        // Drag handles show only in edit mode, which Select also turns on for its checkboxes.
        .environment(\.editMode, .constant(model.selection.isSelecting || isReordering ? .active : .inactive))
    }

    /// Nil outside Reorder, so Select's edit mode shows checkboxes without drag handles.
    private var moveAction: ((IndexSet, Int) -> Void)? {
        guard isReordering else { return nil }
        return { source, destination in
            var ids = model.visibleGames.map(\.id)
            ids.move(fromOffsets: source, toOffset: destination)
            model.reorder(visible: ids)
        }
    }

    private func gameListLabel(_ game: Game) -> some View {
        HStack(spacing: 12) {
            GameArtworkView(url: container.artworkURL(for: game), system: model.system(of: game), title: game.primaryTitle)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(game.primaryTitle).font(.headline)
                    if game.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("Favorite")
                    }
                }
                Text(listSubtitle(for: game))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func listSubtitle(for game: Game) -> String {
        switch sort {
        case .title, .system, .manual:
            model.system(of: game).displayName
        case .recentlyPlayed:
            PlayStatisticsDisplay.played(
                model.statistics[game.id]?.lastPlayedAt,
                hasBeenPlayed: model.statistics[game.id]?.hasBeenPlayed ?? false
            )
        case .recentlyAdded:
            "Added \(game.createdAt.formatted(date: .abbreviated, time: .omitted))"
        case .recentlyChanged:
            model.statistics[game.id]?.lastBuildChangeAt.map { "Changed \(PlayStatisticsDisplay.lastPlayed($0))" } ?? "No Builds"
        case .playtime:
            BuildPlaytime.formatted(model.statistics[game.id]?.totalPlaytimeSeconds ?? 0)
        case .hackAuthor:
            LibrarySort.hackAuthor(of: model.preferredBuilds[game.id]) ?? "No Author"
        case .version:
            model.preferredBuilds[game.id]?.versionString.map { "Version \($0)" } ?? "No Version"
        }
    }

    @ViewBuilder
    private func gameActions(_ game: Game) -> some View {
        Section {
            Button("Play", systemImage: "play.fill") { launch(game) }
            Button("Start Over", systemImage: "arrow.counterclockwise") { launch(game, start: .startOver) }
        }
        Section {
            Button(game.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                   systemImage: game.isFavorite ? "star.slash" : "star") {
                model.toggleFavorite(game)
            }
            .accessibilityIdentifier("library.toggleFavorite")
            Button("Rename…", systemImage: "pencil") {
                renameTitle = game.primaryTitle
                gameToRename = game
            }
            Button("Game Settings", systemImage: "gearshape") { settingsGame = game }
        }
        Button(role: .destructive) { model.requestDeletion(of: game) } label: { Label("Delete Game", systemImage: "trash") }
    }

    private func launch(_ game: Game, start: LaunchStart = .resumeGames) {
        guard !model.selection.isSelecting else { return }
        do {
            onPlay(try model.launchContext(for: game), start)
        } catch {
            model.report("Couldn’t start \(game.primaryTitle): \(error.localizedDescription)")
        }
    }

    /// The library scenes; `RootView` opens the gameplay ones.
    private func openScreenshotScene() {
        switch ScreenshotScene.current {
        case .settings:
            showSettings = true
        case .game(let file):
            screenshotGameID = ScreenshotScene.build(romFile: file, in: container)?.gameID
        case .buildInfo(let file):
            screenshotBuildInfo = ScreenshotScene.build(romFile: file, in: container)
        case .importReview(let file):
            openImportReview(at: ScreenshotScene.romURL(file))
        default:
            break
        }
    }

    private func handleImportSelection(_ result: Result<[URL], Error>) {
        let chosenAt = DispatchTime.now().uptimeNanoseconds
        guard case .success(let urls) = result, let url = urls.first else { return }
        switch pendingFileAction {
        case .quickPlay(let copiedSaveProfileID):
            onQuickPlay(QuickPlayRequest(url: url, copiedSaveProfileID: copiedSaveProfileID, chosenAt: chosenAt))
        case .importFiles:
            onImportFiles(urls)
        }
    }

    /// Opens Import Review for a ROM directly, as the screenshot scenes do.
    private func openImportReview(at url: URL) {
        do {
            let analysis = try importCoordinator.analyzeROM(at: url)
            let reviewModel = ImportReviewViewModel(
                analysis: analysis,
                games: model.games,
                coordinator: importCoordinator,
                existingBuilds: { container.builds(in: $0) },
                setArtwork: { _ = try container.gameArtwork.set(gameID: $0, imageData: $1, fileExtension: $2) },
                knownDumps: container.knownDumps,
                releasePreference: (try? ReleasePreferenceStore(store: container.repositories.settings).load()) ?? ReleasePreference()
            )
            importReview = ImportReviewPresentation(model: reviewModel)
        } catch {
            model.report("Couldn’t read \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }
}

private extension LibrarySort {
    var displayName: String {
        switch self {
        case .title: "Title"
        case .recentlyPlayed: "Recently Played"
        case .recentlyAdded: "Recently Added"
        case .recentlyChanged: "Recently Changed"
        case .playtime: "Playtime"
        case .system: "System"
        case .hackAuthor: "Hack Author"
        case .version: "Version"
        case .manual: "Manual"
        }
    }
}

private struct ImportReviewPresentation: Identifiable {
    let id = UUID()
    let model: ImportReviewViewModel
}

private struct GameLibraryTile: View {
    let game: Game
    let system: GameSystem
    let artworkURL: URL?
    let showsTitle: Bool

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GameArtworkView(url: artworkURL, system: system, title: game.primaryTitle)
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .topTrailing) {
                    if game.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .padding(6)
                            .background(.regularMaterial, in: Circle())
                            .padding(6)
                    }
                }
            if showsTitle {
                Text(game.primaryTitle)
                    .font(.headline)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // The title stays readable to VoiceOver when it isn't shown.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(game.isFavorite ? "\(game.primaryTitle), Favorite" : game.primaryTitle)
    }
}

/// The Game's assigned artwork, or a cartridge for its system with its title on the label.
private struct GameArtworkView: View {
    let url: URL?
    let system: GameSystem
    let title: String

    var body: some View {
        if let url {
            // The shape takes the frame the parent offers, and the image fills and is clipped to it.
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.quaternary)
                .overlay {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        ProgressView()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.quaternary)
            .overlay {
                GeometryReader { proxy in
                    CartridgeIcon(system: system, title: title)
                        .frame(width: min(proxy.size.width, proxy.size.height) * 0.64)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .clipped()
    }
}

/// A DMG Game Pak from the front, 57 by 65.5 mm, after a photograph of one: the app's name in
/// capitals pressed into the raised plaque, as GAME BOY is on the cartridge, short grip ridges
/// beside it, the lock notch at the top right, the framed label recess, and the arrow pointing
/// into the slot. Drawn in millimeters.
private struct CartridgeIcon: View {
    let system: GameSystem
    let title: String

    /// Game Boy Color cartridges take the brand's magenta, so the two systems tell apart at a glance.
    private var bodyStyle: AnyShapeStyle {
        system == .gameBoyColor
            ? AnyShapeStyle(Color(uiColor: AppBrand.Wordmark.accent).opacity(0.55))
            : AnyShapeStyle(.tertiary)
    }

    var body: some View {
        GeometryReader { proxy in
            let mm = proxy.size.width / 57
            let rect = { (x: Double, y: Double, width: Double, height: Double) -> CGRect in
                CGRect(x: x * mm, y: y * mm, width: width * mm, height: height * mm)
            }
            ZStack {
                CartridgeShape()
                    .fill(bodyStyle)
                Capsule()
                    .path(in: rect(9, 2, 40, 8.5))
                    .stroke(.background.opacity(0.3), lineWidth: max(0.5 * mm, 0.5))
                PlaqueLettering(mm: mm)
                    .position(x: 29 * mm, y: 6.25 * mm)
                Path { path in
                    let ridges = [(1.8, 2.6), (1.8, 4.6), (1.8, 6.6), (1.8, 8.6), (50.8, 4.6), (50.8, 6.6), (50.8, 8.6)]
                    for (x, y) in ridges {
                        path.addRoundedRect(in: rect(x, y, x < 10 ? 5.4 : 4.4, 0.9), cornerSize: CGSize(width: 0.45 * mm, height: 0.45 * mm))
                    }
                }
                .fill(.background.opacity(0.3))
                RoundedRectangle(cornerRadius: 1.5 * mm, style: .continuous)
                    .path(in: rect(4, 13, 49, 42.5))
                    .fill(.background.opacity(0.3))
                RoundedRectangle(cornerRadius: 1 * mm, style: .continuous)
                    .path(in: rect(5.4, 14.4, 46.2, 39.7))
                    .fill(.background.opacity(0.6))
                // Too small to read in the list's thumbnails, where the title sits beside it anyway.
                if proxy.size.width >= 50 {
                    Text(title)
                        .font(.system(size: 6 * mm, weight: .bold))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.6)
                        .frame(width: 40 * mm, height: 34 * mm)
                        .position(x: 28.5 * mm, y: 34.25 * mm)
                }
                Path { path in
                    path.move(to: CGPoint(x: 25.5 * mm, y: 57.2 * mm))
                    path.addLine(to: CGPoint(x: 31.5 * mm, y: 57.2 * mm))
                    path.addLine(to: CGPoint(x: 28.5 * mm, y: 60.7 * mm))
                    path.closeSubpath()
                }
                .fill(.background.opacity(0.3))
            }
        }
        .aspectRatio(57 / 65.5, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// The app's name in capitals, pressed into the cartridge's plaque the way the wordmark is pressed
/// into the controller's menu button. Lit from above, each letter's top edge shades a band of the
/// recess floor, and its bottom edge catches the light in a line below.
private struct PlaqueLettering: View {
    let mm: CGFloat

    var body: some View {
        let depth = 0.25 * mm
        ZStack {
            letters
                .foregroundStyle(.background.opacity(0.3))
            letters
                .foregroundStyle(.black.opacity(0.3))
                .mask { cutout(letters, removing: letters.offset(y: depth)) }
            letters
                .offset(y: depth)
                .foregroundStyle(.white.opacity(0.2))
                .mask { cutout(letters.offset(y: depth), removing: letters) }
        }
    }

    private var letters: some View {
        Text(AppBrand.displayName.uppercased())
            .font(Font(AppBrand.Wordmark.font(size: 5 * mm)))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(width: 34 * mm)
    }

    /// `shape` minus `removed`, as a mask.
    private func cutout(_ shape: some View, removing removed: some View) -> some View {
        ZStack {
            shape
            removed.blendMode(.destinationOut)
        }
        .compositingGroup()
    }
}

private struct CartridgeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let mm = rect.width / 57
        let radius = 1.5 * mm
        let notchX = rect.minX + 51 * mm
        let notchBottom = rect.minY + 2.5 * mm
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addLine(to: CGPoint(x: notchX, y: rect.minY))
        path.addLine(to: CGPoint(x: notchX, y: notchBottom))
        path.addLine(to: CGPoint(x: rect.maxX, y: notchBottom))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

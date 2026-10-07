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
        case importROM
        /// Carries the library save the session gets a copy of, if any.
        case quickPlay(copiedSaveProfileID: UUID?)
    }

    @StateObject private var model: LibraryViewModel
    @State private var displayMode: DisplayMode = .grid
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showROMImporter = false
    @State private var pendingFileAction: FileAction = .importROM
    @State private var importReview: ImportReviewPresentation?
    @State private var showSettings = false
    @State private var showBuildNameReview = false
    @State private var showFamilyMergeReview = false
    @State private var showSaveChooser = false
    @State private var chosenQuickPlaySave: UUID?
    @State private var showQuickPlaySessions = false
    @State private var quickPlayToResume: QuickPlaySession?
    @State private var screenshotGameID: UUID?
    @State private var screenshotBuildInfo: Build?
    /// Off hides the titles under grid tiles, for libraries whose box art carries the name.
    @AppStorage("library.showsGridTitles") private var showsGridTitles = true

    let container: AppContainer
    let onPlay: (LaunchContext) -> Void
    let onQuickPlay: (QuickPlayRequest) -> Void
    let onResumeQuickPlay: (QuickPlaySession) -> Void

    private let importCoordinator: ImportCoordinator

    init(
        container: AppContainer,
        onPlay: @escaping (LaunchContext) -> Void,
        onQuickPlay: @escaping (QuickPlayRequest) -> Void,
        onResumeQuickPlay: @escaping (QuickPlaySession) -> Void
    ) {
        self.container = container
        self.onPlay = onPlay
        self.onQuickPlay = onQuickPlay
        self.onResumeQuickPlay = onResumeQuickPlay
        let coordinator = ImportCoordinator(
            analyzer: container.importAnalyzer,
            committer: container.importCommitter,
            assetStore: container.fileStore
        )
        importCoordinator = coordinator
        _model = StateObject(wrappedValue: LibraryViewModel(
            gameRepository: container.repositories.games,
            buildRepository: container.repositories.builds,
            launchResolver: container.preferredLaunchResolver
        ))
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.visibleGames.isEmpty {
                    ContentUnavailableView {
                        Label("No Games", systemImage: "gamecontroller")
                    } description: {
                        Text(model.searchText.isEmpty
                             ? "Import a Game Boy or Game Boy Color ROM to get started."
                             : "No games match your search.")
                    } actions: {
                        if model.searchText.isEmpty {
                            Button("Import ROM") {
                                pendingFileAction = .importROM
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
                    Menu {
                        Picker("Library View", selection: $displayMode) {
                            Label("Grid", systemImage: "square.grid.2x2").tag(DisplayMode.grid)
                            Label("List", systemImage: "list.bullet").tag(DisplayMode.list)
                        }
                        if displayMode == .grid {
                            Toggle("Show Titles", isOn: $showsGridTitles)
                        }
                        Section {
                            Button {
                                showBuildNameReview = true
                            } label: {
                                Label("Suggest Build Names…", systemImage: "character.cursor.ibeam")
                            }
                            Button("Suggest Game Merges…", systemImage: "arrow.triangle.merge") {
                                showFamilyMergeReview = true
                            }
                        }
                    } label: {
                        Image(systemName: displayMode == .grid ? "square.grid.2x2" : "list.bullet")
                    }
                    .accessibilityIdentifier("library.viewMenu")

                    Menu {
                        Button {
                            pendingFileAction = .importROM
                            showROMImporter = true
                        } label: {
                            Label("Import ROM", systemImage: "square.and.arrow.down")
                        }
                        Section("Quick Play") {
                            Button {
                                pendingFileAction = .quickPlay(copiedSaveProfileID: nil)
                                showROMImporter = true
                            } label: {
                                Label("Quick Play ROM", systemImage: "play.circle")
                            }
                            Button {
                                showSaveChooser = true
                            } label: {
                                Label("Quick Play with a Save…", systemImage: "play.circle.fill")
                            }
                            Button {
                                showQuickPlaySessions = true
                            } label: {
                                Label("Quick Play Sessions…", systemImage: "clock.arrow.circlepath")
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("library.addMenu")
                }
            }
            .onAppear { model.reload() }
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
                allowedContentTypes: UTType.romFileTypes,
                allowsMultipleSelection: false
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
            .sheet(isPresented: $showFamilyMergeReview) {
                FamilyMergeReviewView(container: container)
            }
            .sheet(isPresented: $showBuildNameReview) {
                BuildNameReviewView(container: container)
            }
            .sheet(isPresented: $showSettings) {
                AppSettingsView(
                    store: container.repositories.settings,
                    integrityChecker: container.integrityChecker,
                    libraryDeletion: container.libraryDeletion,
                    games: container.repositories.games
                )
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
                    NavigationLink {
                        GameDetailView(container: container, gameID: game.id, onPlay: onPlay)
                    } label: {
                        GameLibraryTile(
                            game: game,
                            system: model.system(of: game),
                            artworkURL: container.artworkURL(for: game),
                            showsTitle: showsGridTitles
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Play") { launch(game) }
                    }
                }
            }
            .padding()
        }
    }

    private var gameList: some View {
        List(model.visibleGames) { game in
            NavigationLink {
                GameDetailView(container: container, gameID: game.id, onPlay: onPlay)
            } label: {
                HStack(spacing: 12) {
                    GameArtworkView(url: container.artworkURL(for: game), system: model.system(of: game), title: game.primaryTitle)
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(game.primaryTitle)
                            .font(.headline)
                        Text(model.system(of: game).displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button("Play") { launch(game) }
                    .tint(.accentColor)
            }
        }
        .listStyle(.plain)
    }

    private func launch(_ game: Game) {
        do {
            onPlay(try model.launchContext(for: game))
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
            handleImportSelection(.success([ScreenshotScene.romURL(file)]))
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
        case .importROM:
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
            if showsTitle {
                Text(game.primaryTitle)
                    .font(.headline)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // The title stays readable to VoiceOver when it isn't shown.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(game.primaryTitle)
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
/// capitals in the raised plaque, as GAME BOY is on the cartridge, short grip ridges beside it,
/// the lock notch at the top right, the framed label recess, and the arrow pointing into the slot.
/// Drawn in millimeters.
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
                Text(AppBrand.displayName.uppercased())
                    .font(Font(AppBrand.Wordmark.font(size: 5 * mm)))
                    .foregroundStyle(.background.opacity(0.3))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(width: 34 * mm)
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

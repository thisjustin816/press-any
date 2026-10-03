import EmulatorDomain
import Importing
import QuickPlay
import SwiftUI

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
    @State private var showROMImporter = false
    @State private var pendingFileAction: FileAction = .importROM
    @State private var importReview: ImportReviewPresentation?
    @State private var showSettings = false
    @State private var showSaveChooser = false
    @State private var chosenQuickPlaySave: UUID?
    @State private var showQuickPlaySessions = false
    @State private var quickPlayToResume: QuickPlaySession?

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
                    WordmarkView()
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
                    } label: {
                        Image(systemName: displayMode == .grid ? "square.grid.2x2" : "list.bullet")
                    }

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
                }
            }
            .onAppear { model.reload() }
            // Quick Play promotion adds Games from sheets this screen doesn't own.
            .onReceive(NotificationCenter.default.publisher(for: .libraryDidChange)) { _ in model.reload() }
            .refreshable { model.reload() }
            .fileImporter(
                isPresented: $showROMImporter,
                allowedContentTypes: [.gameBoyROM, .gameBoyColorROM],
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
            .sheet(isPresented: $showSettings) {
                AppSettingsView(store: container.repositories.settings)
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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 16)], spacing: 20) {
                ForEach(model.visibleGames) { game in
                    NavigationLink {
                        GameDetailView(container: container, gameID: game.id, onPlay: onPlay)
                    } label: {
                        GameLibraryTile(game: game, artworkURL: container.artworkURL(for: game))
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
                    GameArtworkView(title: game.primaryTitle, url: container.artworkURL(for: game))
                        .frame(width: 48, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(game.primaryTitle)
                            .font(.headline)
                        Text("Game Boy")
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
                    coordinator: importCoordinator
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
    let artworkURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GameArtworkView(title: game.primaryTitle, url: artworkURL)
                .aspectRatio(0.72, contentMode: .fit)
            Text(game.primaryTitle)
                .font(.headline)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The Game's assigned artwork, or a placeholder with its title.
private struct GameArtworkView: View {
    let title: String
    let url: URL?

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
                VStack(spacing: 6) {
                    Image(systemName: "gamecontroller.fill")
                        .font(.title2)
                    Text(title)
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 6)
                }
                .foregroundStyle(.secondary)
            }
            .clipped()
    }
}

import EmulatorDomain
import Importing
import SwiftUI

struct LibraryView: View {
    enum DisplayMode: String, CaseIterable {
        case grid
        case list
    }

    private enum FileAction {
        case importROM
        case quickPlay
    }

    @StateObject private var model: LibraryViewModel
    @State private var displayMode: DisplayMode = .grid
    @State private var showROMImporter = false
    @State private var pendingFileAction: FileAction = .importROM
    @State private var importReview: ImportReviewPresentation?
    @State private var showSettings = false

    let container: AppContainer
    let onPlay: (LaunchContext) -> Void
    let onQuickPlayROM: (URL) -> Void

    private let importCoordinator: ImportCoordinator

    init(
        container: AppContainer,
        onPlay: @escaping (LaunchContext) -> Void,
        onQuickPlayROM: @escaping (URL) -> Void
    ) {
        self.container = container
        self.onPlay = onPlay
        self.onQuickPlayROM = onQuickPlayROM
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
            .searchable(text: $model.searchText, prompt: "Search games")
            .toolbar {
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
                        Button {
                            pendingFileAction = .quickPlay
                            showROMImporter = true
                        } label: {
                            Label("Quick Play ROM", systemImage: "play.circle")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .task { model.reload() }
            .refreshable { model.reload() }
            .fileImporter(
                isPresented: $showROMImporter,
                allowedContentTypes: [.gameBoyROM, .gameBoyColorROM],
                allowsMultipleSelection: false
            ) { result in
                handleImportSelection(result)
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
                        GameLibraryTile(game: game)
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
                    GameArtworkPlaceholder(title: game.primaryTitle)
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
            // Reload will surface repository failures. Gameplay startup reports its own errors.
            model.reload()
        }
    }

    private func handleImportSelection(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        switch pendingFileAction {
        case .quickPlay:
            onQuickPlayROM(url)
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
                model.reload()
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GameArtworkPlaceholder(title: game.primaryTitle)
                .aspectRatio(0.72, contentMode: .fit)
            Text(game.primaryTitle)
                .font(.headline)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct GameArtworkPlaceholder: View {
    let title: String

    var body: some View {
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

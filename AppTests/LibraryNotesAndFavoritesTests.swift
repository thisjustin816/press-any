import EmulatorDomain
import Foundation
import XCTest
@testable import PressAny

@MainActor
final class LibraryNotesAndFavoritesTests: XCTestCase {
    func testBuildDetailsSavesPlainTextCancelsAndClearsNotes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try AppContainer(rootURL: root)
        let build = try importROM(into: container, root: root, title: "Example")
        let model = BuildDetailViewModel(buildID: build.id, builds: container.repositories.builds, operations: container.buildOperations)
        model.reload()
        model.editNotes()
        model.notesDraft = "  Route A\n**plain text**  "
        model.saveNotes()
        XCTAssertFalse(model.isEditingNotes)
        XCTAssertEqual(model.build?.notes, model.notesDraft)

        model.editNotes()
        model.notesDraft = "Canceled change"
        model.isEditingNotes = false
        model.reload()
        XCTAssertEqual(model.build?.notes, "  Route A\n**plain text**  ")

        try container.repositories.builds.addPlaytime(buildID: build.id, seconds: 125)
        model.editNotes()
        model.notesDraft = ""
        model.saveNotes()
        XCTAssertEqual(model.build?.notes, "")
        XCTAssertEqual(model.build?.totalPlaytimeSeconds, 125)
        let reopened = try AppContainer(rootURL: root)
        XCTAssertEqual(try reopened.repositories.builds.fetchBuild(id: build.id)?.notes, "")
        XCTAssertEqual(try reopened.repositories.builds.fetchBuild(id: build.id)?.totalPlaytimeSeconds, 125)
        XCTAssertFalse(BuildPlaytime.formatted(125).isEmpty)
        XCTAssertFalse(BuildPlaytime.formatted(0).isEmpty)
    }

    func testGameDetailsAndLibraryMenuToggleFavoritesAndFilterWithSearch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try AppContainer(rootURL: root)
        let first = try importROM(into: container, root: root, title: "Alpha")
        let second = try importROM(into: container, root: root, title: "Beta", byte: 1)
        let details = detailModel(container, gameID: second.gameID)
        details.reload()
        details.setFavorite(true)
        XCTAssertTrue(try XCTUnwrap(details.game).isFavorite)

        let library = LibraryViewModel(
            gameRepository: container.repositories.games, buildRepository: container.repositories.builds,
            profiles: container.repositories.saveProfiles,
            launchResolver: container.preferredLaunchResolver, buildOperations: container.buildOperations,
            deletion: container.libraryDeletion
        )
        library.reload()
        library.favoritesOnly = true
        XCTAssertEqual(library.visibleGames.map(\.id), [second.gameID])
        library.searchText = "Alpha"
        XCTAssertTrue(library.visibleGames.isEmpty)
        library.searchText = "Beta"
        XCTAssertEqual(library.visibleGames.map(\.id), [second.gameID])
        library.searchText = ""
        let alpha = try XCTUnwrap(container.repositories.games.fetchGame(id: first.gameID))
        library.toggleFavorite(alpha)
        XCTAssertEqual(library.visibleGames.map(\.id), [first.gameID, second.gameID])
        let beta = try XCTUnwrap(container.repositories.games.fetchGame(id: second.gameID))
        library.toggleFavorite(beta)
        XCTAssertEqual(library.visibleGames.map(\.id), [first.gameID])
        var favorite = try XCTUnwrap(container.repositories.games.fetchGame(id: first.gameID))
        favorite.addAliases(["Alternate Alpha"])
        try container.repositories.games.updateGame(favorite)
        library.reload()
        library.searchText = "Alternate"
        XCTAssertEqual(library.visibleGames.map(\.id), [first.gameID])
        library.searchText = ""
        library.toggleFavorite(alpha)
        XCTAssertTrue(library.visibleGames.isEmpty)
        library.toggleFavorite(alpha)
        library.favoritesOnly = false
        XCTAssertEqual(library.visibleGames.count, 2)
        let reopened = try AppContainer(rootURL: root)
        XCTAssertEqual(try reopened.repositories.games.fetchGame(id: first.gameID)?.isFavorite, true)
        XCTAssertEqual(try reopened.repositories.games.fetchGame(id: second.gameID)?.isFavorite, false)
    }

    func testLibraryAndGameStatisticsRefreshAndSortingPreservesFilters() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try AppContainer(rootURL: root)
        let first = try importROM(into: container, root: root, title: "Alpha")
        let second = try importROM(into: container, root: root, title: "Beta", byte: 1)
        let details = detailModel(container, gameID: second.gameID)
        details.reload()
        XCTAssertFalse(try XCTUnwrap(details.statistics).hasBeenPlayed)
        let library = LibraryViewModel(
            gameRepository: container.repositories.games, buildRepository: container.repositories.builds,
            profiles: container.repositories.saveProfiles,
            launchResolver: container.preferredLaunchResolver, buildOperations: container.buildOperations,
            deletion: container.libraryDeletion
        )
        library.reload()
        XCTAssertEqual(library.visibleGames.map(\.id), [first.gameID, second.gameID])
        try container.repositories.builds.addPlaytime(buildID: second.id, seconds: 125)
        var profile = try XCTUnwrap(details.saveProfiles.first)
        profile.totalPlaytimeSeconds = 125
        profile.sessionCount = 2
        profile.lastPlayedAt = Date()
        try container.repositories.saveProfiles.updateSaveProfile(profile)
        library.sort = .playtime
        library.reload()
        details.reload()
        XCTAssertEqual(library.visibleGames.map(\.id), [second.gameID, first.gameID])
        XCTAssertEqual(library.statistics[second.gameID], details.statistics)
        XCTAssertEqual(details.statistics?.totalPlaytimeSeconds, 125)
        XCTAssertEqual(details.statistics?.sessionCount, 2)
        XCTAssertEqual(details.statistics?.lastPlayedAt, profile.lastPlayedAt)
        XCTAssertEqual(details.saveProfiles.first?.totalPlaytimeSeconds, 125)
        library.searchText = "Alpha"
        XCTAssertEqual(library.visibleGames.map(\.id), [first.gameID])
        library.searchText = ""
        library.toggleFavorite(try XCTUnwrap(details.game))
        library.favoritesOnly = true
        XCTAssertEqual(library.visibleGames.map(\.id), [second.gameID])
        XCTAssertFalse(PlayStatisticsDisplay.played(profile.lastPlayedAt).isEmpty)
        XCTAssertEqual(PlayStatisticsDisplay.played(nil), "Never Played")
        XCTAssertEqual(PlayStatisticsDisplay.played(nil, hasBeenPlayed: true), "Last Played Unknown")
        XCTAssertEqual(PlayStatisticsDisplay.lastPlayed(nil), "Unknown")
    }

    private func importROM(into container: AppContainer, root: URL, title: String, byte: UInt8 = 0) throws -> Build {
        let file = root.appendingPathComponent("\(title).gb")
        var data = Data(repeating: 0, count: 0x8000)
        data[0x200] = byte
        try data.write(to: file)
        let coordinator = ImportCoordinator(analyzer: container.importAnalyzer, committer: container.importCommitter, assetStore: container.fileStore)
        let review = ImportReviewViewModel(analysis: try coordinator.analyzeROM(at: file), games: [], coordinator: coordinator)
        return try review.commit().build
    }

    private func detailModel(_ container: AppContainer, gameID: UUID) -> GameDetailViewModel {
        GameDetailViewModel(
            gameID: gameID, games: container.repositories.games, builds: container.repositories.builds,
            profiles: container.repositories.saveProfiles, buildOperations: container.buildOperations,
            createBlank: container.createBlankSaveProfile, duplicateProfile: container.duplicateSaveProfile,
            badges: container.setSaveProfileBadge, deletion: container.libraryDeletion,
            importSave: container.importBatterySave, patchCreator: container.patchCreator,
            evictImage: container.evictGeneratedImage, artwork: container.gameArtwork,
            variableMaps: container.attachVariableMap, replaceSave: container.replaceBatterySave,
            exporter: container.exportFiles, exportsDirectory: container.exportsDirectory
        )
    }
}

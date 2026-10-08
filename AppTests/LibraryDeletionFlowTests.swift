import EmulatorApplication
import EmulatorDomain
import Foundation
import Importing
import XCTest
@testable import PressAny

@MainActor
final class LibraryDeletionFlowTests: XCTestCase {
    func testADeletedGameWaitsInRecentlyDeletedAcrossLaunchesAndComesBack() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try AppContainer(rootURL: root)
        let build = try importROM(into: container, root: root)
        _ = try container.createBlankSaveProfile.execute(gameID: build.gameID, name: "Main")
        let model = detailModel(container, gameID: build.gameID)
        model.reload()

        model.requestGameDeletion()
        let plan = try XCTUnwrap(model.pendingDeletion)
        XCTAssertEqual(
            model.deletionMessage(for: plan),
            "1 Build and 1 Save Profile go with it. Recently Deleted in Settings keeps everything for 30 days."
        )
        model.confirm(plan)
        XCTAssertTrue(model.gameRemoved)
        XCTAssertTrue(try container.repositories.games.fetchGames().isEmpty)

        // The next launch purges only what is past its 30 days.
        let relaunched = try AppContainer(rootURL: root)
        let waiting = try relaunched.libraryDeletion.recentlyDeleted()
        XCTAssertEqual(waiting.map(\.title), [plan.title])

        try relaunched.libraryDeletion.restore(deletionID: try XCTUnwrap(waiting.first).id)
        XCTAssertEqual(try relaunched.repositories.builds.fetchBuild(id: build.id)?.id, build.id)
        XCTAssertEqual(try relaunched.repositories.saveProfiles.fetchSaveProfiles(gameID: build.gameID).count, 1)
    }

    func testABlankProfileGoesAloneAndSaysWhereItWaits() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try AppContainer(rootURL: root)
        let build = try importROM(into: container, root: root)
        let profile = try container.createBlankSaveProfile.execute(gameID: build.gameID, name: "Main")
        let model = detailModel(container, gameID: build.gameID)
        model.reload()

        model.requestDeletion(of: profile)
        let plan = try XCTUnwrap(model.pendingDeletion)
        XCTAssertEqual(model.deletionMessage(for: plan), "Recently Deleted in Settings keeps it for 30 days.")
        model.confirm(plan)
        XCTAssertTrue(model.saveProfiles.isEmpty)
        XCTAssertFalse(model.gameRemoved)
    }

    func testLibrarySelectionUsesVisibleGamesAndDoneClearsIt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try AppContainer(rootURL: root)
        let first = try importROM(into: container, root: root)
        let second = try importROM(into: container, root: root, marker: 1)
        try container.buildOperations.renameGame(gameID: first.gameID, title: "Alpha")
        try container.buildOperations.renameGame(gameID: second.gameID, title: "Beta")
        let model = LibraryViewModel(
            gameRepository: container.repositories.games, buildRepository: container.repositories.builds,
            launchResolver: container.preferredLaunchResolver, buildOperations: container.buildOperations,
            deletion: container.libraryDeletion
        )
        model.reload()
        model.selection.toggleMode()
        model.selection.toggleAll(Set(model.visibleGames.map(\.id)))
        XCTAssertEqual(model.selection.ids, [first.gameID, second.gameID])
        model.selection.toggleAll(Set(model.visibleGames.map(\.id)))
        XCTAssertTrue(model.selection.ids.isEmpty)
        model.selection.toggle(first.gameID)
        model.selection.toggle(second.gameID)
        model.searchText = "Beta"
        XCTAssertEqual(model.selection.ids, [second.gameID])
        model.requestSelectedDeletion()
        let batch = try XCTUnwrap(model.pendingBatchDeletion)
        XCTAssertEqual(batch.items.map { $0.target.id }, [second.gameID])
        model.selection.toggleMode()
        XCTAssertTrue(model.selection.ids.isEmpty)
        XCTAssertEqual(try container.repositories.games.fetchGames().count, 2)
        model.selection.toggleMode()
        model.selection.toggle(second.gameID)
        model.confirm(batch)
        XCTAssertFalse(model.selection.isSelecting, "empty filtered list exits selection")
        XCTAssertEqual(try container.repositories.games.fetchGames().map(\.id), [first.gameID])
    }

    func testGameSelectionSpansBothSectionsAndDropsMissingRowsOnReload() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try AppContainer(rootURL: root)
        let build = try importROM(into: container, root: root)
        let profile = try container.createBlankSaveProfile.execute(gameID: build.gameID, name: "Main")
        let model = detailModel(container, gameID: build.gameID)
        model.reload()
        let buildTarget = LibraryDeletionTarget(kind: .build, id: build.id)
        let profileTarget = LibraryDeletionTarget(kind: .saveProfile, id: profile.id)
        model.selection.toggleMode()
        model.selection.toggle(buildTarget)
        model.selection.toggle(profileTarget)
        model.requestSelectedDeletion()
        XCTAssertEqual(Set(try XCTUnwrap(model.pendingBatchDeletion).items.map(\.target)), [buildTarget, profileTarget])
        XCTAssertNotNil(try container.repositories.games.fetchGame(id: build.gameID))
        model.selection.toggleMode()
        XCTAssertTrue(model.selection.ids.isEmpty)
        model.selection.toggleMode()
        model.selection.toggle(buildTarget)
        model.selection.toggle(profileTarget)
        try container.libraryDeletion.delete(container.libraryDeletion.planProfileDeletion(profileID: profile.id))
        model.reload()
        XCTAssertEqual(model.selection.ids, [buildTarget])
        model.requestSelectedDeletion()
        model.confirm(try XCTUnwrap(model.pendingBatchDeletion))
        XCTAssertTrue(model.gameRemoved)
        XCTAssertFalse(model.selection.isSelecting)
        XCTAssertTrue(model.selection.ids.isEmpty)
    }

    func testSelectionToggleAndEmptyReconciliation() {
        let first = UUID(), second = UUID()
        var selection = ItemSelection<UUID>()
        selection.toggle(first)
        XCTAssertTrue(selection.ids.isEmpty)
        selection.toggleMode()
        selection.toggle(first)
        selection.toggle(second)
        selection.toggle(first)
        XCTAssertEqual(selection.ids, [second])
        selection.reconcile(with: [first])
        XCTAssertTrue(selection.isSelecting)
        XCTAssertTrue(selection.ids.isEmpty)
        selection.reconcile(with: [])
        XCTAssertFalse(selection.isSelecting)
    }

    private func importROM(into container: AppContainer, root: URL, marker: UInt8 = 0) throws -> Build {
        let file = root.appendingPathComponent("Example.gb")
        // A generated header is enough for import; no core execution is needed.
        var bytes = Data(repeating: 0, count: 0x8000)
        bytes[0] = marker
        try bytes.write(to: file)
        let coordinator = ImportCoordinator(analyzer: container.importAnalyzer, committer: container.importCommitter, assetStore: container.fileStore)
        let review = ImportReviewViewModel(analysis: try coordinator.analyzeROM(at: file), games: [], coordinator: coordinator)
        return try review.commit().build
    }

    private func detailModel(_ container: AppContainer, gameID: UUID) -> GameDetailViewModel {
        GameDetailViewModel(
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
        )
    }
}

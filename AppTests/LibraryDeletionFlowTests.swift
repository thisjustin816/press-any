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

    private func importROM(into container: AppContainer, root: URL) throws -> Build {
        let file = root.appendingPathComponent("Example.gb")
        // A generated header is enough for import; no core execution is needed.
        try Data(repeating: 0, count: 0x8000).write(to: file)
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
            replaceSave: container.replaceBatterySave
        )
    }
}

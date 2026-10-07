import EmulationSession
import EmulatorApplication
import EmulatorDomain
import Foundation
import Importing
import SwiftUI
import UIKit
import XCTest
@testable import PressAny

@MainActor
final class SessionRestorationTests: XCTestCase {
    func testCrashOffersRecoveryWithoutStartingACoreAndStartNormallyKeepsCheckpoint() throws {
        let fixture = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let checkpoint = try insertState(.crashRecovery, in: fixture.container, context: fixture.context)
        try fixture.container.launchHistory.started(fixture.context)

        let reopened = try AppContainer(rootURL: fixture.root)
        XCTAssertEqual(try reopened.launchRestoration(), .recover(fixture.context, checkpoint))
        XCTAssertNil(reopened.activeSession)
        let recovery = reopened.prepareRecovery(context: fixture.context, checkpoint: checkpoint)
        XCTAssertEqual(recovery.autoState, checkpoint)
        XCTAssertEqual(recovery.session.state, .idle)
        try reopened.startNormallyAfterCrash()
        XCTAssertEqual(try reopened.launchRestoration(), .library)
        XCTAssertNotNil(try reopened.repositories.saveStates.fetchSaveState(id: checkpoint.id))
        XCTAssertEqual(try AppContainer(rootURL: fixture.root).launchRestoration(), .library)
    }

    func testSavedBackgroundSessionReopensThroughResumeGamesPolicy() throws {
        let fixture = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let state = try insertState(.auto, in: fixture.container, context: fixture.context)
        for policy in [AutoResumePolicy.always, .ask, .never] {
            try fixture.container.repositories.settings.set(policy, key: SettingKey.autoResumePolicy.rawValue, scope: .app)
            try fixture.container.launchHistory.backgroundSaved(fixture.context)
            let reopened = try AppContainer(rootURL: fixture.root)
            XCTAssertEqual(try reopened.launchRestoration(), .reopen(fixture.context))
            let launch = reopened.prepareLaunch(context: fixture.context)
            XCTAssertEqual(launch.policy, policy)
            XCTAssertEqual(launch.autoState, policy == .never ? nil : state)
            XCTAssertEqual(try AppContainer(rootURL: fixture.root).launchRestoration(), .library)
        }
        try fixture.container.launchHistory.closed()
        XCTAssertEqual(try AppContainer(rootURL: fixture.root).launchRestoration(), .library)
    }

    func testRootShowsRecoveryChoicesWithoutOpeningTheGame() throws {
        let fixture = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        _ = try insertState(.crashRecovery, in: fixture.container, context: fixture.context)
        try fixture.container.launchHistory.started(fixture.context)
        let (window, host) = try showRoot(fixture.container)
        defer { window.isHidden = true }
        let alert = try waitForAlert(on: host)
        XCTAssertEqual(alert.title, "Recover Session?")
        XCTAssertEqual(alert.actions.compactMap(\.title), ["Recover Session", "Start Normally"])
        XCTAssertNil(fixture.container.activeSession)
    }

    func testRootReopensSavedBackgroundSessionWithResumeGamesAsk() throws {
        let fixture = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        _ = try insertState(.auto, in: fixture.container, context: fixture.context)
        try fixture.container.repositories.settings.set(AutoResumePolicy.ask, key: SettingKey.autoResumePolicy.rawValue, scope: .app)
        try fixture.container.launchHistory.backgroundSaved(fixture.context)
        let (window, host) = try showRoot(fixture.container)
        defer { window.isHidden = true }
        let alert = try waitForAlert(on: host)
        XCTAssertEqual(alert.title, "Resume where you left off?")
        XCTAssertEqual(alert.actions.compactMap(\.title), ["Resume", "Start Over"])
        XCTAssertNil(fixture.container.activeSession)
        XCTAssertNil(try fixture.container.launchHistory.context())
    }

    private func showRoot(_ container: AppContainer) throws -> (UIWindow, UIViewController) {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: RootView(bootstrap: AppBootstrap(container: container)))
        window.rootViewController = host
        window.makeKeyAndVisible()
        return (window, host)
    }

    private func waitForAlert(on host: UIViewController) throws -> UIAlertController {
        let deadline = Date().addingTimeInterval(3)
        while host.presentedViewController == nil, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        return try XCTUnwrap(host.presentedViewController as? UIAlertController)
    }

    func testDeletedBuildDoesNotReopen() throws {
        let fixture = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try fixture.container.launchHistory.backgroundSaved(fixture.context)
        try fixture.container.libraryDeletion.delete(fixture.container.libraryDeletion.planBuildDeletion(buildID: fixture.context.buildID))
        XCTAssertEqual(try AppContainer(rootURL: fixture.root).launchRestoration(), .library)
    }

    func testProfileStateListHidesCheckpoint() throws {
        let fixture = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        _ = try insertState(.crashRecovery, in: fixture.container, context: fixture.context)
        let manual = try insertState(.manual, in: fixture.container, context: fixture.context)
        let container = fixture.container
        let model = SaveStatesViewModel(
            profile: try XCTUnwrap(container.repositories.saveProfiles.fetchSaveProfile(id: fixture.context.saveProfileID)),
            repository: container.repositories.saveStates, builds: container.repositories.builds,
            assets: container.repositories.assets, fileStore: container.fileStore, deletion: container.libraryDeletion
        )
        XCTAssertEqual(model.states, [manual])
    }

    private func makeLibrary() throws -> (root: URL, container: AppContainer, context: LaunchContext) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let container = try AppContainer(rootURL: root)
        let file = root.appendingPathComponent("Example.gb")
        try Data(repeating: 0, count: 0x8000).write(to: file)
        let coordinator = ImportCoordinator(analyzer: container.importAnalyzer, committer: container.importCommitter, assetStore: container.fileStore)
        let review = ImportReviewViewModel(analysis: try coordinator.analyzeROM(at: file), games: [], coordinator: coordinator)
        let build = try review.commit().build
        let profile = try container.createBlankSaveProfile.execute(gameID: build.gameID, name: "Main")
        return (root, container, LaunchContext(gameID: build.gameID, buildID: build.id, saveProfileID: profile.id))
    }

    private func insertState(_ kind: SaveStateKind, in container: AppContainer, context: LaunchContext) throws -> SaveState {
        let id = UUID()
        let payload = Data([1, 2, 3])
        let url = container.fileStore.stateURL(stateID: id)
        try container.fileStore.writeDataAtomically(payload, to: url)
        let asset = ManagedAsset(
            id: UUID(), kind: .saveState, storageClass: .userData,
            contentSHA256: container.fileStore.hashData(payload), byteLength: Int64(payload.count),
            relativePath: try container.fileStore.managedRelativePath(for: url), integrityStatus: .verified, createdAt: Date()
        )
        try container.repositories.assets.insertAsset(asset)
        let state = SaveState(
            id: id, buildID: context.buildID, saveProfileID: context.saveProfileID,
            core: .init(identifier: "sameboy", version: "1.0.3"), stateSerializationVersion: "test",
            stateAssetID: asset.id, kind: kind, autoSequence: kind == .auto ? 1 : nil,
            playtimeSeconds: 60, createdAt: Date(timeIntervalSince1970: ceil(Date().timeIntervalSince1970) + 1)
        )
        try container.repositories.saveStates.insertSaveState(state)
        return state
    }
}

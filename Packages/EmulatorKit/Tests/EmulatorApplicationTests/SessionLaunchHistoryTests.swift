import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import XCTest

final class SessionLaunchHistoryTests: XCTestCase {
    private let context = LaunchContext(gameID: UUID(), buildID: UUID(), saveProfileID: UUID())

    func testCleanCloseReturnsToLibrary() throws {
        let history = SessionLaunchHistory(store: InMemorySettingsStore())
        try history.started(context)
        try history.closed()
        XCTAssertEqual(try history.launchAction(checkpoint: nil), .library)
    }

    func testBackgroundAfterAutoStateReopensOnce() throws {
        let store = InMemorySettingsStore()
        try SessionLaunchHistory(store: store).started(context)
        try SessionLaunchHistory(store: store).backgroundSaved(context)
        let reopened = SessionLaunchHistory(store: store)
        XCTAssertEqual(try reopened.launchAction(checkpoint: nil), .reopen(context))
        XCTAssertEqual(try reopened.launchAction(checkpoint: nil), .library)
    }

    func testEndedWhilePlayingOffersRecoveryAndNeverReopensAutomatically() throws {
        let store = InMemorySettingsStore()
        let history = SessionLaunchHistory(store: store)
        try history.started(context)
        let state = checkpoint()
        for _ in 0..<2 {
            XCTAssertEqual(try SessionLaunchHistory(store: store).launchAction(checkpoint: state), .recover(context, state))
        }
        try history.started(context)
        XCTAssertEqual(try history.launchAction(checkpoint: state), .recover(context, state))
        try history.closed()
        XCTAssertEqual(try history.launchAction(checkpoint: state), .library)
    }

    func testOpenSessionWithoutItsOwnCheckpointDoesNotReopen() throws {
        let history = SessionLaunchHistory(store: InMemorySettingsStore())
        try history.started(context)
        XCTAssertEqual(try history.launchAction(checkpoint: nil), .library)
        let other = checkpoint(buildID: UUID())
        XCTAssertEqual(try history.launchAction(checkpoint: other), .library)
    }

    private func checkpoint(buildID: UUID? = nil) -> SaveState {
        SaveState(
            id: UUID(), buildID: buildID ?? context.buildID, saveProfileID: context.saveProfileID,
            core: .init(identifier: "fake", version: "1"), stateSerializationVersion: "1",
            stateAssetID: UUID(), kind: .crashRecovery, playtimeSeconds: 60, createdAt: Date()
        )
    }
}

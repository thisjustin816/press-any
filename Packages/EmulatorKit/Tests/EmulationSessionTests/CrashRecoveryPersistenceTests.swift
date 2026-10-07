import AssetStorage
import EmulationSession
import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import PersistenceGRDB
import XCTest

final class CrashRecoveryPersistenceTests: XCTestCase {
    func testReplacingCheckpointSurvivesReopeningAndRollbackKeepsThePreviousState() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ManagedFileStore(rootURL: root)
        let databaseURL = root.appendingPathComponent("Library.sqlite")
        let database = try AppDatabase(url: databaseURL)
        try database.migrate()
        let repositories = database.makeRepositories()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let game = Game(id: UUID(), primaryTitle: "Recovery", systemFamily: "gameboy", createdAt: date, modifiedAt: date)
        let rom = ManagedAsset(
            id: UUID(), kind: .sourceImage, storageClass: .source, contentSHA256: String(repeating: "a", count: 64),
            byteLength: 0, relativePath: "SourceROMs/test.gb", integrityStatus: .verified, createdAt: date
        )
        let build = Build(
            id: UUID(), gameID: game.id, system: .gameBoy, displayName: "Test", imageAssetID: rom.id,
            imageSHA256: rom.contentSHA256, sourceKind: .importedImage, isBase: true, createdAt: date, modifiedAt: date
        )
        let profile = SaveProfile(id: UUID(), gameID: game.id, displayName: "Main", createdAt: date, modifiedAt: date)
        try repositories.games.insertGame(game)
        try repositories.assets.insertAsset(rom)
        try repositories.builds.insertBuild(build)
        try repositories.saveProfiles.insertSaveProfile(profile)
        let context = LaunchContext(gameID: game.id, buildID: build.id, saveProfileID: profile.id)
        let worker = SessionWorker(core: FakeEmulatorCore())
        func service(transactions: any LibraryTransactionRunner) -> SaveStateService {
            SaveStateService(states: repositories.saveStates, assets: repositories.assets, assetStore: store, transactions: transactions, now: { date })
        }
        let first = try service(transactions: repositories.transactions).save(
            worker: worker, context: context, kind: .crashRecovery, playtimeSeconds: 60
        )
        XCTAssertThrowsError(try service(transactions: FailAfterOperation(inner: repositories.transactions)).save(
            worker: worker, context: context, kind: .crashRecovery, playtimeSeconds: 120
        ))
        XCTAssertEqual(try repositories.saveStates.fetchSaveStates(buildID: build.id, saveProfileID: profile.id), [first])
        let firstAsset = try XCTUnwrap(repositories.assets.fetchAsset(id: first.stateAssetID))
        XCTAssertTrue(store.fileExists(at: try store.managedURL(relativePath: firstAsset.relativePath)))
        try service(transactions: repositories.transactions).load(first, worker: worker, context: context)

        let second = try service(transactions: repositories.transactions).save(
            worker: worker, context: context, kind: .crashRecovery, playtimeSeconds: 180
        )
        let reopened = try AppDatabase(url: databaseURL).makeRepositories()
        XCTAssertEqual(try reopened.saveStates.fetchSaveStates(buildID: build.id, saveProfileID: profile.id), [second])
        XCTAssertNil(try reopened.assets.fetchAsset(id: first.stateAssetID))
        XCTAssertFalse(store.fileExists(at: try store.managedURL(relativePath: firstAsset.relativePath)))

        let history = SessionLaunchHistory(store: repositories.settings)
        try history.started(context)
        XCTAssertEqual(try SessionLaunchHistory(store: reopened.settings).launchAction(checkpoint: second), .recover(context, second))
        try history.backgroundSaved(context)
        XCTAssertEqual(try SessionLaunchHistory(store: reopened.settings).launchAction(checkpoint: nil), .reopen(context))
        XCTAssertEqual(try history.launchAction(checkpoint: second), .library)
    }
}

private struct FailAfterOperation: LibraryTransactionRunner {
    struct Failure: Error {}
    let inner: any LibraryTransactionRunner

    func run<T: Sendable>(_ operation: @Sendable () throws -> T) throws -> T {
        try inner.run { () throws -> T in
            _ = try operation()
            throw Failure()
        }
    }
}

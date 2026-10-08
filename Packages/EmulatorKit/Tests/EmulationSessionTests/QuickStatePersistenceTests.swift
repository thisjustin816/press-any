import AssetStorage
import EmulationCore
import EmulationSession
import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import PersistenceGRDB
import XCTest

final class QuickStatePersistenceTests: XCTestCase {
    func testFailedReplacementLeavesThePreviousQuickStateLoadable() throws {
        let fixture = try QuickStateFixture()
        defer { fixture.removeFiles() }
        let worker = SessionWorker(core: FakeEmulatorCore())
        try worker.perform { try $0.loadPersistentSave(Data([1])) }
        let firstFrame = EmulatorVideoFrame(width: 1, height: 1, bgra8888: Data([1, 1, 1, 255]), emulatedNanoseconds: 0)
        let first = try fixture.save(worker: worker, time: 10, frame: firstFrame)
        let assetsBefore = try fixture.repositories.assets.fetchAssets()
        try worker.perform { try $0.loadPersistentSave(Data([2])) }
        let failing = SaveStateService(states: fixture.repositories.saveStates, assets: fixture.repositories.assets,
            assetStore: fixture.store, transactions: QuickReplacementRollback(inner: fixture.repositories.transactions),
            thumbnails: QuickStateThumbnailEncoder())

        XCTAssertThrowsError(try failing.save(worker: worker, context: fixture.context, kind: .quick,
            playtimeSeconds: 20, frame: firstFrame))

        XCTAssertEqual(try fixture.repositories.saveStates.fetchSaveState(id: first.id), first)
        XCTAssertEqual(Set(try fixture.repositories.assets.fetchAssets().map(\.id)), Set(assetsBefore.map(\.id)))
        XCTAssertEqual(fixture.service(time: 30).thumbnailData(for: first), firstFrame.bgra8888)
        try fixture.service(time: 30).load(first, worker: worker, context: fixture.context)
        XCTAssertEqual(try worker.perform { try $0.persistentSaveData() }, Data([1]))
    }

    func testQuickSaveReplacesInPlaceAndQuickLoadRestoresNewerData() throws {
        let fixture = try QuickStateFixture()
        defer { fixture.removeFiles() }
        let worker = SessionWorker(core: FakeEmulatorCore())
        try worker.perform { try $0.loadPersistentSave(Data([1])) }
        let firstFrame = EmulatorVideoFrame(width: 1, height: 1, bgra8888: Data([1, 1, 1, 255]), emulatedNanoseconds: 0)
        let first = try fixture.save(worker: worker, time: 10, frame: firstFrame)
        let oldAsset = try XCTUnwrap(fixture.repositories.assets.fetchAsset(id: first.stateAssetID))
        let oldThumbnail = try XCTUnwrap(fixture.repositories.assets.fetchAsset(id: try XCTUnwrap(first.screenshotAssetID)))
        try fixture.repositories.saveStates.renameSaveState(id: first.id, label: "Before the boss")
        try worker.perform { try $0.loadPersistentSave(Data([2, 3])) }

        let secondFrame = EmulatorVideoFrame(width: 1, height: 1, bgra8888: Data([2, 2, 2, 255]), emulatedNanoseconds: 0)
        let second = try fixture.save(worker: worker, time: 20, frame: secondFrame)

        XCTAssertEqual(second.id, first.id)
        XCTAssertEqual(second.label, "Before the boss")
        XCTAssertGreaterThan(second.createdAt, first.createdAt)
        let reopened = try AppDatabase(url: fixture.databaseURL).makeRepositories()
        XCTAssertEqual(try reopened.saveStates.fetchSaveStates(buildID: fixture.context.buildID, saveProfileID: fixture.context.saveProfileID), [second])
        XCTAssertNil(try reopened.assets.fetchAsset(id: first.stateAssetID))
        XCTAssertFalse(fixture.store.fileExists(at: try fixture.store.managedURL(relativePath: oldAsset.relativePath)))
        XCTAssertNil(try reopened.assets.fetchAsset(id: oldThumbnail.id))
        XCTAssertFalse(fixture.store.fileExists(at: try fixture.store.managedURL(relativePath: oldThumbnail.relativePath)))
        XCTAssertEqual(fixture.service(time: 30).thumbnailData(for: second), secondFrame.bgra8888)
        try worker.perform { try $0.loadPersistentSave(Data([9])) }
        try fixture.service(time: 30).load(second, worker: worker, context: fixture.context)
        XCTAssertEqual(try worker.perform { try $0.persistentSaveData() }, Data([2, 3]))
    }

    func testQuickStatesAreScopedByBuildAndSaveProfile() throws {
        let fixture = try QuickStateFixture()
        defer { fixture.removeFiles() }
        let worker = SessionWorker(core: FakeEmulatorCore())
        let build = try XCTUnwrap(fixture.repositories.builds.fetchBuild(id: fixture.context.buildID))
        let otherBuild = Build(id: UUID(), gameID: build.gameID, system: build.system, displayName: "Other",
            imageAssetID: build.imageAssetID, imageSHA256: String(repeating: "b", count: 64),
            sourceKind: .importedImage, createdAt: fixture.date, modifiedAt: fixture.date)
        let otherProfile = SaveProfile(id: UUID(), gameID: build.gameID, displayName: "Other",
            createdAt: fixture.date, modifiedAt: fixture.date)
        try fixture.repositories.builds.insertBuild(otherBuild)
        try fixture.repositories.saveProfiles.insertSaveProfile(otherProfile)
        let contexts = [fixture.context,
            LaunchContext(gameID: build.gameID, buildID: otherBuild.id, saveProfileID: fixture.context.saveProfileID),
            LaunchContext(gameID: build.gameID, buildID: build.id, saveProfileID: otherProfile.id)]
        for context in contexts {
            _ = try fixture.save(worker: worker, context: context, time: 10)
            _ = try fixture.save(worker: worker, context: context, time: 20)
        }
        for context in contexts {
            let states = try fixture.repositories.saveStates.fetchSaveStates(buildID: context.buildID, saveProfileID: context.saveProfileID)
            XCTAssertEqual(states.count, 1)
            XCTAssertEqual(states.first?.kind, .quick)
        }
        let quick = try XCTUnwrap(fixture.repositories.saveStates.fetchSaveStates(buildID: build.id, saveProfileID: fixture.context.saveProfileID).first)
        for context in contexts.dropFirst() {
            XCTAssertThrowsError(try fixture.service(time: 30).load(quick, worker: worker, context: context)) {
                XCTAssertEqual($0 as? SaveStateServiceError, .contextMismatch)
            }
        }
        let deletion = LibraryDeletion(id: UUID(), kind: .saveState, title: quick.displayName,
            gameID: build.gameID, deletedAt: fixture.date, records: LibraryRecordSet(saveStateIDs: [quick.id]))
        try fixture.repositories.deletions.insertDeletion(deletion)
        try fixture.repositories.deletions.restoreDeletion(id: deletion.id)
        XCTAssertEqual(try fixture.repositories.saveStates.fetchSaveState(id: quick.id), quick)
    }

    func testRestoringDeletedQuickStateKeepsNewerQuickAndBothPayloads() throws {
        try assertRestore(hasNewerQuick: true)
    }

    func testRestoringDeletedQuickStateWithoutReplacementKeepsItQuick() throws {
        try assertRestore(hasNewerQuick: false)
    }

    private func assertRestore(hasNewerQuick: Bool) throws {
        let fixture = try QuickStateFixture()
        defer { fixture.removeFiles() }
        let worker = SessionWorker(core: FakeEmulatorCore())
        try worker.perform { try $0.loadPersistentSave(Data([1])) }
        let first = try fixture.save(worker: worker, time: 10)
        try fixture.repositories.saveStates.renameSaveState(id: first.id, label: "Old quick")
        let deletion = LibraryDeletion(id: UUID(), kind: .saveState, title: "Old quick",
            gameID: fixture.context.gameID, deletedAt: fixture.date,
            records: LibraryRecordSet(saveStateIDs: [first.id]))
        try fixture.repositories.deletions.insertDeletion(deletion)
        XCTAssertTrue(try fixture.repositories.saveStates.fetchSaveStates(buildID: fixture.context.buildID, saveProfileID: fixture.context.saveProfileID).isEmpty)
        var newer: SaveState?
        if hasNewerQuick {
            try worker.perform { try $0.loadPersistentSave(Data([2])) }
            newer = try fixture.save(worker: worker, time: 20)
        }
        try fixture.repositories.deletions.restoreDeletion(id: deletion.id)
        let restored = try XCTUnwrap(fixture.repositories.saveStates.fetchSaveState(id: first.id))
        XCTAssertEqual(restored.kind, hasNewerQuick ? .manual : .quick)
        XCTAssertEqual(restored.label, "Old quick")
        XCTAssertEqual(restored.createdAt, first.createdAt)
        let states = try fixture.repositories.saveStates.fetchSaveStates(buildID: fixture.context.buildID, saveProfileID: fixture.context.saveProfileID)
        XCTAssertEqual(states.count, hasNewerQuick ? 2 : 1)
        XCTAssertEqual(states.filter { $0.kind == .quick }.count, 1)
        try fixture.service(time: 30).load(restored, worker: worker, context: fixture.context)
        XCTAssertEqual(try worker.perform { try $0.persistentSaveData() }, Data([1]))
        if let newer {
            XCTAssertEqual(try fixture.repositories.saveStates.fetchSaveState(id: newer.id), newer)
            try fixture.service(time: 30).load(newer, worker: worker, context: fixture.context)
            XCTAssertEqual(try worker.perform { try $0.persistentSaveData() }, Data([2]))
        }
    }
}

private struct QuickReplacementRollback: LibraryTransactionRunner {
    struct Failure: Error {}
    let inner: any LibraryTransactionRunner

    func run<T: Sendable>(_ operation: @Sendable () throws -> T) throws -> T {
        try inner.run { () throws -> T in
            _ = try operation()
            throw Failure()
        }
    }
}

private struct QuickStateFixture {
    let root: URL
    let databaseURL: URL
    let store: ManagedFileStore
    let repositories: GRDBRepositorySet
    let context: LaunchContext
    let date = Date(timeIntervalSince1970: 1_700_000_000)

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = try ManagedFileStore(rootURL: root)
        databaseURL = root.appendingPathComponent("Library.sqlite")
        let database = try AppDatabase(url: databaseURL)
        try database.migrate()
        repositories = database.makeRepositories()
        let game = Game(id: UUID(), primaryTitle: "Quick", systemFamily: "gameboy", createdAt: date, modifiedAt: date)
        let rom = ManagedAsset(id: UUID(), kind: .sourceImage, storageClass: .source,
            contentSHA256: String(repeating: "a", count: 64), byteLength: 0,
            relativePath: "SourceROMs/test.gb", integrityStatus: .verified, createdAt: date)
        let build = Build(id: UUID(), gameID: game.id, system: .gameBoy, displayName: "Test",
            imageAssetID: rom.id, imageSHA256: rom.contentSHA256, sourceKind: .importedImage,
            isBase: true, createdAt: date, modifiedAt: date)
        let profile = SaveProfile(id: UUID(), gameID: game.id, displayName: "Main", createdAt: date, modifiedAt: date)
        try repositories.games.insertGame(game)
        try repositories.assets.insertAsset(rom)
        try repositories.builds.insertBuild(build)
        try repositories.saveProfiles.insertSaveProfile(profile)
        context = LaunchContext(gameID: game.id, buildID: build.id, saveProfileID: profile.id)
    }

    func service(time: Double) -> SaveStateService {
        let timestamp = date.addingTimeInterval(time)
        return SaveStateService(states: repositories.saveStates, assets: repositories.assets, assetStore: store,
            transactions: repositories.transactions, thumbnails: QuickStateThumbnailEncoder(), now: { timestamp })
    }

    func save(worker: SessionWorker, context: LaunchContext? = nil, time: Double, frame: EmulatorVideoFrame? = nil) throws -> SaveState {
        try service(time: time).save(worker: worker, context: context ?? self.context, kind: .quick, playtimeSeconds: time, frame: frame)
    }

    func removeFiles() { try? FileManager.default.removeItem(at: root) }
}

private struct QuickStateThumbnailEncoder: FrameImageEncoding {
    let fileExtension = "png"
    func encode(_ frame: EmulatorVideoFrame) throws -> Data { frame.bgra8888 }
}

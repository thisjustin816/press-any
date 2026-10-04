import AssetStorage
import EmulationCore
import EmulatorKitTestSupport
import EmulatorApplication
import EmulatorDomain
import Foundation
import XCTest
@testable import EmulationSession

final class EmulationSessionTests: XCTestCase {
    func testBackgroundFlushesBatteryAndWritesAutoState() throws {
        let harness = try SessionHarness.make(seedBattery: Data([1, 2, 3, 4]))
        let session = harness.makeSession()

        try session.start(context: harness.contextA)
        _ = try session.stepFrame(input: .init(a: true))
        try session.background()

        XCTAssertEqual(session.state, .paused(harness.contextA))
        let profile = try XCTUnwrap(harness.profiles.fetchSaveProfile(id: harness.profile.id))
        XCTAssertNotNil(profile.persistentSaveAssetID)
        let battery = try harness.loadPersistentSave(profile: profile)
        XCTAssertEqual(battery, Data([1, 2, 3, 4]))

        let autos = try harness.states.fetchSaveStates(
            buildID: harness.buildA.id,
            saveProfileID: harness.profile.id
        ).filter { $0.kind == .auto }
        XCTAssertEqual(autos.count, 1)
        XCTAssertEqual(autos.first?.buildID, harness.buildA.id)
        XCTAssertEqual(autos.first?.saveProfileID, harness.profile.id)
    }

    func testAutoStateRetentionKeepsFiveNewest() throws {
        let harness = try SessionHarness.make()
        let session = harness.makeSession()
        try session.start(context: harness.contextA)

        for _ in 0..<7 {
            _ = try session.stepFrame()
            try session.background()
            try session.resume()
        }

        let autos = try harness.states.fetchSaveStates(
            buildID: harness.buildA.id,
            saveProfileID: harness.profile.id
        ).filter { $0.kind == .auto }
        XCTAssertEqual(autos.count, 5)
        XCTAssertEqual(Set(autos.compactMap(\.autoSequence)), Set([3, 4, 5, 6, 7]))
    }

    func testSaveStateCannotLoadIntoDifferentBuildContext() throws {
        let harness = try SessionHarness.make()
        let sessionA = harness.makeSession()
        try sessionA.start(context: harness.contextA)
        let state = try sessionA.saveManualState(label: "A")
        try sessionA.stop()

        let sessionB = harness.makeSession()
        try sessionB.start(context: harness.contextB)

        XCTAssertThrowsError(try sessionB.loadState(state)) { error in
            XCTAssertEqual(error as? SaveStateServiceError, .contextMismatch)
        }
    }

    func testPlaytimeAccumulatesFrameDurationsNotCumulativeTimestamps() throws {
        let harness = try SessionHarness.make()
        let session = harness.makeSession()
        try session.start(context: harness.contextA)

        _ = try session.stepFrame()
        _ = try session.stepFrame()

        XCTAssertEqual(session.playtimeSeconds, 0.033485412, accuracy: 0.000000001)
    }

    func testSaveStatesAreSeparatedByBuildEvenWhenBatteryProfileIsShared() throws {
        let harness = try SessionHarness.make()
        let session = harness.makeSession()
        try session.start(context: harness.contextA)
        _ = try session.saveManualState(label: "Build A")

        let statesForOtherBuild = try harness.states.fetchSaveStates(
            buildID: harness.buildB.id,
            saveProfileID: harness.profile.id
        )
        XCTAssertTrue(statesForOtherBuild.isEmpty)
    }

    func testFirstLaunchPinsCoreAndSubsequentLaunchUsesPin() throws {
        let harness = try SessionHarness.make()
        let session = harness.makeSession()
        try session.start(context: harness.contextA)
        try session.stop()

        let pinned = try XCTUnwrap(harness.builds.fetchBuild(id: harness.buildA.id)?.corePin)
        XCTAssertEqual(pinned.descriptor, CoreDescriptor(identifier: "sameboy", version: "1.0.3"))
    }

    func testForegroundAlwaysResumesButAskStaysPaused() throws {
        let harness = try SessionHarness.make()
        let session = harness.makeSession()
        try session.start(context: harness.contextA)
        try session.pause()

        XCTAssertFalse(try session.foreground(policy: .ask))
        XCTAssertEqual(session.state, .paused(harness.contextA))
        XCTAssertTrue(try session.foreground(policy: .always))
        XCTAssertEqual(session.state, .running(harness.contextA))
    }
}

extension EmulationSessionTests {
    func testBootLogoShowsUnlessTheResolvedSettingSkipsIt() throws {
        let harness = try SessionHarness.make()
        let settings = InMemorySettingsStore()
        let key = SettingKey.skipBootAnimation.rawValue

        func skipsOnStart(_ context: LaunchContext) throws -> Int {
            let session = harness.makeSession(settings: SettingsResolver(store: settings))
            try session.start(context: context)
            try session.stop(createAutoState: false)
            return try XCTUnwrap(harness.factory.cores.last).bootAnimationSkips
        }

        XCTAssertEqual(try skipsOnStart(harness.contextA), 0, "unset shows the logo")

        try settings.set(true, key: key, scope: .app)
        XCTAssertEqual(try skipsOnStart(harness.contextA), 1, "the app-wide setting skips it")

        try settings.set(false, key: key, scope: .build(harness.buildB.id))
        XCTAssertEqual(try skipsOnStart(harness.contextB), 0, "a Build override wins")

        try settings.setValueJSON("not json", key: key, scope: .app)
        XCTAssertEqual(try skipsOnStart(harness.contextA), 0, "an unreadable value shows the logo")
    }
}

extension EmulationSessionTests {
    func testLaunchRestoresTheNewestAutoState() throws {
        let harness = try SessionHarness.make(seedBattery: Data([7]))
        let first = harness.makeSession()
        try first.start(context: harness.contextA)
        for _ in 0..<3 { _ = try first.stepFrame() }
        try first.stop(createAutoState: true)

        let second = harness.makeSession()
        let autoState = try XCTUnwrap(second.resumableAutoState(for: harness.contextA))
        XCTAssertEqual(try second.start(context: harness.contextA, resumeFrom: autoState), .restored(autoState))

        let frame = try second.stepFrame()
        XCTAssertEqual(frame.bgra8888[0], 4, "emulation continues from the restored frame")
        XCTAssertEqual(try XCTUnwrap(harness.factory.cores.last).bootAnimationSkips, 0)
    }

    func testFailedRestoreBootsNormallyAndKeepsTheState() throws {
        let harness = try SessionHarness.make()
        let first = harness.makeSession()
        try first.start(context: harness.contextA)
        _ = try first.stepFrame()
        let autoState = try first.saveAutoState()
        try first.stop()

        let asset = try XCTUnwrap(harness.assets.fetchAsset(id: autoState.stateAssetID))
        try harness.store.writeDataAtomically(
            Data("corrupt".utf8),
            to: harness.store.managedURL(relativePath: asset.relativePath)
        )

        let second = harness.makeSession()
        XCTAssertEqual(try second.start(context: harness.contextA, resumeFrom: autoState), .failed(autoState))
        XCTAssertEqual(second.state, .running(harness.contextA))
        XCTAssertEqual(try second.stepFrame().bgra8888[0], 1, "the game booted from the start")
        XCTAssertEqual(try second.saveStates().map(\.id), [autoState.id], "the rejected state is kept")
    }

    func testTheProfileRemembersWhichBuildLastWroteItsSave() throws {
        let harness = try SessionHarness.make(seedBattery: Data([1, 2]))

        let sessionA = harness.makeSession()
        try sessionA.start(context: harness.contextA)
        try sessionA.stop()
        XCTAssertEqual(try harness.profiles.fetchSaveProfile(id: harness.profile.id)?.saveWrittenByBuildID, harness.buildA.id)

        let sessionB = harness.makeSession()
        try sessionB.start(context: harness.contextB)
        try sessionB.stop()
        XCTAssertEqual(try harness.profiles.fetchSaveProfile(id: harness.profile.id)?.saveWrittenByBuildID, harness.buildB.id)
    }

    func testAutoStateIsNotOfferedOnceASharedProfileSaveIsNewer() throws {
        let harness = try SessionHarness.make(seedBattery: Data([1, 2]))
        let early = Date(timeIntervalSince1970: 1_700_000_000)
        let later = early.addingTimeInterval(60)

        let sessionA = harness.makeSession(now: early)
        try sessionA.start(context: harness.contextA)
        try sessionA.stop(createAutoState: true)
        XCTAssertNotNil(try sessionA.resumableAutoState(for: harness.contextA))

        let sessionB = harness.makeSession(now: later)
        try sessionB.start(context: harness.contextB)
        try sessionB.stop()

        XCTAssertNil(
            try sessionA.resumableAutoState(for: harness.contextA),
            "restoring Build A's state would roll back the save Build B wrote"
        )
    }

    func testAutoResumePolicyDefaultsToAlwaysAndInherits() throws {
        let harness = try SessionHarness.make()
        let settings = InMemorySettingsStore()
        let session = harness.makeSession(settings: SettingsResolver(store: settings))
        let key = SettingKey.autoResumePolicy.rawValue

        XCTAssertEqual(session.autoResumePolicy(for: harness.contextA), .always)

        try settings.set(AutoResumePolicy.ask, key: key, scope: .app)
        XCTAssertEqual(session.autoResumePolicy(for: harness.contextA), .ask)

        try settings.set(AutoResumePolicy.never, key: key, scope: .build(harness.buildB.id))
        XCTAssertEqual(session.autoResumePolicy(for: harness.contextB), .never)
        XCTAssertEqual(session.autoResumePolicy(for: harness.contextA), .ask)

        try settings.setValueJSON("not json", key: key, scope: .app)
        XCTAssertEqual(session.autoResumePolicy(for: harness.contextA), .always)
    }
}

extension EmulationSessionTests {
    func testAFailedPruneKeepsTheAutoStateJustSaved() throws {
        let store = try ManagedFileStore(rootURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("emulatorkit-prune-tests-\(UUID().uuidString)", isDirectory: true))
        let assets = InMemoryAssetRepository()
        let states = UndeletableSaveStateRepository()
        let service = SaveStateService(states: states, assets: assets, assetStore: store, retention: .init(keepCount: 1))
        let core = FakeEmulatorCore()
        try core.loadImage(Data(count: 0x8000), system: .gameBoy)
        let worker = SessionWorker(core: core)
        let context = LaunchContext(gameID: UUID(), buildID: UUID(), saveProfileID: UUID())

        _ = try service.save(worker: worker, context: context, kind: .auto, playtimeSeconds: 0)
        let second = try service.save(worker: worker, context: context, kind: .auto, playtimeSeconds: 1)

        let asset = try XCTUnwrap(assets.fetchAsset(id: second.stateAssetID))
        XCTAssertTrue(store.fileExists(at: try store.managedURL(relativePath: asset.relativePath)))
        XCTAssertTrue(try states.fetchSaveStates(buildID: context.buildID, saveProfileID: context.saveProfileID)
            .contains { $0.id == second.id })
    }
}

extension EmulationSessionTests {
    func testPlaytimeAndSessionCountAreRecordedWithoutTouchingModifiedAt() throws {
        let harness = try SessionHarness.make()
        let frame = 0.016742706
        let session = harness.makeSession(now: Date(timeIntervalSince1970: 1_700_000_500))
        try session.start(context: harness.contextA)
        _ = try session.stepFrame()
        _ = try session.stepFrame()
        try session.background()

        var profile = try XCTUnwrap(harness.profiles.fetchSaveProfile(id: harness.profile.id))
        XCTAssertEqual(profile.totalPlaytimeSeconds, 2 * frame, accuracy: 1e-9)
        XCTAssertEqual(profile.sessionCount, 1)
        XCTAssertEqual(profile.lastPlayedAt, Date(timeIntervalSince1970: 1_700_000_500))
        XCTAssertEqual(profile.modifiedAt, harness.profile.modifiedAt)

        try session.resume()
        _ = try session.stepFrame()
        try session.stop()
        profile = try XCTUnwrap(harness.profiles.fetchSaveProfile(id: harness.profile.id))
        XCTAssertEqual(profile.totalPlaytimeSeconds, 3 * frame, accuracy: 1e-9, "time isn't counted twice")
        XCTAssertEqual(profile.sessionCount, 1, "one session, however many times it backgrounds")

        let next = harness.makeSession()
        try next.start(context: harness.contextA)
        _ = try next.stepFrame()
        XCTAssertEqual(next.playtimeSeconds, 4 * frame, accuracy: 1e-9)
    }
}

/// Fails every delete, so pruning old Auto States fails.
private final class UndeletableSaveStateRepository: SaveStateRepository, @unchecked Sendable {
    private let inner = InMemorySaveStateRepository()
    struct Refused: Error {}

    func insertSaveState(_ state: SaveState) throws { try inner.insertSaveState(state) }
    func fetchSaveStates(buildID: UUID, saveProfileID: UUID) throws -> [SaveState] {
        try inner.fetchSaveStates(buildID: buildID, saveProfileID: saveProfileID)
    }
    func deleteSaveState(id: UUID) throws { throw Refused() }
}

private struct SessionHarness {
    let game: Game
    let buildA: Build
    let buildB: Build
    let profile: SaveProfile
    let contextA: LaunchContext
    let contextB: LaunchContext
    let builds: InMemoryBuildRepository
    let profiles: InMemorySaveProfileRepository
    let states: InMemorySaveStateRepository
    let assets: InMemoryAssetRepository
    let store: ManagedFileStore
    let factory: CapturingCoreFactory

    static func make(seedBattery: Data? = nil) throws -> SessionHarness {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let game = Game(
            id: UUID(),
            primaryTitle: "Test",
            systemFamily: "gameboy",
            createdAt: now,
            modifiedAt: now
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("emulatorkit-session-tests-\(UUID().uuidString)", isDirectory: true)
        let store = try ManagedFileStore(rootURL: root)
        let assets = InMemoryAssetRepository()

        func makeROMAsset(bytes: UInt8) throws -> ManagedAsset {
            let source = root.appendingPathComponent("source-\(UUID().uuidString).gb")
            try Data(repeating: bytes, count: 0x8000).write(to: source)
            let staged = try store.stageCopy(from: source, transactionID: UUID())
            let hash = try store.hashFile(at: staged)
            let destination = try store.commitSourceROM(stagedURL: staged, sha256: hash)
            let asset = ManagedAsset(
                id: UUID(),
                kind: .sourceImage,
                storageClass: .source,
                contentSHA256: hash,
                byteLength: 0x8000,
                relativePath: try store.managedRelativePath(for: destination),
                originalFilename: source.lastPathComponent,
                integrityStatus: .verified,
                createdAt: now
            )
            try assets.insertAsset(asset)
            return asset
        }

        let romA = try makeROMAsset(bytes: 0)
        let romB = try makeROMAsset(bytes: 1)
        let buildA = Build(
            id: UUID(),
            gameID: game.id,
            system: .gameBoyColor,
            displayName: "A",
            imageAssetID: romA.id,
            imageSHA256: romA.contentSHA256,
            sourceKind: .importedImage,
            isBase: true,
            createdAt: now,
            modifiedAt: now
        )
        let buildB = Build(
            id: UUID(),
            gameID: game.id,
            system: .gameBoyColor,
            displayName: "B",
            imageAssetID: romB.id,
            imageSHA256: romB.contentSHA256,
            sourceKind: .importedImage,
            isBase: false,
            createdAt: now,
            modifiedAt: now
        )
        var profile = SaveProfile(
            id: UUID(),
            gameID: game.id,
            displayName: "Main",
            createdAt: now,
            modifiedAt: now
        )

        if let seedBattery {
            let destination = store.persistentSaveURL(profileID: profile.id)
            try store.writeDataAtomically(seedBattery, to: destination)
            let asset = ManagedAsset(
                id: UUID(),
                kind: .persistentSave,
                storageClass: .userData,
                contentSHA256: try store.hashFile(at: destination),
                byteLength: Int64(seedBattery.count),
                relativePath: try store.managedRelativePath(for: destination),
                integrityStatus: .verified,
                createdAt: now
            )
            try assets.insertAsset(asset)
            profile.persistentSaveAssetID = asset.id
        }

        let builds = InMemoryBuildRepository([buildA, buildB])
        let profiles = InMemorySaveProfileRepository([profile])
        let states = InMemorySaveStateRepository()
        let factory = CapturingCoreFactory()

        return SessionHarness(
            game: game,
            buildA: buildA,
            buildB: buildB,
            profile: profile,
            contextA: LaunchContext(gameID: game.id, buildID: buildA.id, saveProfileID: profile.id),
            contextB: LaunchContext(gameID: game.id, buildID: buildB.id, saveProfileID: profile.id),
            builds: builds,
            profiles: profiles,
            states: states,
            assets: assets,
            store: store,
            factory: factory
        )
    }

    func makeSession(
        settings: SettingsResolver? = nil,
        now: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> EmulationSession {
        EmulationSession(
            builds: builds,
            profiles: profiles,
            states: states,
            assets: assets,
            assetStore: store,
            imageResolver: TestBuildROMResolver(builds: builds, assets: assets, store: store),
            coreRegistry: CoreRegistry(factories: [factory]),
            settings: settings,
            now: { now }
        )
    }

    func loadPersistentSave(profile: SaveProfile) throws -> Data? {
        guard let assetID = profile.persistentSaveAssetID,
              let asset = try assets.fetchAsset(id: assetID) else { return nil }
        return try store.readData(at: store.managedURL(relativePath: asset.relativePath))
    }
}

private final class CapturingCoreFactory: EmulatorCoreFactory, @unchecked Sendable {
    let descriptor = CoreDescriptor(identifier: "sameboy", version: "1.0.3")
    let supportedSystems: Set<GameSystem> = [.gameBoy, .gameBoyColor]
    private(set) var cores: [FakeEmulatorCore] = []

    func makeCore() throws -> any EmulatorCore {
        let core = FakeEmulatorCore(descriptor: descriptor)
        cores.append(core)
        return core
    }
}

private struct TestBuildROMResolver: BuildImageResolving {
    let builds: InMemoryBuildRepository
    let assets: InMemoryAssetRepository
    let store: ManagedFileStore

    func resolveImageURL(buildID: UUID) throws -> URL {
        guard let build = try builds.fetchBuild(id: buildID) else {
            throw EmulationSessionError.buildNotFound(buildID)
        }
        guard let asset = try assets.fetchAsset(id: build.imageAssetID) else {
            throw EmulationSessionError.romAssetNotFound(build.imageAssetID)
        }
        return try store.managedURL(relativePath: asset.relativePath)
    }
}

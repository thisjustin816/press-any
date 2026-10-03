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

    func makeSession(settings: SettingsResolver? = nil) -> EmulationSession {
        EmulationSession(
            builds: builds,
            profiles: profiles,
            states: states,
            assets: assets,
            assetStore: store,
            imageResolver: TestBuildROMResolver(builds: builds, assets: assets, store: store),
            coreRegistry: CoreRegistry(factories: [factory]),
            settings: settings,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
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

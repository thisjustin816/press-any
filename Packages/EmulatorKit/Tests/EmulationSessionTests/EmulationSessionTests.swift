import AssetStorage
import EmulationCore
import EmulatorKitTestSupport
import EmulatorApplication
import EmulatorDomain
import Foundation
import XCTest
@testable import EmulationSession

final class EmulationSessionTests: XCTestCase {
    func testIntactPersistentSaveLoadsWithItsRecordedHash() throws {
        let harness = try SessionHarness.make(seedBattery: Data([1, 2, 3]))
        let service = PersistentSaveService(profiles: harness.profiles, assets: harness.assets, assetStore: harness.store)

        XCTAssertEqual(try service.loadPersistentSave(for: harness.profile), Data([1, 2, 3]))
        let asset = try XCTUnwrap(harness.assets.fetchAsset(id: try XCTUnwrap(harness.profile.persistentSaveAssetID)))
        XCTAssertEqual(asset.integrityStatus, .verified)
    }

    func testDamagedPersistentSaveIsRejectedMarkedAndKept() throws {
        try assertDamagedPersistentSaveIsRejected(markingFails: false)
    }

    func testDamagedPersistentSaveIsRejectedEvenWhenMarkingFails() throws {
        try assertDamagedPersistentSaveIsRejected(markingFails: true)
    }

    private func assertDamagedPersistentSaveIsRejected(markingFails: Bool) throws {
        let harness = try SessionHarness.make(seedBattery: Data([1, 2, 3]))
        let asset = try XCTUnwrap(harness.assets.fetchAsset(id: try XCTUnwrap(harness.profile.persistentSaveAssetID)))
        let url = try harness.store.managedURL(relativePath: asset.relativePath)
        let damaged = Data([9, 8, 7])
        try harness.store.writeDataAtomically(damaged, to: url)
        let assets: any ManagedAssetRepository = markingFails
            ? RefusingAssetUpdateRepository(inner: harness.assets) : harness.assets
        let service = PersistentSaveService(profiles: harness.profiles, assets: assets, assetStore: harness.store)
        var loaded: Data?

        XCTAssertThrowsError(loaded = try service.loadPersistentSave(for: harness.profile)) { error in
            XCTAssertEqual(error as? PersistentSaveServiceError, .hashMismatch(
                assetID: asset.id, expected: asset.contentSHA256, actual: harness.store.hashData(damaged)
            ))
            XCTAssertEqual(error.localizedDescription, "This Save Profile's save file is damaged, so the game didn't start. The file was kept.")
        }

        XCTAssertNil(loaded)
        XCTAssertEqual(try harness.store.readData(at: url), damaged)
        var expectedAsset = asset
        if !markingFails { expectedAsset.integrityStatus = .corrupt }
        XCTAssertEqual(try harness.assets.fetchAsset(id: asset.id), expectedAsset)
        XCTAssertEqual(try harness.profiles.fetchSaveProfile(id: harness.profile.id), harness.profile)
    }

    func testDamagedPersistentSaveStopsLaunchBeforeCreatingACore() throws {
        let harness = try SessionHarness.make(seedBattery: Data([1, 2, 3]))
        let asset = try XCTUnwrap(harness.assets.fetchAsset(id: try XCTUnwrap(harness.profile.persistentSaveAssetID)))
        let url = try harness.store.managedURL(relativePath: asset.relativePath)
        let damaged = Data([9, 8, 7])
        try harness.store.writeDataAtomically(damaged, to: url)
        let session = harness.makeSession()

        XCTAssertThrowsError(try session.start(context: harness.contextA)) { error in
            XCTAssertEqual(error as? PersistentSaveServiceError, .hashMismatch(
                assetID: asset.id, expected: asset.contentSHA256, actual: harness.store.hashData(damaged)
            ))
        }
        XCTAssertEqual(session.state, .idle)
        XCTAssertTrue(harness.factory.cores.isEmpty)
        try session.stop()
        XCTAssertEqual(try harness.store.readData(at: url), damaged)
        XCTAssertEqual(try harness.assets.fetchAsset(id: asset.id)?.integrityStatus, .corrupt)
    }

    func testIntactStateLoadsWithItsRecordedHash() throws {
        let harness = try SessionHarness.make()
        let service = SaveStateService(states: harness.states, assets: harness.assets, assetStore: harness.store)
        let worker = SessionWorker(core: FakeEmulatorCore())
        try worker.perform { try $0.loadPersistentSave(Data([1, 2, 3])) }
        let state = try service.save(worker: worker, context: harness.contextA, kind: .manual, playtimeSeconds: 0)
        try worker.perform { try $0.loadPersistentSave(Data([9])) }

        try service.load(state, worker: worker, context: harness.contextA)

        XCTAssertEqual(try worker.perform { try $0.persistentSaveData() }, Data([1, 2, 3]))
        XCTAssertEqual(try harness.assets.fetchAsset(id: state.stateAssetID)?.integrityStatus, .verified)
    }

    func testDamagedStateIsRejectedBeforeDeserializationMarkedAndKept() throws {
        try assertDamagedStateIsRejected(markingFails: false)
    }

    func testDamagedStateIsRejectedBeforeDeserializationEvenWhenMarkingFails() throws {
        try assertDamagedStateIsRejected(markingFails: true)
    }

    private func assertDamagedStateIsRejected(markingFails: Bool) throws {
        let harness = try SessionHarness.make()
        let writer = SaveStateService(states: harness.states, assets: harness.assets, assetStore: harness.store)
        let worker = SessionWorker(core: FakeEmulatorCore())
        try worker.perform { try $0.loadPersistentSave(Data([1, 2, 3])) }
        let state = try writer.save(worker: worker, context: harness.contextA, kind: .manual, playtimeSeconds: 0)
        let asset = try XCTUnwrap(harness.assets.fetchAsset(id: state.stateAssetID))
        let url = try harness.store.managedURL(relativePath: asset.relativePath)
        let damaged = try worker.perform { core in
            try core.loadPersistentSave(Data([9]))
            return try core.serializeState()
        }
        try harness.store.writeDataAtomically(damaged, to: url)
        try worker.perform { core in
            try core.loadPersistentSave(Data([2]))
            (core as! FakeEmulatorCore).failsNextStateLoadPartway = true
        }
        let assets: any ManagedAssetRepository = markingFails
            ? RefusingAssetUpdateRepository(inner: harness.assets) : harness.assets
        let service = SaveStateService(states: harness.states, assets: assets, assetStore: harness.store)

        XCTAssertThrowsError(try service.load(state, worker: worker, context: harness.contextA)) { error in
            XCTAssertEqual(error as? SaveStateServiceError, .hashMismatch(
                assetID: asset.id, expected: asset.contentSHA256, actual: harness.store.hashData(damaged)
            ))
            XCTAssertEqual(error.localizedDescription, "This save state is damaged, so it wasn't loaded. The file was kept.")
        }

        XCTAssertTrue(try worker.perform { ($0 as! FakeEmulatorCore).failsNextStateLoadPartway }, "deserializeState was never called")
        XCTAssertEqual(try worker.perform { try $0.persistentSaveData() }, Data([2]))
        XCTAssertEqual(try harness.store.readData(at: url), damaged)
        var expectedAsset = asset
        if !markingFails { expectedAsset.integrityStatus = .corrupt }
        XCTAssertEqual(try harness.assets.fetchAsset(id: asset.id), expectedAsset)
        XCTAssertEqual(try harness.states.fetchSaveStates(buildID: state.buildID, saveProfileID: state.saveProfileID), [state])
    }

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

    func testAStateKeepsAThumbnailOfTheFrameItWasSavedOn() throws {
        let harness = try SessionHarness.make()
        let session = harness.makeSession(thumbnails: FrameSizeEncoder())
        try session.start(context: harness.contextA)
        let frame = try session.stepFrame()

        let state = try session.saveManualState()

        XCTAssertEqual(session.thumbnailData(for: state), FrameSizeEncoder.bytes(of: frame))
        let asset = try XCTUnwrap(harness.assets.fetchAsset(id: try XCTUnwrap(state.screenshotAssetID)))
        XCTAssertEqual(asset.kind, .stateThumbnail)
    }

    func testAStateSavedBeforeAnyFrameOrWithoutAnEncoderHasNoThumbnail() throws {
        let harness = try SessionHarness.make()
        let withEncoder = harness.makeSession(thumbnails: FrameSizeEncoder())
        try withEncoder.start(context: harness.contextA)
        XCTAssertNil(try withEncoder.saveManualState().screenshotAssetID)
        try withEncoder.stop()

        let without = harness.makeSession()
        try without.start(context: harness.contextA)
        _ = try without.stepFrame()
        XCTAssertNil(try without.saveManualState().screenshotAssetID)
    }

    func testPruningAutoStatesRemovesTheirThumbnails() throws {
        let harness = try SessionHarness.make()
        let session = harness.makeSession(thumbnails: FrameSizeEncoder())
        try session.start(context: harness.contextA)
        for _ in 0..<7 {
            _ = try session.stepFrame()
            try session.background()
            try session.resume()
        }

        let kept = try harness.states.fetchSaveStates(buildID: harness.buildA.id, saveProfileID: harness.profile.id)
        let thumbnails = try harness.assets.fetchAssets().filter { $0.kind == .stateThumbnail }
        XCTAssertEqual(Set(thumbnails.map(\.id)), Set(kept.compactMap(\.screenshotAssetID)))
        XCTAssertEqual(thumbnails.count, 5)
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
        XCTAssertEqual(try harness.assets.fetchAsset(id: asset.id)?.integrityStatus, .corrupt)
        XCTAssertEqual(try harness.store.readData(at: harness.store.managedURL(relativePath: asset.relativePath)), Data("corrupt".utf8))
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

    func testImportingASaveIntoAProfileKeepsItsOldSaveAsACopy() throws {
        let harness = try SessionHarness.make(seedBattery: Data([1, 2, 3]))
        var profile = try XCTUnwrap(harness.profiles.fetchSaveProfile(id: harness.profile.id))
        profile.saveWrittenByBuildID = harness.buildA.id
        try harness.profiles.updateSaveProfile(profile)
        let file = try harness.writeExternalFile(Data([9, 9]))

        let result = try harness.replaceSave().execute(profileID: profile.id, sourceURL: file)

        XCTAssertEqual(try harness.batteryData(of: result.profile), Data([9, 9]))
        XCTAssertNil(result.profile.saveWrittenByBuildID, "an imported file's writer isn't known")
        let copy = try XCTUnwrap(result.safetyCopy)
        XCTAssertEqual(copy.displayName, "Main before import")
        XCTAssertEqual(try harness.batteryData(of: copy), Data([1, 2, 3]))
    }

    func testImportingASaveIntoABlankProfileMakesNoCopy() throws {
        let harness = try SessionHarness.make()
        let result = try harness.replaceSave().execute(
            profileID: harness.profile.id,
            sourceURL: try harness.writeExternalFile(Data([7]))
        )
        XCTAssertNil(result.safetyCopy)
        XCTAssertEqual(try harness.batteryData(of: result.profile), Data([7]))
        XCTAssertEqual(try harness.profiles.fetchSaveProfiles(gameID: harness.game.id).count, 1)
    }

    func testAnEmptyFileReplacesNothing() throws {
        let harness = try SessionHarness.make(seedBattery: Data([1, 2, 3]))
        XCTAssertThrowsError(try harness.replaceSave().execute(
            profileID: harness.profile.id,
            sourceURL: try harness.writeExternalFile(Data())
        )) { XCTAssertEqual($0 as? ReplaceBatterySaveError, .emptyFile) }
        XCTAssertEqual(try harness.profiles.fetchSaveProfiles(gameID: harness.game.id).count, 1)
        XCTAssertEqual(try harness.batteryData(of: harness.profile), Data([1, 2, 3]))
    }

    func testAnOversizedFileReplacesNothing() throws {
        let harness = try SessionHarness.make(seedBattery: Data([1, 2, 3]))
        let huge = try ImportTestFiles.sparse(
            at: FileManager.default.temporaryDirectory.appendingPathComponent("import-\(UUID().uuidString).sav"),
            byteCount: 5 * 1_048_576
        )
        XCTAssertThrowsError(try harness.replaceSave().execute(profileID: harness.profile.id, sourceURL: huge)) {
            XCTAssertEqual($0 as? ImportSizeError, .fileTooLarge(limit: ImportSizeLimit.batterySave.bytes))
        }
        XCTAssertEqual(try harness.profiles.fetchSaveProfiles(gameID: harness.game.id).count, 1)
        XCTAssertEqual(try harness.batteryData(of: harness.profile), Data([1, 2, 3]))
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

extension EmulationSessionTests {
    func testTheGameSaveIsWrittenDuringPlayAtMostEveryFiveSeconds() throws {
        let harness = try SessionHarness.make(seedBattery: Data([1, 2]))
        let session = harness.makeSession()
        try session.start(context: harness.contextA)
        try XCTUnwrap(harness.factory.cores.last).writeBattery(Data([3, 4]))

        for _ in 0..<298 {
            _ = try session.stepFrame()
            XCTAssertFalse(try session.flushBatteryIfChanged())
        }
        XCTAssertEqual(try harness.batteryData(of: harness.profile), Data([1, 2]), "under five seconds played")

        _ = try session.stepFrame()
        XCTAssertTrue(try session.flushBatteryIfChanged())
        XCTAssertEqual(try harness.batteryData(of: harness.profile), Data([3, 4]))

        for _ in 0..<300 { _ = try session.stepFrame() }
        XCTAssertFalse(try session.flushBatteryIfChanged(), "an unchanged save isn't written again")
    }

    func testAFailedBatteryWriteStillSavesTheAutoState() throws {
        let harness = try SessionHarness.make(seedBattery: Data([1, 2]))
        let session = harness.makeSession()
        try session.start(context: harness.contextA)
        _ = try session.stepFrame()
        try harness.breakSaveDirectory()

        XCTAssertThrowsError(try session.background()) { error in
            XCTAssertEqual((error as? SessionSaveError)?.failures.count, 1, "only the battery write failed")
        }
        let autos = try harness.states.fetchSaveStates(buildID: harness.buildA.id, saveProfileID: harness.profile.id)
        XCTAssertEqual(autos.map(\.kind), [.auto])
        XCTAssertNotNil(try session.resumableAutoState(for: harness.contextA), "the state is the way back to the unsaved game")
    }

    func testAFailedStopStaysOpenToRetryOrToCloseWithoutSaving() throws {
        let harness = try SessionHarness.make(seedBattery: Data([1, 2]))
        let session = harness.makeSession()
        try session.start(context: harness.contextA)
        try XCTUnwrap(harness.factory.cores.last).writeBattery(Data([5]))
        try harness.breakSaveDirectory()

        XCTAssertThrowsError(try session.stop(createAutoState: true))
        XCTAssertEqual(session.state, .paused(harness.contextA))
        try harness.repairSaveDirectory()
        try session.stop(createAutoState: true)
        XCTAssertEqual(session.state, .stopped)
        XCTAssertEqual(try harness.batteryData(of: harness.profile), Data([5]))

        let second = harness.makeSession()
        try second.start(context: harness.contextA)
        try XCTUnwrap(harness.factory.cores.last).writeBattery(Data([6]))
        try harness.breakSaveDirectory()
        XCTAssertThrowsError(try second.stop(createAutoState: true))
        let statesBefore = try harness.states.fetchSaveStates(buildID: harness.buildA.id, saveProfileID: harness.profile.id)

        try second.stop(createAutoState: true, discardUnsaved: true)
        XCTAssertEqual(second.state, .stopped)
        XCTAssertEqual(
            try harness.states.fetchSaveStates(buildID: harness.buildA.id, saveProfileID: harness.profile.id),
            statesBefore,
            "closing without saving writes nothing"
        )
    }

    func testLoadingAnOlderStateWarnsAndKeepsTheNewerSaveAsACopy() throws {
        let harness = try SessionHarness.make(seedBattery: Data([1]))
        let first = harness.makeSession(now: Date(timeIntervalSince1970: 1_700_000_000))
        try first.start(context: harness.contextA)
        let old = try first.saveManualState(label: "old")
        try first.stop()
        _ = try ReplaceBatterySave(
            profiles: harness.profiles,
            assets: harness.assets,
            assetStore: harness.store,
            now: { Date(timeIntervalSince1970: 1_700_000_100) }
        ).execute(profileID: harness.profile.id, sourceURL: harness.writeExternalFile(Data([9])))

        let second = harness.makeSession(now: Date(timeIntervalSince1970: 1_700_000_200))
        try second.start(context: harness.contextA)
        XCTAssertTrue(try second.loadingWouldRollBackSave(old))
        XCTAssertFalse(try second.loadingWouldRollBackSave(second.saveManualState(label: "new")))

        let copy = try second.loadStateKeepingCopy(old)
        try second.stop()

        XCTAssertEqual(copy.displayName, "Main before loading state")
        XCTAssertEqual(try harness.batteryData(of: copy), Data([9]))
        XCTAssertEqual(try harness.batteryData(of: harness.profile), Data([1]), "the state's save, as chosen")
    }

    func testAnInGameSaveNotYetWrittenIsKeptInTheCopy() throws {
        let harness = try SessionHarness.make(seedBattery: Data([1]))
        let session = harness.makeSession()
        try session.start(context: harness.contextA)
        let state = try session.saveManualState(label: "before")
        let core = try XCTUnwrap(harness.factory.cores.last)
        core.writeBattery(Data([9]))

        XCTAssertTrue(try session.loadingWouldRollBackSave(state))
        let copy = try session.loadStateKeepingCopy(state)
        XCTAssertEqual(try harness.batteryData(of: copy), Data([9]), "the unwritten save is in the copy")
        XCTAssertEqual(try core.persistentSaveData(), Data([1]), "the state is loaded")
        try session.stop()
        XCTAssertEqual(try harness.batteryData(of: harness.profile), Data([1]))
        XCTAssertEqual(try harness.profiles.fetchSaveProfiles(gameID: harness.game.id).count, 2)
    }

    func testTakingAStateWritesTheGameSaveFirst() throws {
        let harness = try SessionHarness.make(seedBattery: Data([1]))
        let session = harness.makeSession()
        try session.start(context: harness.contextA)
        try XCTUnwrap(harness.factory.cores.last).writeBattery(Data([9]))

        let state = try session.saveManualState(label: "after saving")
        XCTAssertEqual(try harness.batteryData(of: harness.profile), Data([9]))
        XCTAssertFalse(try session.loadingWouldRollBackSave(state), "the state holds every save made so far")
    }

    func testLoadingWithNothingSavedSinceTheStateDoesNotWarn() throws {
        let harness = try SessionHarness.make(seedBattery: Data([1]))
        let session = harness.makeSession()
        try session.start(context: harness.contextA)
        let state = try session.saveManualState(label: "now")
        _ = try session.stepFrame()
        XCTAssertFalse(try session.loadingWouldRollBackSave(state))

        let noBattery = try SessionHarness.make()
        let other = noBattery.makeSession()
        try other.start(context: noBattery.contextA)
        let otherState = try other.saveManualState(label: "now")
        XCTAssertFalse(try other.loadingWouldRollBackSave(otherState), "a game without a save has nothing to lose")
    }

    func testASaveThatCantBeWrittenStopsTheLoad() throws {
        let harness = try SessionHarness.make(seedBattery: Data([1]))
        let session = harness.makeSession()
        try session.start(context: harness.contextA)
        let state = try session.saveManualState(label: "before")
        let core = try XCTUnwrap(harness.factory.cores.last)
        core.writeBattery(Data([9]))
        try harness.breakSaveDirectory()

        XCTAssertThrowsError(try session.loadStateKeepingCopy(state))
        XCTAssertEqual(try core.persistentSaveData(), Data([9]), "nothing was loaded")
        XCTAssertEqual(try harness.profiles.fetchSaveProfiles(gameID: harness.game.id).count, 1)
        try harness.repairSaveDirectory()
        let copy = try session.loadStateKeepingCopy(state)
        XCTAssertEqual(try harness.batteryData(of: copy), Data([9]), "trying again works once the save can be written")
    }

    func testAStateThatFailsPartwayPutsTheLatestSaveBack() throws {
        let harness = try SessionHarness.make(seedBattery: Data([1]))
        let session = harness.makeSession()
        try session.start(context: harness.contextA)
        let state = try session.saveManualState(label: "before")
        let core = try XCTUnwrap(harness.factory.cores.last)
        core.writeBattery(Data([9]))
        core.failsNextStateLoadPartway = true

        XCTAssertThrowsError(try session.loadStateKeepingCopy(state))
        XCTAssertEqual(try core.persistentSaveData(), Data([9]), "the game has its latest save again")
        XCTAssertEqual(
            try harness.profiles.fetchSaveProfiles(gameID: harness.game.id).count, 1,
            "with the save back in the game, the copy isn't needed"
        )
        try session.stop()
        XCTAssertEqual(try harness.batteryData(of: harness.profile), Data([9]))

        // The plain load, used when nothing is at risk, puts the written save back the same way.
        let second = harness.makeSession()
        try second.start(context: harness.contextA)
        let fresh = try second.saveManualState(label: "fresh")
        let secondCore = try XCTUnwrap(harness.factory.cores.last)
        secondCore.failsNextStateLoadPartway = true
        XCTAssertThrowsError(try second.loadState(fresh)) { error in
            guard case .stateLoadFailedPartway? = error as? FakeEmulatorCoreError else {
                return XCTFail("expected the core's own error, got \(error)")
            }
        }
        XCTAssertEqual(try secondCore.persistentSaveData(), Data([9]))
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
    func fetchSaveStates(saveProfileID: UUID) throws -> [SaveState] {
        try inner.fetchSaveStates(saveProfileID: saveProfileID)
    }
    func fetchSaveState(id: UUID) throws -> SaveState? { try inner.fetchSaveState(id: id) }
    func renameSaveState(id: UUID, label: String?) throws { try inner.renameSaveState(id: id, label: label) }
    func reassignSaveStates(buildID: UUID, fromSaveProfileID: UUID, toSaveProfileID: UUID) throws {
        try inner.reassignSaveStates(buildID: buildID, fromSaveProfileID: fromSaveProfileID, toSaveProfileID: toSaveProfileID)
    }
    func deleteSaveState(id: UUID) throws { throw Refused() }
}

private struct RefusingAssetUpdateRepository: ManagedAssetRepository {
    let inner: InMemoryAssetRepository
    struct Refused: Error {}

    func fetchAsset(id: UUID) throws -> ManagedAsset? { try inner.fetchAsset(id: id) }
    func fetchSourceAsset(kind: ManagedAssetKind, sha256: String) throws -> ManagedAsset? {
        try inner.fetchSourceAsset(kind: kind, sha256: sha256)
    }
    func fetchAsset(relativePath: String) throws -> ManagedAsset? { try inner.fetchAsset(relativePath: relativePath) }
    func insertAsset(_ asset: ManagedAsset) throws { try inner.insertAsset(asset) }
    func updateMutableAsset(_ asset: ManagedAsset) throws { throw Refused() }
    func deleteAsset(id: UUID) throws { try inner.deleteAsset(id: id) }
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

    /// Puts a file where the profile's save directory goes, so writing the battery save fails.
    func breakSaveDirectory() throws {
        let directory = store.persistentSaveURL(profileID: profile.id).deletingLastPathComponent()
        try? FileManager.default.removeItem(at: directory)
        try Data().write(to: directory)
    }

    func repairSaveDirectory() throws {
        try FileManager.default.removeItem(at: store.persistentSaveURL(profileID: profile.id).deletingLastPathComponent())
    }

    func replaceSave() -> ReplaceBatterySave {
        ReplaceBatterySave(profiles: profiles, assets: assets, assetStore: store)
    }

    func writeExternalFile(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("import-\(UUID().uuidString).sav")
        try data.write(to: url)
        return url
    }

    func batteryData(of profile: SaveProfile) throws -> Data? {
        let current = try XCTUnwrap(profiles.fetchSaveProfile(id: profile.id))
        guard let assetID = current.persistentSaveAssetID, let asset = try assets.fetchAsset(id: assetID) else { return nil }
        return try store.readData(at: store.managedURL(relativePath: asset.relativePath))
    }

    func makeSession(
        settings: SettingsResolver? = nil,
        thumbnails: (any FrameImageEncoding)? = nil,
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
            thumbnails: thumbnails,
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

/// Encodes a frame as its width and height, so a test can tell which frame it got.
private struct FrameSizeEncoder: FrameImageEncoding {
    let fileExtension = "png"

    static func bytes(of frame: EmulatorVideoFrame) -> Data {
        Data([UInt8(frame.width), UInt8(frame.height)])
    }

    func encode(_ frame: EmulatorVideoFrame) throws -> Data {
        Self.bytes(of: frame)
    }
}


// An in-game save made since the last write is newer than the state, so loading it warns.
extension EmulationSessionTests {
    func testReviewUnflushedBatteryChangeTriggersStateRollbackWarning() throws {
        let h = try SessionHarness.make(seedBattery: Data([1]))
        let session = h.makeSession(now: Date(timeIntervalSince1970: 1_700_000_001))
        try session.start(context: h.contextA)
        let state = try session.saveManualState(label: "Before new in-game save")
        let core = try XCTUnwrap(h.factory.cores.last)
        core.writeBattery(Data([9])) // An in-game save before the next periodic flush.
        XCTAssertEqual(try h.batteryData(of: h.profile), Data([1]))
        XCTAssertEqual(try core.persistentSaveData(), Data([9]))
        let warns = try session.loadingWouldRollBackSave(state)
        XCTAssertTrue(warns, "Newer live cartridge RAM needs protection, not just newer disk metadata")
        if !warns {
            // This is the exact unguarded path used by the gameplay view controller.
            try session.loadState(state)
            try session.flushBattery()
            XCTAssertEqual(try h.batteryData(of: h.profile), Data([1]),
                           "Demonstrates the newer [9] save has been overwritten")
            XCTAssertEqual(try h.profiles.fetchSaveProfiles(gameID: h.game.id).count, 1,
                           "No safety profile was created")
        }
    }
}

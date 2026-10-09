import AssetStorage
import EmulationCore
import EmulatorKitTestSupport
import EmulatorApplication
import EmulatorDomain
import Foundation
import Importing
import Testing
import XCTest
@testable import QuickPlay

final class QuickPlayTests: XCTestCase {
    func testRunningQuickPlayNeverWritesTimedStates() throws {
        let harness = try QuickPlayHarness.make(seedBattery: Data([1]))
        defer { try? FileManager.default.removeItem(at: harness.store.rootURL) }
        let session = try harness.workspace.start(romURL: harness.writeExternalROM(TestROM.make(title: "SMOKE")))
        let runtime = harness.makeRuntime(session)
        try runtime.start()
        try runtime.setSpeed(.unlimited)
        for _ in 0..<4_000 {
            _ = try runtime.stepFrame()
            _ = try runtime.flushBatteryIfChanged()
        }
        XCTAssertGreaterThan(runtime.playtimeSeconds, 60)
        XCTAssertFalse(FileManager.default.fileExists(atPath: session.autoStateURL.path))
        XCTAssertTrue(try harness.states.fetchSaveStates(saveProfileID: harness.profile.id).isEmpty)
    }

    func testPromotionPreservesThePickedFilenameAndItsMetadata() throws {
        let harness = try QuickPlayHarness.make()
        let rom = harness.external.appendingPathComponent("Example%20v1.10%20(Europe)%20(En,Fr).gb")
        let decodedFilename = "Example v1.10 (Europe) (En,Fr).gb"
        try TestROM.make(title: "EXAMPLE").write(to: rom)
        let session = try harness.workspace.start(romURL: rom)
        XCTAssertEqual(session.imageURL.lastPathComponent, "rom.bin")
        XCTAssertEqual(session.originalFilename, decodedFilename)
        let analysis = try harness.promoter.analyze(session, targetGameID: nil)
        XCTAssertEqual(analysis.originalFilename, decodedFilename)
        XCTAssertEqual(analysis.filenameMetadata.suggestedTitle, "Example")
        let result = try harness.promoter.promote(
            session: session,
            plan: ROMImportPlan(analysis: analysis, disposition: .createGame(title: "Example"), buildDisplayName: "1.10", markAsBase: true),
            saveDisposition: .keepExisting
        )
        XCTAssertEqual(result.importResult.build.region, "Europe")
        XCTAssertEqual(result.importResult.build.language, "En, Fr")
        XCTAssertEqual(result.importResult.build.versionString, "1.10")
        XCTAssertEqual(result.importResult.sourceAsset.originalFilename, decodedFilename)
    }

    func testQuickPlayWithExistingSaveNeverMutatesLibraryProfile() throws {
        let harness = try QuickPlayHarness.make(seedBattery: Data([1, 2, 3]))
        let originalHash = try harness.libraryBatteryHash()
        let rom = try harness.writeExternalROM(TestROM.make(title: "SMOKE", cgb: true))

        let session = try harness.workspace.start(
            romURL: rom,
            copiedSaveProfileID: harness.profile.id
        )
        XCTAssertEqual(try harness.workspace.temporaryBatteryData(sessionID: session.id), Data([1, 2, 3]))

        try harness.workspace.writeTemporaryBattery(Data([9, 9, 9]), sessionID: session.id)

        XCTAssertEqual(try harness.libraryBatteryHash(), originalHash)
        XCTAssertEqual(try harness.libraryBatteryData(), Data([1, 2, 3]))
        XCTAssertEqual(try harness.workspace.temporaryBatteryData(sessionID: session.id), Data([9, 9, 9]))
    }

    func testQuickPlayRefusesAFileLargerThanAnyCartridge() throws {
        let harness = try QuickPlayHarness.make()
        let huge = try ImportTestFiles.sparse(at: harness.external.appendingPathComponent("huge.gb"), byteCount: 9 * 1_048_576)

        XCTAssertThrowsError(try harness.workspace.start(romURL: huge)) {
            XCTAssertEqual($0 as? ImportSizeError, .fileTooLarge(limit: ImportSizeLimit.rom.bytes))
        }
        XCTAssertEqual(try harness.store.quickPlaySessionIDs(), [])
        XCTAssertEqual(ImportTestFiles.stagedItems(under: harness.store.rootURL), [])
    }

    func testExpiredQuickPlaySessionIsRemovedButUnknownDirectoryIsPreserved() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let harness = try QuickPlayHarness.make(now: start, retentionSeconds: 60)
        let rom = try harness.writeExternalROM(TestROM.make(title: "TEMP", cgb: false))
        let session = try harness.workspace.start(romURL: rom)

        let unknown = harness.store.rootURL
            .appendingPathComponent("Temporary/QuickPlay/not-a-session", isDirectory: true)
        try FileManager.default.createDirectory(at: unknown, withIntermediateDirectories: true)

        let retention = QuickPlayRetention(
            assetStore: harness.store,
            now: { Date(timeIntervalSince1970: 1_061) }
        )
        XCTAssertEqual(try retention.removeExpiredSessions(), [session.id])
        XCTAssertFalse(harness.store.fileExists(at: session.rootURL))
        XCTAssertTrue(harness.store.fileExists(at: unknown))
    }

    func testPromotionCanReplaceExistingSaveOnlyAfterExplicitDisposition() throws {
        let harness = try QuickPlayHarness.make(seedBattery: Data([1, 2, 3]))
        let rom = try harness.writeExternalROM(TestROM.make(title: "NEXT", cgb: true, payloadByte: 4))
        let session = try harness.workspace.start(
            romURL: rom,
            copiedSaveProfileID: harness.profile.id
        )
        try harness.workspace.writeTemporaryBattery(Data([7, 7, 7]), sessionID: session.id)

        let analysis = try harness.promoter.analyze(session, targetGameID: harness.game.id)
        let plan = ROMImportPlan(
            analysis: analysis,
            disposition: .addBuild(gameID: harness.game.id),
            buildDisplayName: "Smoke Build",
            markAsBase: false
        )
        let promoted = try harness.promoter.promote(
            session: session,
            plan: plan,
            saveDisposition: .replaceExisting(profileID: harness.profile.id)
        )

        XCTAssertEqual(promoted.importResult.game.id, harness.game.id)
        XCTAssertEqual(try harness.builds.fetchBuilds(gameID: harness.game.id).count, 1)
        XCTAssertEqual(try harness.libraryBatteryData(), Data([7, 7, 7]))
        XCTAssertFalse(harness.store.fileExists(at: session.rootURL))
        let safetyCopy = try XCTUnwrap(promoted.safetyCopy)
        XCTAssertEqual(safetyCopy.copiedFromProfileID, harness.profile.id)
        XCTAssertEqual(try harness.libraryBatteryData(profileID: safetyCopy.id), Data([1, 2, 3]))
    }

    func testReplacingAProfileOfAnotherGameIsRefusedBeforeAnythingIsImported() throws {
        let harness = try QuickPlayHarness.make(seedBattery: Data([1]))
        let rom = try harness.writeExternalROM(TestROM.make(title: "OTHER", cgb: false, payloadByte: 5))
        let session = try harness.workspace.start(romURL: rom, copiedSaveProfileID: harness.profile.id)
        try harness.workspace.writeTemporaryBattery(Data([3]), sessionID: session.id)

        let analysis = try harness.promoter.analyze(session, targetGameID: nil)
        XCTAssertThrowsError(try harness.promoter.promote(
            session: session,
            plan: ROMImportPlan(
                analysis: analysis,
                disposition: .createGame(title: "Other"),
                buildDisplayName: "Other",
                markAsBase: true
            ),
            saveDisposition: .replaceExisting(profileID: harness.profile.id)
        )) { error in
            XCTAssertEqual(error as? PromoteQuickPlayError, .profileInDifferentGame(profileID: harness.profile.id))
        }

        XCTAssertEqual(try harness.games.fetchGames().count, 1)
        XCTAssertEqual(try harness.libraryBatteryData(), Data([1]))
        XCTAssertTrue(harness.store.fileExists(at: session.rootURL), "the session stays for another try")
    }

    func testASaveFailureAfterImportKeepsTheSessionForARetry() throws {
        let harness = try QuickPlayHarness.make(seedBattery: Data([1]))
        let rom = try harness.writeExternalROM(TestROM.make(title: "RETRY", cgb: false, payloadByte: 9))
        let session = try harness.workspace.start(romURL: rom, copiedSaveProfileID: harness.profile.id)
        try harness.workspace.writeTemporaryBattery(Data([4]), sessionID: session.id)
        let refusing = PromoteQuickPlay(
            analyzer: ROMImportAnalyzer(builds: harness.builds,
                fingerprints: harness.fingerprints,
                toolchainReports: harness.toolchainReports,
                assetStore: harness.store),
            committer: ImportCommitter(
                games: harness.games,
                builds: harness.builds,
                assets: harness.assets,
                toolchainReports: harness.toolchainReports,
                fingerprints: harness.fingerprints,
                assetStore: harness.store,
                transactions: PassthroughTransactionRunner()
            ),
            workspace: harness.workspace,
            builds: harness.builds,
            profiles: InsertRefusingProfiles(inner: harness.profiles),
            states: harness.states,
            assets: harness.assets,
            assetStore: harness.store
        )
        let plan = ROMImportPlan(
            analysis: try refusing.analyze(session, targetGameID: harness.game.id),
            disposition: .addBuild(gameID: harness.game.id),
            buildDisplayName: "Retry",
            markAsBase: false
        )

        XCTAssertThrowsError(try refusing.promote(session: session, plan: plan, saveDisposition: .createProfile(name: "New"))) { error in
            guard case .importedButSaveFailed(let gameID, _) = error as? PromoteQuickPlayError else {
                return XCTFail("Expected importedButSaveFailed, got \(error)")
            }
            XCTAssertEqual(gameID, harness.game.id)
        }
        XCTAssertTrue(harness.store.fileExists(at: session.rootURL), "the session stays for a retry")

        let retry = try harness.promoter.analyze(session, targetGameID: harness.game.id)
        let promoted = try harness.promoter.promote(
            session: session,
            plan: ROMImportPlan(analysis: retry, disposition: .duplicateExisting(buildID: XCTUnwrap(retry.exactExistingBuildID)), buildDisplayName: "Retry", markAsBase: false),
            saveDisposition: .createProfile(name: "New")
        )
        XCTAssertEqual(try harness.libraryBatteryData(profileID: XCTUnwrap(promoted.saveProfile).id), Data([4]))
    }

    func testAFailedReplaceLeavesNoSafetyCopyBehind() throws {
        let harness = try QuickPlayHarness.make(seedBattery: Data([1]))
        let rom = try harness.writeExternalROM(TestROM.make(title: "REPLACE", cgb: false, payloadByte: 11))
        let session = try harness.workspace.start(romURL: rom, copiedSaveProfileID: harness.profile.id)
        try harness.workspace.writeTemporaryBattery(Data([5]), sessionID: session.id)
        let refusing = PromoteQuickPlay(
            analyzer: ROMImportAnalyzer(builds: harness.builds,
                fingerprints: harness.fingerprints,
                toolchainReports: harness.toolchainReports,
                assetStore: harness.store),
            committer: ImportCommitter(
                games: harness.games,
                builds: harness.builds,
                assets: harness.assets,
                toolchainReports: harness.toolchainReports,
                fingerprints: harness.fingerprints,
                assetStore: harness.store,
                transactions: PassthroughTransactionRunner()
            ),
            workspace: harness.workspace,
            builds: harness.builds,
            profiles: UpdateRefusingProfiles(inner: harness.profiles),
            states: harness.states,
            assets: harness.assets,
            assetStore: harness.store
        )
        let plan = ROMImportPlan(
            analysis: try refusing.analyze(session, targetGameID: harness.game.id),
            disposition: .addBuild(gameID: harness.game.id),
            buildDisplayName: "Replace",
            markAsBase: false
        )

        XCTAssertThrowsError(try refusing.promote(
            session: session,
            plan: plan,
            saveDisposition: .replaceExisting(profileID: harness.profile.id)
        ))
        XCTAssertEqual(try harness.profiles.fetchSaveProfiles(gameID: harness.game.id).map(\.id), [harness.profile.id])
        XCTAssertEqual(try harness.libraryBatteryData(), Data([1]))
    }

    func testKeptSessionsListWithTheDatesTheyWereSavedWith() throws {
        let harness = try QuickPlayHarness.make()
        let rom = try harness.writeExternalROM(TestROM.make(title: "KEEP", cgb: false, payloadByte: 6))
        let session = try harness.workspace.start(romURL: rom)

        XCTAssertEqual(try harness.workspace.load(sessionID: session.id), session)
        XCTAssertEqual(try harness.workspace.sessions(), [session])
    }

    func testALoadedSessionLivesWhereTheWorkspaceIsNowNotWhereItWasRecorded() throws {
        let harness = try QuickPlayHarness.make()
        let rom = try harness.writeExternalROM(TestROM.make(title: "MOVED", cgb: false))
        let session = try harness.workspace.start(romURL: rom)
        let manifest = try String(contentsOf: session.manifestURL, encoding: .utf8)
        let stale = manifest.replacingOccurrences(
            of: session.rootURL.absoluteString.replacingOccurrences(of: "/", with: "\\/"),
            with: "file:\\/\\/\\/old-container\\/QuickPlay\\/"
        )
        XCTAssertNotEqual(stale, manifest, "the fixture rewrote the recorded root")
        try stale.write(to: session.manifestURL, atomically: true, encoding: .utf8)

        XCTAssertEqual(try harness.workspace.load(sessionID: session.id).rootURL, session.rootURL)
    }

    func testPromotionCanCreateIndependentSaveProfile() throws {
        let harness = try QuickPlayHarness.make(seedBattery: Data([1]))
        let rom = try harness.writeExternalROM(TestROM.make(title: "FORK", cgb: false, payloadByte: 8))
        let session = try harness.workspace.start(
            romURL: rom,
            copiedSaveProfileID: harness.profile.id
        )
        try harness.workspace.writeTemporaryBattery(Data([2, 2]), sessionID: session.id)

        let analysis = try harness.promoter.analyze(session, targetGameID: harness.game.id)
        let result = try harness.promoter.promote(
            session: session,
            plan: ROMImportPlan(
                analysis: analysis,
                disposition: .addBuild(gameID: harness.game.id),
                buildDisplayName: "Fork",
                markAsBase: false
            ),
            saveDisposition: .createProfile(name: "Testing")
        )

        let newProfile = try XCTUnwrap(result.saveProfile)
        XCTAssertNotEqual(newProfile.id, harness.profile.id)
        XCTAssertEqual(newProfile.displayName, "Testing")
        XCTAssertEqual(try harness.libraryBatteryData(profileID: newProfile.id), Data([2, 2]))
        XCTAssertEqual(try harness.libraryBatteryData(), Data([1]))
    }
}

private struct QuickPlayHarness {
    let external: URL
    let store: ManagedFileStore
    let games: InMemoryGameRepository
    let builds: InMemoryBuildRepository
    let profiles: InMemorySaveProfileRepository
    let states: InMemorySaveStateRepository
    let assets: InMemoryAssetRepository
    let fingerprints: InMemoryImageFingerprintRepository
    let toolchainReports: InMemoryToolchainReportRepository
    let game: Game
    let profile: SaveProfile
    let workspace: QuickPlayWorkspace
    let promoter: PromoteQuickPlay

    static func make(
        seedBattery: Data? = nil,
        now: Date = Date(timeIntervalSince1970: 1_700_000_000),
        retentionSeconds: TimeInterval = 24 * 60 * 60
    ) throws -> QuickPlayHarness {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("EmulatorKit-QuickPlayTests-\(UUID().uuidString)", isDirectory: true)
        let external = root.appendingPathComponent("External", isDirectory: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let store = try ManagedFileStore(rootURL: root.appendingPathComponent("Managed", isDirectory: true))
        let games = InMemoryGameRepository()
        let builds = InMemoryBuildRepository()
        let profiles = InMemorySaveProfileRepository()
        let states = InMemorySaveStateRepository()
        let fingerprints = InMemoryImageFingerprintRepository()
        let toolchainReports = InMemoryToolchainReportRepository()
        let assets = InMemoryAssetRepository(fingerprints: fingerprints)

        let game = Game(
            id: UUID(),
            primaryTitle: "Test",
            systemFamily: "gameboy",
            createdAt: now,
            modifiedAt: now
        )
        try games.insertGame(game)
        var profile = SaveProfile(
            id: UUID(),
            gameID: game.id,
            displayName: "Main",
            createdAt: now,
            modifiedAt: now
        )
        try profiles.insertSaveProfile(profile)

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
            try profiles.updateSaveProfile(profile)
        }

        let workspace = QuickPlayWorkspace(
            profiles: profiles,
            assets: assets,
            assetStore: store,
            retentionSeconds: retentionSeconds,
            now: { now }
        )
        let analyzer = ROMImportAnalyzer(builds: builds,
            fingerprints: fingerprints,
            toolchainReports: toolchainReports,
            assetStore: store)
        let committer = ImportCommitter(
            games: games,
            builds: builds,
            assets: assets,
            toolchainReports: toolchainReports,
            fingerprints: fingerprints,
            assetStore: store,
            transactions: PassthroughTransactionRunner(),
            now: { now }
        )
        let promoter = PromoteQuickPlay(
            analyzer: analyzer,
            committer: committer,
            workspace: workspace,
            builds: builds,
            profiles: profiles,
            states: states,
            assets: assets,
            assetStore: store,
            now: { now }
        )

        return QuickPlayHarness(
            external: external,
            store: store,
            games: games,
            builds: builds,
            profiles: profiles,
            states: states,
            assets: assets,
            fingerprints: fingerprints,
            toolchainReports: toolchainReports,
            game: game,
            profile: profile,
            workspace: workspace,
            promoter: promoter
        )
    }

    func makeRuntime(
        _ session: QuickPlaySession,
        factory: any EmulatorCoreFactory = QuickPlayFakeFactory(),
        store: (any AssetStore)? = nil
    ) -> QuickPlayRuntimeSession {
        QuickPlayRuntimeSession(session: session, coreRegistry: CoreRegistry(factories: [factory]), assetStore: store ?? self.store)
    }

    func writeExternalROM(_ data: Data) throws -> URL {
        let url = external.appendingPathComponent("\(UUID().uuidString).gb")
        try data.write(to: url)
        return url
    }

    func libraryBatteryHash(profileID: UUID? = nil) throws -> String {
        let id = profileID ?? profile.id
        let selected = try XCTUnwrap(profiles.fetchSaveProfile(id: id))
        let assetID = try XCTUnwrap(selected.persistentSaveAssetID)
        let asset = try XCTUnwrap(assets.fetchAsset(id: assetID))
        return asset.contentSHA256
    }

    func libraryBatteryData(profileID: UUID? = nil) throws -> Data {
        let id = profileID ?? profile.id
        let selected = try XCTUnwrap(profiles.fetchSaveProfile(id: id))
        let assetID = try XCTUnwrap(selected.persistentSaveAssetID)
        let asset = try XCTUnwrap(assets.fetchAsset(id: assetID))
        return try store.readData(at: store.managedURL(relativePath: asset.relativePath))
    }
}

extension QuickPlayTests {
    func testRuntimeWritesOnlyTemporaryBatteryAndAutoState() throws {
        let harness = try QuickPlayHarness.make(seedBattery: Data([1, 2, 3]))
        let rom = try harness.writeExternalROM(TestROM.make(title: "SMOKE", cgb: true))
        let session = try harness.workspace.start(
            romURL: rom,
            copiedSaveProfileID: harness.profile.id
        )
        let runtime = harness.makeRuntime(session)

        try runtime.start(resumeAutoState: false)
        _ = try runtime.stepFrame(input: .init(a: true))
        try runtime.background()

        XCTAssertEqual(try harness.libraryBatteryData(), Data([1, 2, 3]))
        XCTAssertEqual(try harness.workspace.temporaryBatteryData(sessionID: session.id), Data([1, 2, 3]))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: session.rootURL.appendingPathComponent("autosave.state").path
        ))
    }
}

extension QuickPlayTests {
    func testARejectedAutosaveBootsTheGameAndIsSetAside() throws {
        let harness = try QuickPlayHarness.make()
        let rom = try harness.writeExternalROM(TestROM.make(title: "BROKEN", cgb: false))
        let session = try harness.workspace.start(romURL: rom)
        let autoStateURL = session.rootURL.appendingPathComponent("autosave.state")
        try Data("not a state".utf8).write(to: autoStateURL)

        let runtime = harness.makeRuntime(session)
        try runtime.start()

        XCTAssertTrue(runtime.autoStateRejected)
        XCTAssertEqual(runtime.state, .running(session.id))
        XCTAssertEqual(try runtime.stepFrame().bgra8888[0], 1, "the game booted from the start")
        XCTAssertFalse(FileManager.default.fileExists(atPath: autoStateURL.path))
        XCTAssertEqual(
            try Data(contentsOf: session.rootURL.appendingPathComponent("autosave.rejected.state")),
            Data("not a state".utf8)
        )
    }
}

extension QuickPlayTests {
    func testRestartBootsTheGameAgainAndKeepsItsSave() throws {
        let harness = try QuickPlayHarness.make(seedBattery: Data([1, 2, 3]))
        let rom = try harness.writeExternalROM(TestROM.make(title: "AGAIN", cgb: false))
        let session = try harness.workspace.start(romURL: rom, copiedSaveProfileID: harness.profile.id)
        let factory = CapturingQuickPlayFactory()
        let runtime = harness.makeRuntime(session, factory: factory)
        try runtime.start(resumeAutoState: false)
        for _ in 0..<3 { _ = try runtime.stepFrame() }

        try runtime.restart()

        XCTAssertEqual(try runtime.stepFrame().bgra8888[0], 1, "the game booted again")
        XCTAssertEqual(factory.cores.map(\.bootAnimationSkips), [2], "a restart skips the boot logo as a fresh start does")
        try runtime.flushBattery()
        XCTAssertEqual(try harness.workspace.temporaryBatteryData(sessionID: session.id), Data([1, 2, 3]))
    }
}

extension QuickPlayTests {
    func testQuickPlayNeverAppliesCheats() throws {
        let harness = try QuickPlayHarness.make()
        let rom = try harness.writeExternalROM(TestROM.make(title: "NOCHEATS", cgb: false))
        let session = try harness.workspace.start(romURL: rom)
        let factory = CapturingQuickPlayFactory()
        let runtime = harness.makeRuntime(session, factory: factory)
        try runtime.start(resumeAutoState: false)
        for _ in 0..<3 { _ = try runtime.stepFrame() }
        try runtime.restart()
        let core = try XCTUnwrap(factory.cores.last)
        XCTAssertEqual(core.framesRunAtCheatChanges, [])
        XCTAssertEqual(core.cheatCodes, [])
    }

    func testFreshStartSkipsBootAnimationButResumeDoesNot() throws {
        let harness = try QuickPlayHarness.make()
        let rom = try harness.writeExternalROM(TestROM.make(title: "BOOT", cgb: false))
        let session = try harness.workspace.start(romURL: rom)

        let fresh = CapturingQuickPlayFactory()
        let first = harness.makeRuntime(session, factory: fresh)
        try first.start()
        XCTAssertEqual(fresh.cores.map(\.bootAnimationSkips), [1])
        try first.background()

        let resumed = CapturingQuickPlayFactory()
        let second = harness.makeRuntime(session, factory: resumed)
        try second.start()
        XCTAssertEqual(resumed.cores.map(\.bootAnimationSkips), [0])
    }
}

extension QuickPlayTests {
    func testQuickPlayWritesTheGameSaveDuringPlay() throws {
        let harness = try QuickPlayHarness.make(seedBattery: Data([1]))
        let rom = try harness.writeExternalROM(TestROM.make(title: "LIVE", cgb: false))
        let session = try harness.workspace.start(romURL: rom, copiedSaveProfileID: harness.profile.id)
        let factory = CapturingQuickPlayFactory()
        let runtime = harness.makeRuntime(session, factory: factory)
        try runtime.start()
        try XCTUnwrap(factory.cores.last).writeBattery(Data([2]))

        for _ in 0..<298 {
            _ = try runtime.stepFrame()
            XCTAssertFalse(try runtime.flushBatteryIfChanged())
        }
        _ = try runtime.stepFrame()
        XCTAssertTrue(try runtime.flushBatteryIfChanged())
        XCTAssertEqual(try harness.workspace.temporaryBatteryData(sessionID: session.id), Data([2]))
        for _ in 0..<300 { _ = try runtime.stepFrame() }
        XCTAssertFalse(try runtime.flushBatteryIfChanged(), "an unchanged save isn't written again")
    }

    func testAFailedQuickPlayBatteryWriteStillSavesTheAutosaveAndCanBeRetried() throws {
        let harness = try QuickPlayHarness.make(seedBattery: Data([1]))
        let rom = try harness.writeExternalROM(TestROM.make(title: "RETRY", cgb: false))
        let session = try harness.workspace.start(romURL: rom, copiedSaveProfileID: harness.profile.id)
        let factory = CapturingQuickPlayFactory()
        let runtime = harness.makeRuntime(session, factory: factory)
        try runtime.start()
        try XCTUnwrap(factory.cores.last).writeBattery(Data([2]))
        // A directory where battery.sav goes, so the rename onto it fails.
        try FileManager.default.removeItem(at: session.persistentSaveURL)
        try FileManager.default.createDirectory(at: session.persistentSaveURL, withIntermediateDirectories: true)

        XCTAssertThrowsError(try runtime.stop())
        XCTAssertTrue(FileManager.default.fileExists(atPath: session.rootURL.appendingPathComponent("autosave.state").path))
        XCTAssertEqual(runtime.state, .paused(session.id), "still open, so stop can be retried")

        try FileManager.default.removeItem(at: session.persistentSaveURL)
        try runtime.stop()
        XCTAssertEqual(runtime.state, .stopped)
        XCTAssertEqual(try harness.workspace.temporaryBatteryData(sessionID: session.id), Data([2]))

        let second = harness.makeRuntime(session, factory: factory)
        try second.start()
        try XCTUnwrap(factory.cores.last).writeBattery(Data([3]))
        try second.stop(createAutoState: true, discardUnsaved: true)
        XCTAssertEqual(second.state, .stopped)
        XCTAssertEqual(try harness.workspace.temporaryBatteryData(sessionID: session.id), Data([2]), "nothing was saved")
    }

    func testAnAutosaveOlderThanTheBatterySaveIsNotRestored() throws {
        let harness = try QuickPlayHarness.make(seedBattery: Data([1]))
        let rom = try harness.writeExternalROM(TestROM.make(title: "STALE", cgb: false))
        let session = try harness.workspace.start(romURL: rom, copiedSaveProfileID: harness.profile.id)
        let first = harness.makeRuntime(session)
        try first.start(resumeAutoState: false)
        try first.background()
        try first.stop(createAutoState: false)
        // As when a later background wrote the battery save and then failed to write the state.
        try harness.workspace.writeTemporaryBattery(Data([9]), sessionID: session.id)

        let fresh = CapturingQuickPlayFactory()
        let second = harness.makeRuntime(session, factory: fresh)
        try second.start()
        XCTAssertEqual(fresh.cores.map(\.bootAnimationSkips), [1], "booted rather than resumed")
        XCTAssertFalse(second.autoStateRejected)
        try second.stop(createAutoState: false)
        XCTAssertEqual(try harness.workspace.temporaryBatteryData(sessionID: session.id), Data([9]), "the newer save stays")
    }

    func testQuickPlaySavesUseTheDurableWriter() throws {
        let harness = try QuickPlayHarness.make(seedBattery: Data([1]))
        let rom = try harness.writeExternalROM(TestROM.make(title: "SYNC", cgb: false))
        let session = try harness.workspace.start(romURL: rom, copiedSaveProfileID: harness.profile.id)
        let operations = RenameRecordingFileOperations()
        let store = try ManagedFileStore(rootURL: harness.store.rootURL, atomicWriter: AtomicFileWriter(fileOperations: operations))
        let runtime = harness.makeRuntime(session, store: store)
        try runtime.start()

        try runtime.background()

        XCTAssertTrue(operations.renamedTo.contains("battery.sav"))
        XCTAssertTrue(operations.renamedTo.contains("autosave.state"))
    }
}

extension QuickPlayTests {
    func testAddingQuickPlayToTheLibraryKeepsWhereItLeftOff() throws {
        let harness = try QuickPlayHarness.make(seedBattery: Data([1]))
        let rom = try harness.writeExternalROM(TestROM.make(title: "RESUME", cgb: false, payloadByte: 12))
        let session = try harness.workspace.start(romURL: rom, copiedSaveProfileID: harness.profile.id)
        let runtime = harness.makeRuntime(session)
        try runtime.start()
        for _ in 0..<3 { _ = try runtime.stepFrame() }
        try runtime.stop()
        let autosave = try Data(contentsOf: session.autoStateURL)

        let result = try harness.promoter.promote(
            session: session,
            plan: ROMImportPlan(
                analysis: try harness.promoter.analyze(session, targetGameID: harness.game.id),
                disposition: .addBuild(gameID: harness.game.id),
                buildDisplayName: "Resume",
                markAsBase: false
            ),
            saveDisposition: .createProfile(name: "Kept")
        )

        let profile = try XCTUnwrap(result.saveProfile)
        let states = try harness.states.fetchSaveStates(buildID: result.importResult.build.id, saveProfileID: profile.id)
        let state = try XCTUnwrap(states.first)
        XCTAssertEqual(states.count, 1)
        XCTAssertEqual(state.kind, .auto)
        XCTAssertEqual(state.core, CoreDescriptor(identifier: "sameboy", version: "1.0.3"))
        XCTAssertEqual(state.stateSerializationVersion, "fake-json-v1")
        XCTAssertLessThanOrEqual(profile.modifiedAt, state.createdAt, "not older than the save, so the first launch resumes it")
        let asset = try XCTUnwrap(harness.assets.fetchAsset(id: state.stateAssetID))
        XCTAssertEqual(try harness.store.readData(at: harness.store.managedURL(relativePath: asset.relativePath)), autosave)
    }

    func testAnAutosaveOlderThanTheQuickPlaySaveIsNotAddedToTheLibrary() throws {
        let harness = try QuickPlayHarness.make(seedBattery: Data([1]))
        let rom = try harness.writeExternalROM(TestROM.make(title: "OLDER", cgb: false, payloadByte: 13))
        let session = try harness.workspace.start(romURL: rom, copiedSaveProfileID: harness.profile.id)
        let runtime = harness.makeRuntime(session)
        try runtime.start()
        try runtime.stop()
        try harness.workspace.writeTemporaryBattery(Data([9]), sessionID: session.id)

        let result = try harness.promoter.promote(
            session: session,
            plan: ROMImportPlan(
                analysis: try harness.promoter.analyze(session, targetGameID: harness.game.id),
                disposition: .addBuild(gameID: harness.game.id),
                buildDisplayName: "Older",
                markAsBase: false
            ),
            saveDisposition: .replaceExisting(profileID: harness.profile.id)
        )

        XCTAssertEqual(try harness.libraryBatteryData(), Data([9]))
        XCTAssertEqual(try harness.states.fetchSaveStates(buildID: result.importResult.build.id, saveProfileID: harness.profile.id), [])
    }
}

extension QuickPlayTests {
    /// Plays a few frames of a game with no battery save and closes, leaving only the autosave.
    private func stateOnlySession(_ harness: QuickPlayHarness, title: String) throws -> QuickPlaySession {
        let rom = try harness.writeExternalROM(TestROM.make(title: title, cgb: false, payloadByte: 21))
        let session = try harness.workspace.start(romURL: rom)
        let runtime = harness.makeRuntime(session)
        try runtime.start()
        for _ in 0..<3 { _ = try runtime.stepFrame() }
        try runtime.stop()
        XCTAssertNil(try harness.workspace.temporaryBatteryData(sessionID: session.id), "no battery save")
        XCTAssertTrue(session.hasResumePoint(files: harness.store))
        return session
    }

    private func resolver(_ harness: QuickPlayHarness) -> ResolvePreferredSaveProfile {
        ResolvePreferredSaveProfile(
            games: harness.games, builds: harness.builds, profiles: harness.profiles,
            createBlank: CreateBlankSaveProfile(games: harness.games, profiles: harness.profiles)
        )
    }

    func testAGameWithNoBatterySaveKeepsItsResumePointInANewGame() throws {
        let harness = try QuickPlayHarness.make()
        let session = try stateOnlySession(harness, title: "NO BATTERY")

        let result = try harness.promoter.promote(
            session: session,
            plan: ROMImportPlan(
                analysis: try harness.promoter.analyze(session, targetGameID: nil),
                disposition: .createGame(title: "No Battery"),
                buildDisplayName: "No Battery",
                markAsBase: true
            ),
            saveDisposition: .createProfile(name: "Quick Play")
        )

        XCTAssertEqual(result.shortfalls, [])
        let profile = try XCTUnwrap(result.saveProfile)
        XCTAssertNil(profile.persistentSaveAssetID, "a blank profile holds the resume point")
        XCTAssertEqual(result.build.preferredSaveProfileID, profile.id)
        XCTAssertEqual(try harness.builds.fetchBuild(id: result.build.id)?.preferredSaveProfileID, profile.id)
        let states = try harness.states.fetchSaveStates(buildID: result.build.id, saveProfileID: profile.id)
        XCTAssertEqual(states.map(\.kind), [.auto])
        XCTAssertEqual(try resolver(harness).execute(gameID: result.importResult.game.id, buildID: result.build.id).id, profile.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: session.rootURL.path), "everything moved, so the session goes")
    }

    func testAResumePointAddedToAnExistingGameLeavesItsOtherSavesAlone() throws {
        let harness = try QuickPlayHarness.make(seedBattery: Data([1]))
        var game = harness.game
        game.preferredSaveProfileID = harness.profile.id
        try harness.games.updateGame(game)
        let otherSession = try harness.workspace.start(
            romURL: harness.writeExternalROM(TestROM.make(title: "OTHER", cgb: false, payloadByte: 22))
        )
        let other = try harness.promoter.promote(
            session: otherSession,
            plan: ROMImportPlan(
                analysis: try harness.promoter.analyze(otherSession, targetGameID: harness.game.id),
                disposition: .addBuild(gameID: harness.game.id),
                buildDisplayName: "Other",
                markAsBase: false
            ),
            saveDisposition: .keepExisting
        )
        XCTAssertNil(other.build.preferredSaveProfileID, "keeping nothing sets nothing")
        let session = try stateOnlySession(harness, title: "NO BATTERY")

        let result = try harness.promoter.promote(
            session: session,
            plan: ROMImportPlan(
                analysis: try harness.promoter.analyze(session, targetGameID: harness.game.id),
                disposition: .addBuild(gameID: harness.game.id),
                buildDisplayName: "No Battery",
                markAsBase: false
            ),
            saveDisposition: .createProfile(name: "Quick Play")
        )

        let profile = try XCTUnwrap(result.saveProfile)
        XCTAssertEqual(result.build.preferredSaveProfileID, profile.id)
        XCTAssertEqual(try harness.games.fetchGame(id: harness.game.id)?.preferredSaveProfileID, harness.profile.id, "the Game's default stays")
        XCTAssertNil(try harness.builds.fetchBuild(id: other.build.id)?.preferredSaveProfileID, "other Builds stay")
        XCTAssertEqual(try harness.libraryBatteryData(), Data([1]), "Main is untouched")
        XCTAssertEqual(try resolver(harness).execute(gameID: harness.game.id, buildID: other.build.id).id, harness.profile.id)
    }

    func testReplacingTheCopiedProfileMakesItThePromotedBuildsSave() throws {
        let harness = try QuickPlayHarness.make(seedBattery: Data([1]))
        let rom = try harness.writeExternalROM(TestROM.make(title: "REPLACE", cgb: false, payloadByte: 23))
        let session = try harness.workspace.start(romURL: rom, copiedSaveProfileID: harness.profile.id)
        try harness.workspace.writeTemporaryBattery(Data([9]), sessionID: session.id)

        let result = try harness.promoter.promote(
            session: session,
            plan: ROMImportPlan(
                analysis: try harness.promoter.analyze(session, targetGameID: harness.game.id),
                disposition: .addBuild(gameID: harness.game.id),
                buildDisplayName: "Replace",
                markAsBase: false
            ),
            saveDisposition: .replaceExisting(profileID: harness.profile.id)
        )
        XCTAssertEqual(result.build.preferredSaveProfileID, harness.profile.id)
        XCTAssertEqual(try harness.libraryBatteryData(profileID: XCTUnwrap(result.safetyCopy).id), Data([1]))
    }

    func testAddingAROMAlreadyInTheLibraryPointsThatBuildAtTheKeptSave() throws {
        let harness = try QuickPlayHarness.make(seedBattery: Data([1]))
        let image = TestROM.make(title: "ALREADY", cgb: false, payloadByte: 24)
        let first = try harness.workspace.start(romURL: harness.writeExternalROM(image))
        let existing = try harness.promoter.promote(
            session: first,
            plan: ROMImportPlan(
                analysis: try harness.promoter.analyze(first, targetGameID: harness.game.id),
                disposition: .addBuild(gameID: harness.game.id),
                buildDisplayName: "Already",
                markAsBase: false
            ),
            saveDisposition: .keepExisting
        ).build
        var preferring = existing
        preferring.preferredSaveProfileID = harness.profile.id
        try harness.builds.updateBuildMetadata(preferring)

        let session = try harness.workspace.start(romURL: harness.writeExternalROM(image), copiedSaveProfileID: harness.profile.id)
        try harness.workspace.writeTemporaryBattery(Data([9]), sessionID: session.id)
        let result = try harness.promoter.promote(
            session: session,
            plan: ROMImportPlan(
                analysis: try harness.promoter.analyze(session, targetGameID: harness.game.id),
                disposition: .duplicateExisting(buildID: existing.id),
                buildDisplayName: "Already",
                markAsBase: false
            ),
            saveDisposition: .createProfile(name: "Quick Play")
        )

        XCTAssertEqual(result.build.id, existing.id, "the same Build")
        let profile = try XCTUnwrap(result.saveProfile)
        XCTAssertEqual(try harness.builds.fetchBuild(id: existing.id)?.preferredSaveProfileID, profile.id)
        XCTAssertEqual(try harness.libraryBatteryData(profileID: profile.id), Data([9]))
    }

    func testAResumePointThatCantBeMovedKeepsTheSession() throws {
        let harness = try QuickPlayHarness.make()
        let session = try stateOnlySession(harness, title: "NO BATTERY")
        let refusing = PromoteQuickPlay(
            analyzer: ROMImportAnalyzer(builds: harness.builds,
                fingerprints: harness.fingerprints,
                toolchainReports: harness.toolchainReports,
                assetStore: harness.store),
            committer: ImportCommitter(
                games: harness.games,
                builds: harness.builds,
                assets: harness.assets,
                toolchainReports: harness.toolchainReports,
                fingerprints: harness.fingerprints,
                assetStore: harness.store,
                transactions: PassthroughTransactionRunner()
            ),
            workspace: harness.workspace,
            builds: harness.builds,
            profiles: harness.profiles,
            states: InsertRefusingStates(),
            assets: harness.assets,
            assetStore: harness.store
        )

        let result = try refusing.promote(
            session: session,
            plan: ROMImportPlan(
                analysis: try refusing.analyze(session, targetGameID: nil),
                disposition: .createGame(title: "No Battery"),
                buildDisplayName: "No Battery",
                markAsBase: true
            ),
            saveDisposition: .createProfile(name: "Quick Play")
        )

        XCTAssertEqual(result.shortfalls, [.resumePointNotMoved])
        XCTAssertTrue(session.hasResumePoint(files: harness.store), "the session still holds it")
        XCTAssertTrue(try harness.workspace.sessions().contains { $0.id == session.id }, "and is kept for later")
        XCTAssertEqual(try harness.assets.fetchAssets().filter { $0.kind == .saveState }, [], "no half-moved state")
    }

    func testDiscardingProgressSetsNoSaveAndRemovesTheSession() throws {
        let harness = try QuickPlayHarness.make()
        let session = try stateOnlySession(harness, title: "NO BATTERY")
        let result = try harness.promoter.promote(
            session: session,
            plan: ROMImportPlan(
                analysis: try harness.promoter.analyze(session, targetGameID: nil),
                disposition: .createGame(title: "No Battery"),
                buildDisplayName: "No Battery",
                markAsBase: true
            ),
            saveDisposition: .keepExisting
        )
        XCTAssertNil(result.saveProfile)
        XCTAssertNil(result.build.preferredSaveProfileID)
        XCTAssertEqual(try harness.profiles.fetchSaveProfiles(gameID: result.importResult.game.id), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: session.rootURL.path))
    }
}

/// Refuses new states, so moving the resume point fails.
private struct InsertRefusingStates: SaveStateRepository {
    let inner = InMemorySaveStateRepository()
    struct Refused: Error {}

    func insertSaveState(_ state: SaveState) throws { throw Refused() }
    func updateSaveState(_ state: SaveState) throws { throw Refused() }
    func fetchSaveStates(buildID: UUID, saveProfileID: UUID) throws -> [SaveState] {
        try inner.fetchSaveStates(buildID: buildID, saveProfileID: saveProfileID)
    }
    func fetchSaveStates(saveProfileID: UUID) throws -> [SaveState] { try inner.fetchSaveStates(saveProfileID: saveProfileID) }
    func fetchSaveState(id: UUID) throws -> SaveState? { try inner.fetchSaveState(id: id) }
    func renameSaveState(id: UUID, label: String?) throws { try inner.renameSaveState(id: id, label: label) }
    func reassignSaveStates(buildID: UUID, fromSaveProfileID: UUID, toSaveProfileID: UUID) throws {}
    func deleteSaveState(id: UUID) throws { try inner.deleteSaveState(id: id) }
}

/// Records the files the atomic writer puts in place.
private final class RenameRecordingFileOperations: FileOperations, @unchecked Sendable {
    private let live = FoundationFileOperations()
    private let lock = NSLock()
    private var names: [String] = []
    var renamedTo: [String] { lock.withLock { names } }

    func createDirectory(at url: URL) throws { try live.createDirectory(at: url) }
    func fileExists(at url: URL) -> Bool { live.fileExists(at: url) }
    func write(_ data: Data, to url: URL) throws { try live.write(data, to: url) }
    func synchronizeFile(at url: URL) throws { try live.synchronizeFile(at: url) }
    func synchronizeDirectory(at url: URL) throws { try live.synchronizeDirectory(at: url) }
    func moveItem(at source: URL, to destination: URL) throws {
        lock.withLock { names.append(destination.lastPathComponent) }
        try live.moveItem(at: source, to: destination)
    }
    func replaceItem(at destination: URL, with source: URL) throws {
        lock.withLock { names.append(destination.lastPathComponent) }
        try live.replaceItem(at: destination, with: source)
    }
    func removeItemIfExists(at url: URL) throws { try live.removeItemIfExists(at: url) }
}

private final class CapturingQuickPlayFactory: EmulatorCoreFactory, @unchecked Sendable {
    let descriptor = CoreDescriptor(identifier: "sameboy", version: "1.0.3")
    let supportedSystems: Set<GameSystem> = [.gameBoy, .gameBoyColor]
    private(set) var cores: [FakeEmulatorCore] = []

    func makeCore() throws -> any EmulatorCore {
        let core = FakeEmulatorCore(descriptor: descriptor)
        cores.append(core)
        return core
    }
}

private struct QuickPlayFakeFactory: EmulatorCoreFactory {
    let descriptor = CoreDescriptor(identifier: "sameboy", version: "1.0.3")
    let supportedSystems: Set<GameSystem> = [.gameBoy, .gameBoyColor]

    func makeCore() throws -> any EmulatorCore {
        FakeEmulatorCore(descriptor: descriptor)
    }
}

/// Refuses new profiles, so creating one during promotion fails after the import.
private struct InsertRefusingProfiles: SaveProfileRepository {
    let inner: InMemorySaveProfileRepository
    struct Refused: Error {}

    func fetchSaveProfile(id: UUID) throws -> SaveProfile? { try inner.fetchSaveProfile(id: id) }
    func fetchSaveProfiles(gameID: UUID) throws -> [SaveProfile] { try inner.fetchSaveProfiles(gameID: gameID) }
    func fetchAllSaveProfiles() throws -> [SaveProfile] { try inner.fetchAllSaveProfiles() }
    func insertSaveProfile(_ profile: SaveProfile) throws { throw Refused() }
    func updateSaveProfile(_ profile: SaveProfile) throws { try inner.updateSaveProfile(profile) }
    func deleteSaveProfile(id: UUID) throws { try inner.deleteSaveProfile(id: id) }
}

/// Refuses profile updates, so replacing a profile's save fails after its safety copy exists.
private struct UpdateRefusingProfiles: SaveProfileRepository {
    let inner: InMemorySaveProfileRepository
    struct Refused: Error {}

    func fetchSaveProfile(id: UUID) throws -> SaveProfile? { try inner.fetchSaveProfile(id: id) }
    func fetchSaveProfiles(gameID: UUID) throws -> [SaveProfile] { try inner.fetchSaveProfiles(gameID: gameID) }
    func fetchAllSaveProfiles() throws -> [SaveProfile] { try inner.fetchAllSaveProfiles() }
    func insertSaveProfile(_ profile: SaveProfile) throws { try inner.insertSaveProfile(profile) }
    func updateSaveProfile(_ profile: SaveProfile) throws { throw Refused() }
    func deleteSaveProfile(id: UUID) throws { try inner.deleteSaveProfile(id: id) }
}


// Play on a promoted Build continues the progress kept with it.
extension QuickPlayTests {
    func testReviewPromotedBuildPlaysWithItsPromotedSaveProfile() throws {
        let h = try QuickPlayHarness.make(seedBattery: Data([1]))
        var game = h.game
        game.preferredSaveProfileID = h.profile.id
        try h.games.updateGame(game)
        let rom = try h.writeExternalROM(TestROM.make(title: "NEW BUILD", cgb: true))
        let session = try h.workspace.start(romURL: rom, copiedSaveProfileID: h.profile.id)
        try h.workspace.writeTemporaryBattery(Data([9]), sessionID: session.id)
        let analysis = try h.promoter.analyze(session, targetGameID: h.game.id)
        let promoted = try h.promoter.promote(
            session: session,
            plan: ROMImportPlan(analysis: analysis, disposition: .addBuild(gameID: h.game.id),
                                buildDisplayName: "Quick Play build", markAsBase: false),
            saveDisposition: .createProfile(name: "Quick Play progress")
        )
        let promotedProfile = try XCTUnwrap(promoted.saveProfile)
        XCTAssertEqual(try h.libraryBatteryData(profileID: promotedProfile.id), Data([9]))
        let resolver = ResolvePreferredSaveProfile(
            games: h.games, builds: h.builds, profiles: h.profiles,
            createBlank: CreateBlankSaveProfile(games: h.games, profiles: h.profiles)
        )
        let selected = try resolver.execute(gameID: h.game.id, buildID: promoted.importResult.build.id)
        XCTAssertEqual(selected.id, promotedProfile.id,
                       "Play on the promoted Build should use its new progress, not the old Main profile")
    }
}

@Suite("Quick Play metadata provenance")
struct QuickPlayMetadataProvenanceTests {
    @Test("promotion records filename provenance and review overrides")
    func promotion() throws {
        let harness = try QuickPlayHarness.make()
        defer { try? FileManager.default.removeItem(at: harness.external.deletingLastPathComponent()) }
        let rom = harness.external.appendingPathComponent("Example (USA) (En) [v1.2].gb")
        try TestROM.make(title: "EXAMPLE").write(to: rom)
        let session = try harness.workspace.start(romURL: rom)
        let analysis = try harness.promoter.analyze(session, targetGameID: nil)
        var metadata = BuildImportMetadata(analysis: analysis)
        metadata.language = "Fr"
        let result = try harness.promoter.promote(session: session, plan: ROMImportPlan(analysis: analysis,
            disposition: .createGame(title: "Example"), buildDisplayName: analysis.filenameMetadata.suggestedBuildName,
            markAsBase: true, metadata: metadata), saveDisposition: .keepExisting)
        let rows = try harness.builds.fetchMetadataProvenance(ownerID: result.build.id)
        #expect(rows.first { $0.field == .region }?.source == .filename)
        #expect(rows.first { $0.field == .region }?.confidence == .high)
        #expect(rows.first { $0.field == .language }?.source == .player)
        #expect(rows.first { $0.field == .language }?.providedValue == "En")
        #expect(try harness.games.fetchMetadataProvenance(ownerID: result.importResult.game.id).first?.source == .filename)
    }
}

// Quick Play writes its autosave and the record beside it as two files. These set up the files
// the app would leave if it stopped between the writes, since a test can't stop it mid-call.
extension QuickPlayTests {
    /// Two autosaves with a battery save written between them. Returns each one's state and record.
    private func twoAutosaves(
        _ harness: QuickPlayHarness, title: String
    ) throws -> (session: QuickPlaySession, first: (state: Data, record: Data), second: (state: Data, record: Data)) {
        let rom = try harness.writeExternalROM(TestROM.make(title: title, cgb: false))
        let session = try harness.workspace.start(romURL: rom, copiedSaveProfileID: harness.profile.id)
        let factory = CapturingQuickPlayFactory()
        let runtime = harness.makeRuntime(session, factory: factory)
        try runtime.start(resumeAutoState: false)
        _ = try runtime.stepFrame()
        try runtime.background()
        let first = (try Data(contentsOf: session.autoStateURL), try Data(contentsOf: session.autoStateRecordURL))
        _ = try runtime.foreground(policy: .always)
        for _ in 0..<3 { _ = try runtime.stepFrame() }
        try XCTUnwrap(factory.cores.last).writeBattery(Data([2]))
        try runtime.background()
        let second = (try Data(contentsOf: session.autoStateURL), try Data(contentsOf: session.autoStateRecordURL))
        try runtime.stop(createAutoState: false)
        XCTAssertNotEqual(first.0, second.0)
        XCTAssertEqual(try harness.workspace.temporaryBatteryData(sessionID: session.id), Data([2]))
        return (session, first, second)
    }

    private func resumes(_ harness: QuickPlayHarness, _ session: QuickPlaySession) throws -> Bool {
        let factory = CapturingQuickPlayFactory()
        let runtime = harness.makeRuntime(session, factory: factory)
        try runtime.start()
        defer { try? runtime.stop(createAutoState: false) }
        XCTAssertFalse(runtime.autoStateRejected)
        return factory.cores.map(\.bootAnimationSkips) == [0]
    }

    func testAFinishedAutosaveLeavesNoPendingRecord() throws {
        let harness = try QuickPlayHarness.make(seedBattery: Data([1]))
        let saves = try twoAutosaves(harness, title: "DONE")
        XCTAssertFalse(FileManager.default.fileExists(atPath: saves.session.pendingAutoStateRecordURL.path))
        XCTAssertTrue(try resumes(harness, saves.session))
    }

    func testAnAutosaveWrittenWithoutItsRecordIsStillResumed() throws {
        let harness = try QuickPlayHarness.make(seedBattery: Data([1]))
        let saves = try twoAutosaves(harness, title: "TORN")
        // Stopped after the new state was in place and before its record replaced the old one.
        try saves.first.record.write(to: saves.session.autoStateRecordURL)
        try saves.second.record.write(to: saves.session.pendingAutoStateRecordURL)

        XCTAssertTrue(saves.session.hasResumePoint(files: harness.store))
        XCTAssertTrue(try resumes(harness, saves.session), "the newest autosave is resumed, not lost")
    }

    func testAnAutosaveStoppedBeforeItsStateKeepsTheOlderPairsRules() throws {
        let harness = try QuickPlayHarness.make(seedBattery: Data([1]))
        let saves = try twoAutosaves(harness, title: "EARLY")
        // Stopped after the pending record and before the new state: the older pair is on disk,
        // but the battery save is newer than it, so it can't be restored.
        try saves.first.state.write(to: saves.session.autoStateURL)
        try saves.first.record.write(to: saves.session.autoStateRecordURL)
        try saves.second.record.write(to: saves.session.pendingAutoStateRecordURL)

        XCTAssertFalse(saves.session.hasResumePoint(files: harness.store))
        XCTAssertFalse(try resumes(harness, saves.session))
        XCTAssertEqual(try harness.workspace.temporaryBatteryData(sessionID: saves.session.id), Data([2]), "the save stays")
    }

    func testAnAutosaveNoRecordDescribesIsNotResumed() throws {
        let harness = try QuickPlayHarness.make(seedBattery: Data([1]))
        let saves = try twoAutosaves(harness, title: "ODD")
        // A state the record doesn't describe, with no pending record to explain it.
        try saves.first.state.write(to: saves.session.autoStateURL)

        XCTAssertFalse(saves.session.hasResumePoint(files: harness.store))
        XCTAssertFalse(try resumes(harness, saves.session))
    }

    func testARecordFromBeforeStateHashesIsStillTrusted() throws {
        let harness = try QuickPlayHarness.make(seedBattery: Data([1]))
        let saves = try twoAutosaves(harness, title: "OLDREC")
        var record = try XCTUnwrap(JSONSerialization.jsonObject(with: saves.second.record) as? [String: Any])
        record.removeValue(forKey: "stateSHA256")
        try JSONSerialization.data(withJSONObject: record).write(to: saves.session.autoStateRecordURL)

        XCTAssertTrue(saves.session.hasResumePoint(files: harness.store))
        XCTAssertTrue(try resumes(harness, saves.session))
    }
}

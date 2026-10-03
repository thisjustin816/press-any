import AssetStorage
import EmulationCore
import EmulatorKitTestSupport
import EmulatorApplication
import EmulatorDomain
import Foundation
import Importing
import XCTest
@testable import QuickPlay

final class QuickPlayTests: XCTestCase {
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

    func testKeptSessionsListWithTheDatesTheyWereSavedWith() throws {
        let harness = try QuickPlayHarness.make()
        let rom = try harness.writeExternalROM(TestROM.make(title: "KEEP", cgb: false, payloadByte: 6))
        let session = try harness.workspace.start(romURL: rom)

        XCTAssertEqual(try harness.workspace.load(sessionID: session.id), session)
        XCTAssertEqual(try harness.workspace.sessions(), [session])
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
    let assets: InMemoryAssetRepository
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
        let assets = InMemoryAssetRepository()

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
        let analyzer = ROMImportAnalyzer(builds: builds, assetStore: store)
        let committer = ImportCommitter(
            games: games,
            builds: builds,
            assets: assets,
            assetStore: store,
            transactions: PassthroughTransactionRunner(),
            now: { now }
        )
        let promoter = PromoteQuickPlay(
            analyzer: analyzer,
            committer: committer,
            workspace: workspace,
            profiles: profiles,
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
            assets: assets,
            game: game,
            profile: profile,
            workspace: workspace,
            promoter: promoter
        )
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
        let runtime = QuickPlayRuntimeSession(
            session: session,
            coreRegistry: CoreRegistry(factories: [QuickPlayFakeFactory()])
        )

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
    func testFreshStartSkipsBootAnimationButResumeDoesNot() throws {
        let harness = try QuickPlayHarness.make()
        let rom = try harness.writeExternalROM(TestROM.make(title: "BOOT", cgb: false))
        let session = try harness.workspace.start(romURL: rom)

        let fresh = CapturingQuickPlayFactory()
        let first = QuickPlayRuntimeSession(session: session, coreRegistry: CoreRegistry(factories: [fresh]))
        try first.start()
        XCTAssertEqual(fresh.cores.map(\.bootAnimationSkips), [1])
        try first.background()

        let resumed = CapturingQuickPlayFactory()
        let second = QuickPlayRuntimeSession(session: session, coreRegistry: CoreRegistry(factories: [resumed]))
        try second.start()
        XCTAssertEqual(resumed.cores.map(\.bootAnimationSkips), [0])
    }
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

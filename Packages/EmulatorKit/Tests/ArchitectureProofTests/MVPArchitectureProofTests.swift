import AssetStorage
import EmulationCore
import EmulatorKitTestSupport
import EmulationSession
import EmulatorApplication
import EmulatorDomain
import Foundation
import Importing
import Patching
import QuickPlay
import XCTest

final class MVPArchitectureProofTests: XCTestCase {
    func testGameBuildSavePatchQuickPlayAndReorganizationWorkflow() throws {
        let harness = try ArchitectureHarness.make()

        // 1. A clean ROM creates one Game with one Base Build.
        let baseROM = try harness.writeROM(name: "Pokemon Crystal (USA).gbc", payloadByte: 0x10)
        let baseAnalysis = try harness.analyzer.analyzeROM(at: baseROM, targetGameID: nil)
        let baseImport = try harness.committer.commit(.init(
            analysis: baseAnalysis,
            disposition: .createGame(title: "Pokémon Crystal"),
            buildDisplayName: "Original",
            markAsBase: true
        ))
        XCTAssertEqual(try harness.games.fetchGames().count, 1)
        XCTAssertTrue(baseImport.build.isBase)

        // 2. Import a battery save as a manually selectable Save Profile.
        let externalSave = harness.external.appendingPathComponent("main.sav")
        try Data([1, 2, 3, 4]).write(to: externalSave)
        let mainProfile = try ImportBatterySave(
            games: harness.games,
            profiles: harness.profiles,
            assets: harness.assets,
            assetStore: harness.store,
            now: harness.now
        ).execute(gameID: baseImport.game.id, sourceURL: externalSave, name: "Main")
        XCTAssertEqual(try harness.persistentSaveData(profileID: mainProfile.id), Data([1, 2, 3, 4]))

        // 3. The core/session boundary pins the first core and creates Build-scoped states.
        let session = EmulationSession(
            builds: harness.builds,
            profiles: harness.profiles,
            states: harness.states,
            assets: harness.assets,
            assetStore: harness.store,
            imageResolver: harness.patchResolver,
            coreRegistry: CoreRegistry(factories: [
                FakeCoreFactory(descriptor: .init(identifier: "sameboy", version: "1.0.3")),
            ]),
            now: harness.now
        )
        let launch = LaunchContext(
            gameID: baseImport.game.id,
            buildID: baseImport.build.id,
            saveProfileID: mainProfile.id
        )
        try session.start(context: launch)
        _ = try session.stepFrame(input: .init(a: true))
        let manualState = try session.saveManualState(label: "Architecture proof")
        try session.background()
        XCTAssertEqual(manualState.buildID, baseImport.build.id)
        XCTAssertEqual(manualState.saveProfileID, mainProfile.id)
        XCTAssertEqual(try harness.states.fetchSaveStates(
            buildID: baseImport.build.id,
            saveProfileID: mainProfile.id
        ).count, 2)
        XCTAssertEqual(try harness.builds.fetchBuild(id: baseImport.build.id)?.corePin?.descriptor.version, "1.0.3")
        XCTAssertEqual(try harness.persistentSaveData(profileID: mainProfile.id), Data([1, 2, 3, 4]))

        // 4. A modified ROM attaches as a Build instead of duplicating the Game.
        let testROM = try harness.writeROM(name: "Pokemon Crystal Test v2.gbc", payloadByte: 0x20)
        let testAnalysis = try harness.analyzer.analyzeROM(at: testROM, targetGameID: baseImport.game.id)
        let testImport = try harness.committer.commit(.init(
            analysis: testAnalysis,
            disposition: .addBuild(gameID: baseImport.game.id),
            buildDisplayName: "Test v2",
            markAsBase: false
        ))
        XCTAssertEqual(try harness.games.fetchGames().count, 1)
        XCTAssertEqual(try harness.builds.fetchBuilds(gameID: baseImport.game.id).count, 2)
        try harness.buildOperations.setPreferredSaveProfile(buildID: testImport.build.id, profileID: mainProfile.id)

        // 5. A patch-derived Build preserves sources and can regenerate an evicted ROM cache.
        let patchURL = harness.external.appendingPathComponent("smoke.ips")
        try singleByteIPS(offset: 0x0200, value: 0x99).write(to: patchURL)
        let patched = try harness.patchCreator.execute(.init(
            gameID: baseImport.game.id,
            baseBuildID: baseImport.build.id,
            patchURLs: [patchURL],
            displayName: "Patched"
        ))
        let generatedAsset = try XCTUnwrap(harness.assets.fetchAsset(id: patched.imageAssetID))
        let generatedURL = try harness.store.managedURL(relativePath: generatedAsset.relativePath)
        try harness.store.removeIfExists(generatedURL)
        let patchedLaunch = LaunchContext(
            gameID: baseImport.game.id,
            buildID: patched.id,
            saveProfileID: mainProfile.id
        )
        let patchedSession = EmulationSession(
            builds: harness.builds,
            profiles: harness.profiles,
            states: harness.states,
            assets: harness.assets,
            assetStore: harness.store,
            imageResolver: harness.patchResolver,
            coreRegistry: CoreRegistry(factories: [
                FakeCoreFactory(descriptor: .init(identifier: "sameboy", version: "1.0.3")),
            ]),
            now: harness.now
        )
        try patchedSession.start(context: patchedLaunch)
        _ = try patchedSession.stepFrame()
        try patchedSession.stop()
        XCTAssertTrue(harness.store.fileExists(at: generatedURL))
        XCTAssertEqual(try harness.store.hashFile(at: generatedURL), patched.imageSHA256)

        // 6. Quick Play copies a save into isolation and only imports its changed save by choice.
        let smokeROM = try harness.writeROM(name: "Pokemon Crystal Smoke v3.gbc", payloadByte: 0x30)
        let quickSession = try harness.quickWorkspace.start(
            romURL: smokeROM,
            copiedSaveProfileID: mainProfile.id
        )
        try harness.quickWorkspace.writeTemporaryBattery(Data([9, 9, 9]), sessionID: quickSession.id)
        XCTAssertEqual(try harness.persistentSaveData(profileID: mainProfile.id), Data([1, 2, 3, 4]))

        let quickAnalysis = try harness.quickPromoter.analyze(quickSession, targetGameID: baseImport.game.id)
        let promoted = try harness.quickPromoter.promote(
            session: quickSession,
            plan: .init(
                analysis: quickAnalysis,
                disposition: .addBuild(gameID: baseImport.game.id),
                buildDisplayName: "Smoke v3",
                markAsBase: false
            ),
            saveDisposition: .createProfile(name: "Smoke Test")
        )
        let smokeProfile = try XCTUnwrap(promoted.saveProfile)
        XCTAssertEqual(try harness.persistentSaveData(profileID: smokeProfile.id), Data([9, 9, 9]))
        XCTAssertEqual(try harness.persistentSaveData(profileID: mainProfile.id), Data([1, 2, 3, 4]))
        XCTAssertFalse(harness.store.fileExists(at: quickSession.rootURL))

        // 7. A Build can become its own Game, then merge back without changing its Build identity.
        let separatedGame = try harness.buildOperations.promoteBuild(
            buildID: testImport.build.id,
            title: "Pokémon Crystal Test",
            mode: .move
        )
        XCTAssertEqual(try harness.builds.fetchBuild(id: testImport.build.id)?.gameID, separatedGame.id)
        XCTAssertEqual(try harness.games.fetchGames().count, 2)

        try harness.buildOperations.mergeGame(
            sourceGameID: separatedGame.id,
            into: baseImport.game.id,
            mode: .move
        )
        XCTAssertEqual(try harness.games.fetchGames().count, 1)
        XCTAssertEqual(try harness.builds.fetchBuild(id: testImport.build.id)?.gameID, baseImport.game.id)
        XCTAssertEqual(try harness.builds.fetchBuilds(gameID: baseImport.game.id).count, 4)

        // The clean source ROM and original save remain intact after the whole workflow.
        XCTAssertTrue(harness.store.fileExists(
            at: try harness.store.managedURL(relativePath: baseImport.sourceAsset.relativePath)
        ))
        XCTAssertEqual(try harness.persistentSaveData(profileID: mainProfile.id), Data([1, 2, 3, 4]))
    }
}

private struct ArchitectureHarness {
    let root: URL
    let external: URL
    let store: ManagedFileStore
    let games: InMemoryGameRepository
    let builds: InMemoryBuildRepository
    let profiles: InMemorySaveProfileRepository
    let states: InMemorySaveStateRepository
    let assets: InMemoryAssetRepository
    let recipes: InMemoryPatchRecipeRepository
    let analyzer: ROMImportAnalyzer
    let committer: ImportCommitter
    let buildOperations: BuildOperations
    let patchCreator: CreatePatchedBuild
    let patchResolver: ResolveImageForLaunch
    let quickWorkspace: QuickPlayWorkspace
    let quickPromoter: PromoteQuickPlay
    let now: @Sendable () -> Date

    static func make() throws -> ArchitectureHarness {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("EmulatorKit-ArchitectureProof-\(UUID().uuidString)", isDirectory: true)
        let external = root.appendingPathComponent("External", isDirectory: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let store = try ManagedFileStore(rootURL: root.appendingPathComponent("Managed", isDirectory: true))
        let games = InMemoryGameRepository()
        let builds = InMemoryBuildRepository()
        let profiles = InMemorySaveProfileRepository()
        let states = InMemorySaveStateRepository()
        let assets = InMemoryAssetRepository()
        let recipes = InMemoryPatchRecipeRepository()
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let now: @Sendable () -> Date = { timestamp }

        let analyzer = ROMImportAnalyzer(builds: builds, assetStore: store)
        let committer = ImportCommitter(
            games: games,
            builds: builds,
            assets: assets,
            toolchainReports: InMemoryToolchainReportRepository(),
            assetStore: store,
            transactions: PassthroughTransactionRunner(),
            now: now
        )
        let buildOperations = BuildOperations(
            games: games,
            builds: builds,
            profiles: profiles,
            recipes: recipes,
            assets: assets,
            assetStore: store,
            transactions: PassthroughTransactionRunner(),
            now: now
        )
        let patchCreator = CreatePatchedBuild(
            games: games,
            builds: builds,
            recipes: recipes,
            assets: assets,
            toolchainReports: InMemoryToolchainReportRepository(),
            assetStore: store,
            patcher: PatchStackApplier(),
            transactions: PassthroughTransactionRunner(),
            now: now
        )
        let patchResolver = ResolveImageForLaunch(
            builds: builds,
            recipes: recipes,
            assets: assets,
            assetStore: store
        )
        let quickWorkspace = QuickPlayWorkspace(
            profiles: profiles,
            assets: assets,
            assetStore: store,
            now: now
        )
        let quickPromoter = PromoteQuickPlay(
            analyzer: analyzer,
            committer: committer,
            workspace: quickWorkspace,
            profiles: profiles,
            states: states,
            assets: assets,
            assetStore: store,
            now: now
        )

        return ArchitectureHarness(
            root: root,
            external: external,
            store: store,
            games: games,
            builds: builds,
            profiles: profiles,
            states: states,
            assets: assets,
            recipes: recipes,
            analyzer: analyzer,
            committer: committer,
            buildOperations: buildOperations,
            patchCreator: patchCreator,
            patchResolver: patchResolver,
            quickWorkspace: quickWorkspace,
            quickPromoter: quickPromoter,
            now: now
        )
    }

    func writeROM(name: String, payloadByte: UInt8) throws -> URL {
        let url = external.appendingPathComponent(name)
        try TestROM.make(title: "POKEMON CRYSTAL", cgb: true, payloadByte: payloadByte).write(to: url)
        return url
    }

    func persistentSaveData(profileID: UUID) throws -> Data? {
        guard let profile = try profiles.fetchSaveProfile(id: profileID),
              let assetID = profile.persistentSaveAssetID,
              let asset = try assets.fetchAsset(id: assetID) else { return nil }
        return try store.readData(at: store.managedURL(relativePath: asset.relativePath))
    }
}

private func singleByteIPS(offset: Int, value: UInt8) -> Data {
    Data([
        0x50, 0x41, 0x54, 0x43, 0x48,
        UInt8((offset >> 16) & 0xff), UInt8((offset >> 8) & 0xff), UInt8(offset & 0xff),
        0x00, 0x01, value,
        0x45, 0x4f, 0x46,
    ])
}

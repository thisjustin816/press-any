import AssetStorage
import EmulatorApplication
import EmulatorDomain
import Foundation
import PersistenceGRDB
import Testing

@Suite("GRDB persistence")
struct PersistenceGRDBTests {
    @Test("migration and repositories round-trip MVP entities")
    func roundTrip() throws {
        let database = try AppDatabase.inMemory()
        try database.migrate()
        let repositories = database.makeRepositories()
        let fixture = try Fixture.create(in: repositories)

        #expect(try repositories.games.fetchGame(id: fixture.game.id) == fixture.game)
        #expect(try repositories.builds.fetchBuild(id: fixture.build.id) == fixture.build)
        #expect(try repositories.builds.fetchBuilds(gameID: fixture.game.id) == [fixture.build, fixture.patchedBuild])
        #expect(try repositories.builds.fetchBuild(gameID: fixture.game.id, imageSHA256: fixture.build.imageSHA256) == fixture.build)
        #expect(try repositories.saveProfiles.fetchSaveProfile(id: fixture.profile.id) == fixture.profile)
        #expect(try repositories.assets.fetchAsset(id: fixture.romAsset.id) == fixture.romAsset)
        #expect(try repositories.assets.fetchAssets().count == 6)
        #expect(try repositories.saveStates.fetchSaveStates(buildID: fixture.build.id, saveProfileID: fixture.profile.id) == [fixture.state])
        #expect(try repositories.patchRecipes.fetchPatchRecipe(resultBuildID: fixture.patchedBuild.id) == fixture.recipe)
    }

    @Test("a Build keeps one toolchain report per detector, deleted with it")
    func toolchainReports() throws {
        let database = try AppDatabase.inMemory()
        try database.migrate()
        let repositories = database.makeRepositories()
        let fixture = try Fixture.create(in: repositories)
        func report(_ name: String) -> ToolchainDetectionReport {
            ToolchainDetectionReport(
                detector: "gbtoolsid",
                detectorVersion: "1",
                corpusRevision: "v1.5.5-14-g5ff49ad",
                components: [DetectedToolchainComponent(
                    kind: .toolchain,
                    name: name,
                    version: "4.3.0",
                    evidence: [ToolchainEvidence(signature: "sig_a", offset: 0x150)]
                )]
            )
        }

        try repositories.toolchainReports.saveReport(report("GBDK"), buildID: fixture.build.id, detectedAt: Date(timeIntervalSince1970: 1))
        #expect(try repositories.toolchainReports.fetchReports(buildID: fixture.build.id) == [report("GBDK")])

        try repositories.toolchainReports.saveReport(report("ZGB"), buildID: fixture.build.id, detectedAt: Date(timeIntervalSince1970: 2))
        #expect(try repositories.toolchainReports.fetchReports(buildID: fixture.build.id) == [report("ZGB")], "replaced, not added")
        #expect(try repositories.toolchainReports.fetchReports(buildID: fixture.patchedBuild.id) == [])

        try repositories.games.deleteGame(id: fixture.game.id)
        #expect(try repositories.toolchainReports.fetchReports(buildID: fixture.build.id) == [])
    }

    @Test("a profile remembers its save's writer and a Build keeps its variable maps")
    func saveWriterAndVariableMaps() throws {
        let database = try AppDatabase.inMemory()
        try database.migrate()
        let repositories = database.makeRepositories()
        let fixture = try Fixture.create(in: repositories)

        var profile = fixture.profile
        profile.saveWrittenByBuildID = fixture.build.id
        try repositories.saveProfiles.updateSaveProfile(profile)
        #expect(try repositories.saveProfiles.fetchSaveProfile(id: profile.id) == profile)

        let map = BuildVariableMap(
            id: UUID(),
            buildID: fixture.build.id,
            assetID: fixture.romAsset.id,
            format: .gbStudioGlobals,
            source: .userImport,
            originalFilename: "game_globals.i",
            attachedAt: Date(timeIntervalSince1970: 5)
        )
        try repositories.variableMaps.insertVariableMap(map)
        #expect(try repositories.variableMaps.fetchVariableMaps(buildID: fixture.build.id) == [map])
        #expect(try repositories.variableMaps.fetchVariableMaps(buildID: fixture.patchedBuild.id) == [])

        try repositories.games.deleteGame(id: fixture.game.id)
        #expect(try repositories.variableMaps.fetchVariableMaps(buildID: fixture.build.id) == [])
    }

    @Test("transaction runner rolls repository writes back together")
    func transactionRollback() throws {
        let database = try AppDatabase.inMemory()
        try database.migrate()
        let repositories = database.makeRepositories()
        let now = Date(timeIntervalSince1970: 10)
        let game = Game(
            id: UUID(),
            primaryTitle: "Rollback",
            systemFamily: "gb",
            createdAt: now,
            modifiedAt: now
        )

        do {
            _ = try repositories.transactions.run { () throws -> Bool in
                try repositories.games.insertGame(game)
                throw TestFailure.expectedRollback
            }
            Issue.record("transaction unexpectedly succeeded")
        } catch TestFailure.expectedRollback {
            // Expected.
        }

        #expect(try repositories.games.fetchGame(id: game.id) == nil)
    }

    @Test("settings store upserts and removes scoped values")
    func settings() throws {
        let database = try AppDatabase.inMemory()
        try database.migrate()
        let repositories = database.makeRepositories()
        let gameID = UUID()

        try repositories.settings.setValueJSON("true", key: "rewind.enabled", scope: .app)
        try repositories.settings.setValueJSON("false", key: "rewind.enabled", scope: .game(gameID))

        #expect(try repositories.settings.valueJSON(key: "rewind.enabled", scope: .app) == "true")
        #expect(try repositories.settings.valueJSON(key: "rewind.enabled", scope: .game(gameID)) == "false")

        try repositories.settings.removeValue(key: "rewind.enabled", scope: .game(gameID))
        #expect(try repositories.settings.valueJSON(key: "rewind.enabled", scope: .game(gameID)) == nil)
    }

    @Test("deleting a game cascades owned rows but preserves source assets")
    func deletionSemantics() throws {
        let database = try AppDatabase.inMemory()
        try database.migrate()
        let repositories = database.makeRepositories()
        let fixture = try Fixture.create(in: repositories)

        try repositories.games.deleteGame(id: fixture.game.id)

        #expect(try repositories.games.fetchGame(id: fixture.game.id) == nil)
        #expect(try repositories.builds.fetchBuild(id: fixture.build.id) == nil)
        #expect(try repositories.saveProfiles.fetchSaveProfile(id: fixture.profile.id) == nil)
        #expect(try repositories.patchRecipes.fetchPatchRecipe(resultBuildID: fixture.patchedBuild.id) == nil)
        #expect(try repositories.assets.fetchAsset(id: fixture.romAsset.id) == fixture.romAsset)
    }

    @Test("deleting a game refuses to orphan a patch Build in another game")
    func deletionProtectsExternalPatchDependents() throws {
        let database = try AppDatabase.inMemory()
        try database.migrate()
        let repositories = database.makeRepositories()
        let fixture = try Fixture.create(in: repositories)
        let now = Date(timeIntervalSince1970: 1_700_000_100)

        let otherGame = Game(
            id: UUID(),
            primaryTitle: "Promoted Hack",
            systemFamily: "gbc",
            createdAt: now,
            modifiedAt: now
        )
        try repositories.games.insertGame(otherGame)

        let externalBuild = Build(
            id: UUID(),
            gameID: otherGame.id,
            system: .gameBoyColor,
            displayName: "Standalone",
            imageAssetID: fixture.patchedBuild.imageAssetID,
            imageSHA256: String(repeating: "f", count: 64),
            sourceKind: .patchRecipe,
            parentBuildID: fixture.build.id,
            createdAt: now,
            modifiedAt: now
        )
        try repositories.builds.insertBuild(externalBuild)

        let externalRecipe = PatchRecipe(
            id: UUID(),
            resultBuildID: externalBuild.id,
            baseBuildID: fixture.build.id,
            expectedResultSHA256: externalBuild.imageSHA256,
            items: fixture.recipe.items,
            createdAt: now
        )
        try repositories.patchRecipes.insertPatchRecipe(externalRecipe)

        do {
            try repositories.games.deleteGame(id: fixture.game.id)
            Issue.record("deletion unexpectedly orphaned an external patch build")
        } catch PersistenceError.gameHasExternalPatchDependents(let count) {
            #expect(count == 1)
        }

        #expect(try repositories.games.fetchGame(id: fixture.game.id) == fixture.game)
        #expect(try repositories.patchRecipes.fetchPatchRecipe(resultBuildID: externalBuild.id) == externalRecipe)
    }

    @Test("merging a game by move keeps its save profiles and states")
    func mergeMoveKeepsSaveProfiles() throws {
        let database = try AppDatabase.inMemory()
        try database.migrate()
        let repositories = database.makeRepositories()
        let fixture = try Fixture.create(in: repositories)
        let now = Date(timeIntervalSince1970: 1_700_000_100)
        let target = Game(
            id: UUID(),
            primaryTitle: "Target",
            systemFamily: "gbc",
            createdAt: now,
            modifiedAt: now
        )
        try repositories.games.insertGame(target)
        var source = fixture.game
        source.preferredSaveProfileID = fixture.profile.id
        try repositories.games.updateGame(source)
        let operations = BuildOperations(
            games: repositories.games,
            builds: repositories.builds,
            profiles: repositories.saveProfiles,
            states: repositories.saveStates,
            recipes: repositories.patchRecipes,
            assets: repositories.assets,
            assetStore: try ManagedFileStore(rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("grdb-operations-\(UUID().uuidString)", isDirectory: true)),
            transactions: repositories.transactions,
            now: { now }
        )

        try operations.mergeGame(sourceGameID: fixture.game.id, into: target.id, mode: .move)

        #expect(try repositories.games.fetchGame(id: fixture.game.id) == nil)
        var movedProfile = fixture.profile
        movedProfile.gameID = target.id
        #expect(try repositories.saveProfiles.fetchSaveProfile(id: fixture.profile.id) == movedProfile)
        #expect(try repositories.saveStates.fetchSaveStates(buildID: fixture.build.id, saveProfileID: fixture.profile.id) == [fixture.state])
        #expect(try repositories.games.fetchGame(id: target.id)?.preferredSaveProfileID == fixture.profile.id)
        #expect(try repositories.games.fetchGame(id: target.id)?.artworkAssetID == fixture.game.artworkAssetID)
    }

    @Test("promoting a game's last build by move keeps its save profiles")
    func promoteLastBuildKeepsSaveProfiles() throws {
        let database = try AppDatabase.inMemory()
        try database.migrate()
        let repositories = database.makeRepositories()
        let fixture = try Fixture.create(in: repositories)
        let now = Date(timeIntervalSince1970: 1_700_000_100)
        let operations = BuildOperations(
            games: repositories.games,
            builds: repositories.builds,
            profiles: repositories.saveProfiles,
            states: repositories.saveStates,
            recipes: repositories.patchRecipes,
            assets: repositories.assets,
            assetStore: try ManagedFileStore(rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("grdb-operations-\(UUID().uuidString)", isDirectory: true)),
            transactions: repositories.transactions,
            now: { now }
        )

        let separated = try operations.promoteBuild(buildID: fixture.patchedBuild.id, title: "Hack", mode: .move)
        #expect(try repositories.saveProfiles.fetchSaveProfile(id: fixture.profile.id)?.gameID == fixture.game.id)

        let last = try operations.promoteBuild(buildID: fixture.build.id, title: "Original", mode: .move)
        #expect(try repositories.games.fetchGame(id: fixture.game.id) == nil)
        #expect(try repositories.saveProfiles.fetchSaveProfile(id: fixture.profile.id)?.gameID == last.id)
        #expect(try repositories.saveStates.fetchSaveStates(buildID: fixture.build.id, saveProfileID: fixture.profile.id) == [fixture.state])
        #expect(try repositories.builds.fetchBuild(id: fixture.patchedBuild.id)?.gameID == separated.id)
    }

    @Test("separating a Build by move takes its save states to the profile copies it plays")
    func promoteMoveTakesStatesToCopies() throws {
        let database = try AppDatabase.inMemory()
        try database.migrate()
        let repositories = database.makeRepositories()
        let fixture = try Fixture.create(in: repositories)
        let store = try ManagedFileStore(rootURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("grdb-operations-\(UUID().uuidString)", isDirectory: true))
        try store.writeDataAtomically(Data([1]), to: store.managedURL(relativePath: "Saves/profile.sav"))
        let operations = BuildOperations(
            games: repositories.games,
            builds: repositories.builds,
            profiles: repositories.saveProfiles,
            states: repositories.saveStates,
            recipes: repositories.patchRecipes,
            assets: repositories.assets,
            assetStore: store,
            transactions: repositories.transactions,
            now: { Date(timeIntervalSince1970: 1_700_000_100) }
        )

        let separated = try operations.promoteBuild(
            buildID: fixture.build.id,
            title: "Separate",
            mode: .move,
            carryOver: GameCarryOver(artwork: false, saveProfileIDs: [fixture.profile.id])
        )

        let copy = try #require(try repositories.saveProfiles.fetchSaveProfiles(gameID: separated.id).first)
        #expect(try repositories.saveStates.fetchSaveStates(buildID: fixture.build.id, saveProfileID: copy.id).map(\.id) == [fixture.state.id])
        #expect(copy.modifiedAt <= fixture.state.createdAt, "the copy holds the same save, so its Auto States still resume")
        try repositories.saveProfiles.deleteSaveProfile(id: fixture.profile.id)
        #expect(try repositories.saveStates.fetchSaveStates(saveProfileID: copy.id).count == 1, "deleting the original keeps them")
    }

    @Test("merging a Game whose image the target already holds")
    func mergeWithDuplicateImages() throws {
        let database = try AppDatabase.inMemory()
        try database.migrate()
        let repositories = database.makeRepositories()
        let fixture = try Fixture.create(in: repositories)
        let operations = try Self.operations(repositories)

        let copied = try operations.promoteBuild(buildID: fixture.build.id, title: "Copy", mode: .copy)
        let copiedBuild = try #require(try repositories.builds.fetchBuilds(gameID: copied.id).first)

        #expect(throws: BuildOperationError.duplicateImagesInTarget(buildIDs: [copiedBuild.id])) {
            try operations.mergeGame(sourceGameID: copied.id, into: fixture.game.id, mode: .move)
        }
        #expect(try repositories.games.fetchGame(id: copied.id) != nil, "a refused move changes nothing")

        try operations.mergeGame(sourceGameID: copied.id, into: fixture.game.id, mode: .copy)
        #expect(try repositories.builds.fetchBuilds(gameID: fixture.game.id).count == 2, "the duplicate is skipped")
    }

    @Test("artwork follows the Game identity and isn't orphaned by a merge")
    func artworkThroughReorganization() throws {
        let database = try AppDatabase.inMemory()
        try database.migrate()
        let repositories = database.makeRepositories()
        let fixture = try Fixture.create(in: repositories)
        let operations = try Self.operations(repositories)

        let hack = try operations.promoteBuild(buildID: fixture.patchedBuild.id, title: "Hack", mode: .move)
        #expect(try repositories.games.fetchGame(id: hack.id)?.lineage?.sourceGameID == fixture.game.id)
        let carried = try operations.promoteBuild(buildID: fixture.build.id, title: "Original", mode: .move)
        #expect(carried.artworkAssetID == fixture.game.artworkAssetID, "the last Build takes the artwork along")
        #expect(
            try repositories.games.fetchGame(id: hack.id)?.lineage == GameLineage(sourceGameID: nil, sourceTitle: fixture.game.primaryTitle),
            "the lineage keeps the title once its Game is gone"
        )

        let now = Date(timeIntervalSince1970: 1_700_000_200)
        let otherArt = ManagedAsset(
            id: UUID(),
            kind: .artwork,
            storageClass: .userData,
            contentSHA256: String(repeating: "9", count: 64),
            byteLength: 1,
            relativePath: "UserData/Artwork/other.png",
            integrityStatus: .verified,
            createdAt: now
        )
        try repositories.assets.insertAsset(otherArt)
        let target = Game(
            id: UUID(),
            primaryTitle: "Target",
            systemFamily: "gbc",
            artworkAssetID: otherArt.id,
            createdAt: now,
            modifiedAt: now
        )
        try repositories.games.insertGame(target)

        try operations.mergeGame(sourceGameID: carried.id, into: target.id, mode: .move)
        #expect(try repositories.games.fetchGame(id: target.id)?.artworkAssetID == otherArt.id)
        #expect(try repositories.assets.fetchAsset(id: try #require(fixture.game.artworkAssetID)) == nil)
    }

    @Test("a copy merge leaves the copies depending only on the target")
    func copyMergeRepointsPatchBases() throws {
        let database = try AppDatabase.inMemory()
        try database.migrate()
        let repositories = database.makeRepositories()
        let fixture = try Fixture.create(in: repositories)
        let operations = try Self.operations(repositories)
        let now = Date(timeIntervalSince1970: 1_700_000_100)
        let target = Game(id: UUID(), primaryTitle: "Target", systemFamily: "gbc", createdAt: now, modifiedAt: now)
        try repositories.games.insertGame(target)

        try operations.mergeGame(sourceGameID: fixture.game.id, into: target.id, mode: .copy)

        let copies = try repositories.builds.fetchBuilds(gameID: target.id)
        let baseCopy = try #require(copies.first { $0.imageSHA256 == fixture.build.imageSHA256 })
        let patchedCopy = try #require(copies.first { $0.imageSHA256 == fixture.patchedBuild.imageSHA256 })
        #expect(patchedCopy.parentBuildID == baseCopy.id)
        #expect(try repositories.patchRecipes.fetchPatchRecipe(resultBuildID: patchedCopy.id)?.baseBuildID == baseCopy.id)
        try repositories.games.deleteGame(id: fixture.game.id)
    }

    private static func operations(_ repositories: GRDBRepositorySet) throws -> BuildOperations {
        BuildOperations(
            games: repositories.games,
            builds: repositories.builds,
            profiles: repositories.saveProfiles,
            states: repositories.saveStates,
            recipes: repositories.patchRecipes,
            assets: repositories.assets,
            assetStore: try ManagedFileStore(rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("grdb-operations-\(UUID().uuidString)", isDirectory: true)),
            transactions: repositories.transactions,
            now: { Date(timeIntervalSince1970: 1_700_000_100) }
        )
    }
}

private enum TestFailure: Error {
    case expectedRollback
}

struct Fixture {
    let game: Game
    let build: Build
    let patchedBuild: Build
    let profile: SaveProfile
    let state: SaveState
    let recipe: PatchRecipe
    let romAsset: ManagedAsset

    static func create(in repositories: GRDBRepositorySet) throws -> Fixture {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let gameID = UUID()
        let sourceROM = ManagedAsset(
            id: UUID(),
            kind: .sourceImage,
            storageClass: .source,
            contentSHA256: String(repeating: "a", count: 64),
            byteLength: 32_768,
            relativePath: "SourceROMs/aa/base.gbc",
            originalFilename: "Base.gbc",
            integrityStatus: .verified,
            createdAt: now
        )
        let generatedROM = ManagedAsset(
            id: UUID(),
            kind: .generatedImage,
            storageClass: .cache,
            contentSHA256: String(repeating: "b", count: 64),
            byteLength: 32_768,
            relativePath: "GeneratedROMs/bb/patched.gbc",
            integrityStatus: .verified,
            createdAt: now
        )
        let patch = ManagedAsset(
            id: UUID(),
            kind: .sourcePatch,
            storageClass: .source,
            contentSHA256: String(repeating: "c", count: 64),
            byteLength: 128,
            relativePath: "SourcePatches/cc/test.bps",
            originalFilename: "test.bps",
            integrityStatus: .verified,
            createdAt: now
        )
        let battery = ManagedAsset(
            id: UUID(),
            kind: .persistentSave,
            storageClass: .userData,
            contentSHA256: String(repeating: "d", count: 64),
            byteLength: 8_192,
            relativePath: "Saves/profile.sav",
            integrityStatus: .verified,
            createdAt: now
        )
        let stateAsset = ManagedAsset(
            id: UUID(),
            kind: .saveState,
            storageClass: .userData,
            contentSHA256: String(repeating: "e", count: 64),
            byteLength: 16_384,
            relativePath: "States/state.bin",
            integrityStatus: .verified,
            createdAt: now
        )
        let artwork = ManagedAsset(
            id: UUID(),
            kind: .artwork,
            storageClass: .userData,
            contentSHA256: String(repeating: "f", count: 64),
            byteLength: 2_048,
            relativePath: "UserData/Artwork/cover.png",
            integrityStatus: .verified,
            createdAt: now
        )
        for asset in [sourceROM, generatedROM, patch, battery, stateAsset, artwork] {
            try repositories.assets.insertAsset(asset)
        }

        let game = Game(
            id: gameID,
            primaryTitle: "Fixture Game",
            systemFamily: "gbc",
            artworkAssetID: artwork.id,
            createdAt: now,
            modifiedAt: now
        )
        try repositories.games.insertGame(game)

        let build = Build(
            id: UUID(),
            gameID: gameID,
            system: .gameBoyColor,
            displayName: "Original",
            imageAssetID: sourceROM.id,
            imageSHA256: sourceROM.contentSHA256,
            sourceKind: .importedImage,
            isBase: true,
            region: "USA",
            revision: "Rev 0",
            baseTitle: "Fixture Game",
            hackTitle: "Fixture Plus",
            author: "Fixture Author",
            translation: "Spanish",
            status: "Beta",
            corePin: CorePin(
                descriptor: CoreDescriptor(identifier: "sameboy", version: "1.0.3"),
                pinnedAt: now
            ),
            createdAt: now,
            modifiedAt: now
        )
        try repositories.builds.insertBuild(build)

        let patchedBuild = Build(
            id: UUID(),
            gameID: gameID,
            system: .gameBoyColor,
            displayName: "v1.0",
            imageAssetID: generatedROM.id,
            imageSHA256: generatedROM.contentSHA256,
            sourceKind: .patchRecipe,
            parentBuildID: build.id,
            versionString: "1.0",
            versionSortKey: "0001.0000",
            createdAt: now,
            modifiedAt: now
        )
        try repositories.builds.insertBuild(patchedBuild)

        let profile = SaveProfile(
            id: UUID(),
            gameID: gameID,
            displayName: "Main",
            badge: "star",
            persistentSaveAssetID: battery.id,
            totalPlaytimeSeconds: 123.5,
            sessionCount: 3,
            lastPlayedAt: now,
            createdAt: now,
            modifiedAt: now
        )
        try repositories.saveProfiles.insertSaveProfile(profile)

        let state = SaveState(
            id: UUID(),
            buildID: build.id,
            saveProfileID: profile.id,
            core: CoreDescriptor(identifier: "sameboy", version: "1.0.3"),
            stateSerializationVersion: "sameboy-1.0.3",
            stateAssetID: stateAsset.id,
            kind: .manual,
            label: "Before boss",
            playtimeSeconds: 123.5,
            createdAt: now
        )
        try repositories.saveStates.insertSaveState(state)

        let recipe = PatchRecipe(
            id: UUID(),
            resultBuildID: patchedBuild.id,
            baseBuildID: build.id,
            expectedResultSHA256: generatedROM.contentSHA256,
            items: [PatchRecipeItem(position: 0, patchAssetID: patch.id, enabled: true, ignoresBaseMismatch: true)],
            createdAt: now
        )
        try repositories.patchRecipes.insertPatchRecipe(recipe)

        return Fixture(
            game: game,
            build: build,
            patchedBuild: patchedBuild,
            profile: profile,
            state: state,
            recipe: recipe,
            romAsset: sourceROM
        )
    }
}

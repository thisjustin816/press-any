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
        #expect(try repositories.assets.fetchAssets().count == 5)
        #expect(try repositories.saveStates.fetchSaveStates(buildID: fixture.build.id, saveProfileID: fixture.profile.id) == [fixture.state])
        #expect(try repositories.patchRecipes.fetchPatchRecipe(resultBuildID: fixture.patchedBuild.id) == fixture.recipe)
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
}

private enum TestFailure: Error {
    case expectedRollback
}

private struct Fixture {
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
        for asset in [sourceROM, generatedROM, patch, battery, stateAsset] {
            try repositories.assets.insertAsset(asset)
        }

        let game = Game(
            id: gameID,
            primaryTitle: "Fixture Game",
            systemFamily: "gbc",
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
            items: [PatchRecipeItem(position: 0, patchAssetID: patch.id, enabled: true)],
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

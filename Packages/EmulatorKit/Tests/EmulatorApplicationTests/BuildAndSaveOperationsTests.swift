import AssetStorage
import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import XCTest

final class BuildAndSaveOperationsTests: XCTestCase {
    func testMergingGamesKeepsTheTargetsBaseBuild() throws {
        for mode in [ReorganizationMode.move, .copy] {
            let harness = try Harness.make(twoBuilds: true)
            let second = try XCTUnwrap(harness.builds.fetchBuilds(gameID: harness.game.id).first { !$0.isBase })
            let operations = harness.buildOperations()
            let source = try operations.promoteBuild(buildID: second.id, title: "Separate", mode: .move)
            try operations.setBase(buildID: second.id, isBase: true)

            try operations.mergeGame(sourceGameID: source.id, into: harness.game.id, mode: mode)

            let builds = try harness.builds.fetchBuilds(gameID: harness.game.id)
            XCTAssertEqual(builds.count, 2)
            XCTAssertEqual(builds.filter(\.isBase).map(\.id), [harness.baseBuild.id])
        }
    }

    func testRenameBuildTrimsTheNameAndRejectsABlankName() throws {
        let harness = try Harness.make()
        let operations = harness.buildOperations()

        try operations.renameBuild(buildID: harness.baseBuild.id, displayName: "  Revision 2  ")
        XCTAssertEqual(try harness.builds.fetchBuild(id: harness.baseBuild.id)?.displayName, "Revision 2")

        XCTAssertThrowsError(try operations.renameBuild(buildID: harness.baseBuild.id, displayName: "  \n ")) {
            XCTAssertEqual($0 as? BuildOperationError, .invalidBuildName)
        }
    }

    func testDuplicateSaveProfileCopiesBytesThenDiverges() throws {
        let harness = try Harness.make()
        let source = try harness.createProfile(name: "Main", battery: Data([1, 2, 3]))
        let duplicateUseCase = DuplicateSaveProfile(
            profiles: harness.profiles,
            assets: harness.assets,
            assetStore: harness.store,
            now: { harness.now }
        )

        let copy = try duplicateUseCase.execute(sourceProfileID: source.id, name: "Testing")
        XCTAssertEqual(try harness.persistentSaveBytes(profileID: copy.id), Data([1, 2, 3]))

        let copyURL = harness.store.persistentSaveURL(profileID: copy.id)
        try harness.store.writeDataAtomically(Data([9, 9, 9]), to: copyURL)
        XCTAssertEqual(try harness.persistentSaveBytes(profileID: source.id), Data([1, 2, 3]))
        XCTAssertEqual(try harness.store.readData(at: copyURL), Data([9, 9, 9]))
        XCTAssertEqual(copy.copiedFromProfileID, source.id)
    }

    func testABadgeIsOneEmojiAndLeavesTheSaveTimeAlone() throws {
        let harness = try Harness.make()
        let profile = try harness.createProfile(name: "Main", battery: Data([1]))
        let setBadge = SetSaveProfileBadge(profiles: harness.profiles)

        for emoji in ["⭐️", "🐉", "1️⃣", "🇯🇵", "👍🏽", "🧑‍🚀"] {
            XCTAssertEqual(try setBadge.execute(profileID: profile.id, badge: emoji).badge, emoji)
        }
        for invalid in ["1", "A", "#", "⭐️⭐️", "Hi"] {
            XCTAssertThrowsError(try setBadge.execute(profileID: profile.id, badge: invalid), invalid)
        }
        XCTAssertNil(try setBadge.execute(profileID: profile.id, badge: "  ").badge, "blank clears it")
        XCTAssertEqual(try harness.profiles.fetchSaveProfile(id: profile.id)?.modifiedAt, profile.modifiedAt)
    }

    func testDeletingAProfileRemovesItsSaveAndStatesAndWhatPointedAtIt() throws {
        let harness = try Harness.make(twoBuilds: true)
        let doomed = try harness.createProfile(name: "Doomed", battery: Data([1]))
        let kept = try harness.createProfile(name: "Kept", battery: Data([2]))
        let hack = try XCTUnwrap(harness.builds.fetchBuilds(gameID: harness.game.id).first { !$0.isBase })
        try harness.buildOperations().setPreferredSaveProfile(buildID: hack.id, profileID: doomed.id)
        let states = InMemorySaveStateRepository()
        let stateURL = harness.store.stateURL(stateID: UUID())
        try harness.store.writeDataAtomically(Data([9]), to: stateURL)
        let stateAsset = ManagedAsset(
            id: UUID(),
            kind: .saveState,
            storageClass: .userData,
            contentSHA256: harness.store.hashData(Data([9])),
            byteLength: 1,
            relativePath: try harness.store.managedRelativePath(for: stateURL),
            integrityStatus: .verified,
            createdAt: harness.now
        )
        try harness.assets.insertAsset(stateAsset)
        try states.insertSaveState(SaveState(
            id: UUID(),
            buildID: hack.id,
            saveProfileID: doomed.id,
            core: CoreDescriptor(identifier: "sameboy", version: "1.0.3"),
            stateSerializationVersion: "1",
            stateAssetID: stateAsset.id,
            kind: .manual,
            playtimeSeconds: 0,
            createdAt: harness.now
        ))
        let saveAsset = try XCTUnwrap(harness.assets.fetchAsset(id: try XCTUnwrap(doomed.persistentSaveAssetID)))

        try DeleteSaveProfile(
            games: harness.games,
            builds: harness.builds,
            profiles: harness.profiles,
            states: states,
            assets: harness.assets,
            assetStore: harness.store,
            transactions: PassthroughTransactionRunner()
        ).execute(profileID: doomed.id)

        XCTAssertEqual(try harness.profiles.fetchSaveProfiles(gameID: harness.game.id).map(\.id), [kept.id])
        XCTAssertNil(try harness.games.fetchGame(id: harness.game.id)?.preferredSaveProfileID, "it was the Game's default")
        XCTAssertNil(try harness.builds.fetchBuild(id: hack.id)?.preferredSaveProfileID)
        XCTAssertEqual(try states.fetchSaveStates(saveProfileID: doomed.id), [])
        XCTAssertNil(try harness.assets.fetchAsset(id: saveAsset.id))
        XCTAssertNil(try harness.assets.fetchAsset(id: stateAsset.id))
        XCTAssertFalse(harness.store.fileExists(at: try harness.store.managedURL(relativePath: saveAsset.relativePath)))
        XCTAssertFalse(harness.store.fileExists(at: stateURL))
        XCTAssertEqual(try harness.persistentSaveBytes(profileID: kept.id), Data([2]))
    }

    func testCreateBlankProfileBecomesPreferredWhenGameHasNone() throws {
        let harness = try Harness.make()
        let useCase = CreateBlankSaveProfile(
            games: harness.games,
            profiles: harness.profiles,
            now: { harness.now }
        )
        let profile = try useCase.execute(gameID: harness.game.id, name: "Main")
        let game = try XCTUnwrap(harness.games.fetchGame(id: harness.game.id))
        XCTAssertEqual(game.preferredSaveProfileID, profile.id)
        XCTAssertNil(profile.persistentSaveAssetID)
    }

    func testPromoteBuildMovePreservesBuildIDAndReassignsOldPreferred() throws {
        let harness = try Harness.make(twoBuilds: true)
        let second = try XCTUnwrap(harness.builds.fetchBuilds(gameID: harness.game.id).first { !$0.isBase })
        try harness.setPreferredBuild(second.id)
        let operations = harness.buildOperations()

        let newGame = try operations.promoteBuild(buildID: second.id, title: "Standalone Hack", mode: .move)

        XCTAssertEqual(try harness.builds.fetchBuild(id: second.id)?.gameID, newGame.id)
        let oldGame = try XCTUnwrap(harness.games.fetchGame(id: harness.game.id))
        XCTAssertEqual(oldGame.preferredBuildID, harness.baseBuild.id)
        XCTAssertEqual(try harness.builds.fetchBuilds(gameID: harness.game.id).count, 1)
    }

    func testPromoteBuildCopyReusesImmutableROMAsset() throws {
        let harness = try Harness.make(twoBuilds: true)
        var second = try XCTUnwrap(harness.builds.fetchBuilds(gameID: harness.game.id).first { !$0.isBase })
        second.baseTitle = "Base Game"
        second.hackTitle = "Standalone Hack"
        second.author = "Hacker"
        second.translation = "Spanish"
        second.status = "Beta"
        try harness.builds.updateBuildMetadata(second)
        let newGame = try harness.buildOperations().promoteBuild(
            buildID: second.id,
            title: "Standalone Copy",
            mode: .copy
        )
        let copied = try XCTUnwrap(harness.builds.fetchBuilds(gameID: newGame.id).first)

        XCTAssertNotEqual(copied.id, second.id)
        XCTAssertEqual(copied.imageAssetID, second.imageAssetID)
        XCTAssertEqual(copied.imageSHA256, second.imageSHA256)
        XCTAssertEqual(copied.baseTitle, second.baseTitle)
        XCTAssertEqual(copied.hackTitle, second.hackTitle)
        XCTAssertEqual(copied.author, second.author)
        XCTAssertEqual(copied.translation, second.translation)
        XCTAssertEqual(copied.status, second.status)
        XCTAssertNotNil(try harness.builds.fetchBuild(id: second.id))
    }

    func testMergeGameMovePreservesBuildIDs() throws {
        let harness = try Harness.make(twoBuilds: true)
        let otherGame = try harness.createStandaloneGame(title: "Other")
        let sourceIDs = Set(try harness.builds.fetchBuilds(gameID: harness.game.id).map(\.id))

        try harness.buildOperations().mergeGame(sourceGameID: harness.game.id, into: otherGame.id, mode: .move)

        let mergedIDs = Set(try harness.builds.fetchBuilds(gameID: otherGame.id).map(\.id))
        XCTAssertTrue(sourceIDs.isSubset(of: mergedIDs))
        XCTAssertNil(try harness.games.fetchGame(id: harness.game.id))
    }

    func testAnOversizedSaveIsNotImported() throws {
        let harness = try Harness.make()
        let huge = try ImportTestFiles.sparse(
            at: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).sav"),
            byteCount: 5 * 1_048_576
        )

        XCTAssertThrowsError(try ImportBatterySave(
            games: harness.games,
            profiles: harness.profiles,
            assets: harness.assets,
            assetStore: harness.store
        ).execute(gameID: harness.game.id, sourceURL: huge, name: "Huge")) {
            XCTAssertEqual($0 as? ImportSizeError, .fileTooLarge(limit: ImportSizeLimit.batterySave.bytes))
        }
        XCTAssertEqual(try harness.profiles.fetchSaveProfiles(gameID: harness.game.id), [])
    }

    func testMarkingABaseBuildReplacesThePreviousBaseButAPatchedBuildCannotBeBase() throws {
        let harness = try Harness.make(twoBuilds: true)
        let hack = try XCTUnwrap(harness.builds.fetchBuilds(gameID: harness.game.id).first { !$0.isBase })
        let operations = harness.buildOperations()

        try operations.setBase(buildID: hack.id, isBase: true)
        let builds = try harness.builds.fetchBuilds(gameID: harness.game.id)
        XCTAssertEqual(builds.filter(\.isBase).map(\.id), [hack.id])
        XCTAssertEqual(try harness.builds.fetchBuild(id: harness.baseBuild.id)?.isBase, false)

        let patched = Build(
            id: UUID(),
            gameID: harness.game.id,
            system: hack.system,
            displayName: "Patched",
            imageAssetID: UUID(),
            imageSHA256: String(repeating: "d", count: 64),
            sourceKind: .patchRecipe,
            parentBuildID: hack.id,
            createdAt: harness.now,
            modifiedAt: harness.now
        )
        try harness.builds.insertBuild(patched)
        XCTAssertThrowsError(try operations.setBase(buildID: patched.id, isBase: true)) {
            XCTAssertEqual($0 as? BuildOperationError, .patchedBuildCannotBeBase(patched.id))
        }
    }

    func testPromotingBringsTheChosenProfilesAndArtworkAndRecordsLineage() throws {
        let harness = try Harness.make(twoBuilds: true)
        let hack = try XCTUnwrap(harness.builds.fetchBuilds(gameID: harness.game.id).first { !$0.isBase })
        let main = try harness.createProfile(name: "Main", battery: Data([1]))
        let hackSave = try harness.createProfile(name: "Hack Run", battery: Data([2]))
        _ = try harness.setArtwork(Data([7, 7]), gameID: harness.game.id)
        let operations = harness.buildOperations()
        try operations.setPreferredSaveProfile(buildID: hack.id, profileID: hackSave.id)

        let suggested = try operations.suggestedCarryOver(promoting: hack.id)
        XCTAssertEqual(suggested, GameCarryOver(artwork: true, saveProfileIDs: [hackSave.id]), "the profile the Build plays")
        let newGame = try operations.promoteBuild(buildID: hack.id, title: "Hack", mode: .move, carryOver: suggested)

        XCTAssertEqual(newGame.lineage, GameLineage(sourceGameID: harness.game.id, sourceTitle: "Test"))
        let copies = try harness.profiles.fetchSaveProfiles(gameID: newGame.id)
        XCTAssertEqual(copies.map(\.displayName), ["Hack Run"])
        let copy = try XCTUnwrap(copies.first)
        XCTAssertEqual(try harness.persistentSaveBytes(profileID: copy.id), Data([2]))
        XCTAssertEqual(try harness.builds.fetchBuild(id: hack.id)?.preferredSaveProfileID, copy.id, "the Build plays the copy")
        XCTAssertEqual(try harness.games.fetchGame(id: newGame.id)?.preferredSaveProfileID, copy.id)
        XCTAssertEqual(Set(try harness.profiles.fetchSaveProfiles(gameID: harness.game.id).map(\.id)), [main.id, hackSave.id])

        let promoted = try XCTUnwrap(harness.games.fetchGame(id: newGame.id))
        XCTAssertNotEqual(promoted.artworkAssetID, try harness.games.fetchGame(id: harness.game.id)?.artworkAssetID, "its own copy")
        XCTAssertEqual(try harness.artworkBytes(gameID: newGame.id), Data([7, 7]))
        _ = try GameArtwork(games: harness.games, assets: harness.assets, assetStore: harness.store).remove(gameID: newGame.id)
        XCTAssertEqual(try harness.artworkBytes(gameID: harness.game.id), Data([7, 7]), "removing one leaves the other")
    }

    func testPromotingWithNothingCarriedLeavesTheBuildWithoutAnotherGamesProfile() throws {
        let harness = try Harness.make(twoBuilds: true)
        let hack = try XCTUnwrap(harness.builds.fetchBuilds(gameID: harness.game.id).first { !$0.isBase })
        let save = try harness.createProfile(name: "Main", battery: Data([1]))
        let operations = harness.buildOperations()
        try operations.setPreferredSaveProfile(buildID: hack.id, profileID: save.id)

        let newGame = try operations.promoteBuild(buildID: hack.id, title: "Hack", mode: .move)

        XCTAssertNil(try harness.builds.fetchBuild(id: hack.id)?.preferredSaveProfileID)
        XCTAssertEqual(try harness.profiles.fetchSaveProfiles(gameID: newGame.id), [])
        XCTAssertNil(newGame.artworkAssetID)
    }

    func testPromotingAGamesOnlyBuildRenamesItWithoutLineage() throws {
        let harness = try Harness.make()
        let newGame = try harness.buildOperations().promoteBuild(buildID: harness.baseBuild.id, title: "Renamed", mode: .move)
        XCTAssertNil(newGame.lineage)
        XCTAssertNil(try harness.games.fetchGame(id: harness.game.id))
    }

    func testACopyMergeCopiesTheChosenProfilesAndArtwork() throws {
        let harness = try Harness.make()
        let other = try harness.createStandaloneGame(title: "Other")
        let otherBuild = try XCTUnwrap(harness.builds.fetchBuilds(gameID: other.id).first)
        let played = try harness.createProfile(name: "Played", battery: Data([3]), gameID: other.id)
        let spare = try harness.createProfile(name: "Spare", battery: Data([4]), gameID: other.id)
        _ = try harness.setArtwork(Data([5]), gameID: other.id)
        let operations = harness.buildOperations()
        try operations.setPreferredSaveProfile(buildID: otherBuild.id, profileID: played.id)
        var otherGame = try XCTUnwrap(harness.games.fetchGame(id: other.id))
        otherGame.preferredSaveProfileID = nil
        try harness.games.updateGame(otherGame)

        let suggested = try operations.suggestedCarryOver(merging: other.id, into: harness.game.id)
        XCTAssertEqual(suggested, GameCarryOver(artwork: true, saveProfileIDs: [played.id]))
        try operations.mergeGame(sourceGameID: other.id, into: harness.game.id, mode: .copy, carryOver: suggested)

        let copiedBuild = try XCTUnwrap(harness.builds.fetchBuilds(gameID: harness.game.id).first { $0.imageSHA256 == otherBuild.imageSHA256 })
        let copies = try harness.profiles.fetchSaveProfiles(gameID: harness.game.id)
        XCTAssertEqual(copies.map(\.displayName), ["Played"])
        XCTAssertEqual(copiedBuild.preferredSaveProfileID, copies.first?.id)
        XCTAssertEqual(try harness.artworkBytes(gameID: harness.game.id), Data([5]))
        XCTAssertEqual(Set(try harness.profiles.fetchSaveProfiles(gameID: other.id).map(\.id)), [played.id, spare.id], "the source is left as it was")
    }

    func testAMoveMergeUsesTheSourceArtworkOnlyWhenAsked() throws {
        let harness = try Harness.make()
        let target = try harness.setArtwork(Data([1]), gameID: harness.game.id)
        let first = try harness.createStandaloneGame(title: "First")
        _ = try harness.setArtwork(Data([2]), gameID: first.id)
        let operations = harness.buildOperations()

        try operations.mergeGame(sourceGameID: first.id, into: harness.game.id, mode: .move)
        XCTAssertEqual(try harness.artworkBytes(gameID: harness.game.id), Data([1]))

        let second = try harness.createStandaloneGame(title: "Second", imageSHA256: String(repeating: "e", count: 64))
        let secondArt = try XCTUnwrap(harness.setArtwork(Data([3]), gameID: second.id).artworkAssetID)
        try operations.mergeGame(
            sourceGameID: second.id,
            into: harness.game.id,
            mode: .move,
            carryOver: GameCarryOver(artwork: true, saveProfileIDs: [])
        )
        XCTAssertEqual(try harness.games.fetchGame(id: harness.game.id)?.artworkAssetID, secondArt)
        XCTAssertNil(try harness.assets.fetchAsset(id: try XCTUnwrap(target.artworkAssetID)), "the replaced artwork is removed")
    }

    func testPreferredProfileResolverUsesBuildThenGameThenOldest() throws {
        let harness = try Harness.make()
        let create = CreateBlankSaveProfile(games: harness.games, profiles: harness.profiles, now: { harness.now })
        let main = try create.execute(gameID: harness.game.id, name: "Main")
        let testing = try create.execute(gameID: harness.game.id, name: "Testing")
        try harness.buildOperations().setPreferredSaveProfile(buildID: harness.baseBuild.id, profileID: testing.id)
        let resolver = ResolvePreferredSaveProfile(
            games: harness.games,
            builds: harness.builds,
            profiles: harness.profiles,
            createBlank: create
        )

        XCTAssertEqual(try resolver.execute(gameID: harness.game.id, buildID: harness.baseBuild.id).id, testing.id)
        try harness.buildOperations().setPreferredSaveProfile(buildID: harness.baseBuild.id, profileID: nil)
        XCTAssertEqual(try resolver.execute(gameID: harness.game.id, buildID: harness.baseBuild.id).id, main.id)
    }
}

private struct Harness {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let game: Game
    let baseBuild: Build
    let games: InMemoryGameRepository
    let builds: InMemoryBuildRepository
    let profiles: InMemorySaveProfileRepository
    let states = InMemorySaveStateRepository()
    let assets: InMemoryAssetRepository
    let store: ManagedFileStore

    static func make(twoBuilds: Bool = false) throws -> Harness {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let game = Game(id: UUID(), primaryTitle: "Test", systemFamily: "gameboy", createdAt: now, modifiedAt: now)
        let games = InMemoryGameRepository([game])
        let profiles = InMemorySaveProfileRepository()
        let assets = InMemoryAssetRepository()
        let store = try ManagedFileStore(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent("emulatorkit-app-tests-\(UUID())", isDirectory: true))
        let imageAssetID = UUID()
        let base = Build(
            id: UUID(),
            gameID: game.id,
            system: .gameBoyColor,
            displayName: "Original",
            imageAssetID: imageAssetID,
            imageSHA256: String(repeating: "a", count: 64),
            sourceKind: .importedImage,
            isBase: true,
            createdAt: now,
            modifiedAt: now
        )
        var initial = [base]
        if twoBuilds {
            initial.append(Build(
                id: UUID(),
                gameID: game.id,
                system: .gameBoyColor,
                displayName: "Hack v1",
                imageAssetID: imageAssetID,
                imageSHA256: String(repeating: "b", count: 64),
                sourceKind: .importedImage,
                parentBuildID: base.id,
                createdAt: now.addingTimeInterval(1),
                modifiedAt: now.addingTimeInterval(1)
            ))
        }
        let builds = InMemoryBuildRepository(initial)
        var preferred = game
        preferred.preferredBuildID = base.id
        try games.updateGame(preferred)
        return Harness(game: preferred, baseBuild: base, games: games, builds: builds, profiles: profiles, assets: assets, store: store)
    }

    func buildOperations() -> BuildOperations {
        BuildOperations(
            games: games,
            builds: builds,
            profiles: profiles,
            states: states,
            recipes: InMemoryPatchRecipeRepository(),
            assets: assets,
            assetStore: store,
            now: { now }
        )
    }

    func setPreferredBuild(_ id: UUID) throws {
        try buildOperations().setPreferredBuild(gameID: game.id, buildID: id)
    }

    func createProfile(name: String, battery: Data, gameID: UUID? = nil) throws -> SaveProfile {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).sav")
        try battery.write(to: source)
        return try ImportBatterySave(
            games: games,
            profiles: profiles,
            assets: assets,
            assetStore: store,
            now: { now }
        ).execute(gameID: gameID ?? game.id, sourceURL: source, name: name)
    }

    func setArtwork(_ bytes: Data, gameID: UUID) throws -> Game {
        // The test bytes aren't images, so they are stored as given.
        try GameArtwork(games: games, assets: assets, assetStore: store, prepareImage: { ($0, $1) }, now: { now })
            .set(gameID: gameID, imageData: bytes, fileExtension: "png")
    }

    func artworkBytes(gameID: UUID) throws -> Data? {
        guard let assetID = try games.fetchGame(id: gameID)?.artworkAssetID,
              let asset = try assets.fetchAsset(id: assetID) else { return nil }
        return try store.readData(at: store.managedURL(relativePath: asset.relativePath))
    }

    func persistentSaveBytes(profileID: UUID) throws -> Data? {
        guard let profile = try profiles.fetchSaveProfile(id: profileID),
              let assetID = profile.persistentSaveAssetID,
              let asset = try assets.fetchAsset(id: assetID) else { return nil }
        return try store.readData(at: store.managedURL(relativePath: asset.relativePath))
    }

    func createStandaloneGame(title: String, imageSHA256: String = String(repeating: "c", count: 64)) throws -> Game {
        let newGame = Game(id: UUID(), primaryTitle: title, systemFamily: "gameboy", createdAt: now, modifiedAt: now)
        try games.insertGame(newGame)
        let build = Build(
            id: UUID(),
            gameID: newGame.id,
            system: .gameBoy,
            displayName: "Original",
            imageAssetID: UUID(),
            imageSHA256: imageSHA256,
            sourceKind: .importedImage,
            isBase: true,
            createdAt: now,
            modifiedAt: now
        )
        try builds.insertBuild(build)
        var updated = newGame
        updated.preferredBuildID = build.id
        try games.updateGame(updated)
        return updated
    }
}

extension BuildAndSaveOperationsTests {
    func testPreferredLaunchContextPersistsInitialBaseBuildAndCreatesMainProfile() throws {
        let harness = try Harness.make(twoBuilds: true)
        var game = try XCTUnwrap(harness.games.fetchGame(id: harness.game.id))
        game.preferredBuildID = nil
        game.preferredSaveProfileID = nil
        try harness.games.updateGame(game)

        let profileID = UUID()
        let resolver = ResolvePreferredLaunchContext(
            games: harness.games,
            builds: harness.builds,
            profiles: harness.profiles,
            now: { harness.now },
            makeID: { profileID }
        )
        let context = try resolver.execute(gameID: game.id)

        XCTAssertEqual(context.buildID, harness.baseBuild.id)
        XCTAssertEqual(context.saveProfileID, profileID)
        XCTAssertEqual(try harness.games.fetchGame(id: game.id)?.preferredBuildID, harness.baseBuild.id)
        XCTAssertEqual(try harness.games.fetchGame(id: game.id)?.preferredSaveProfileID, profileID)
    }
}

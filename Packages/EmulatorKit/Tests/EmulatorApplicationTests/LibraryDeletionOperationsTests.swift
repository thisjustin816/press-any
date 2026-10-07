import AssetStorage
import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import Testing
import XCTest

final class LibraryDeletionOperationsTests: XCTestCase {
    func testDeletingRestoringAndPurgingKeepsInMemoryDeclarationsWithTheirBuilds() throws {
        let library = try Library()
        let a = library.base.id, b = library.patched.id
        let declaration = BuildSaveDeclaration(between: a, and: b, compatibility: .sharesSaves)
        try library.builds.setSaveCompatibility(between: a, and: b, compatibility: .sharesSaves)
        let deleted = try library.operations.delete(library.operations.planBuildDeletion(buildID: b))
        XCTAssertTrue(try library.builds.fetchSaveDeclarations(buildID: a).isEmpty)
        try library.operations.restore(deletionID: deleted.id)
        XCTAssertEqual(try library.builds.fetchSaveDeclarations(buildID: b), [declaration])
        let again = try library.operations.delete(library.operations.planBuildDeletion(buildID: b))
        _ = try library.deletions.purgeDeletion(id: again.id, at: library.clock.now)
        XCTAssertTrue(try library.builds.fetchSaveDeclarations(buildID: a).isEmpty)
        try library.builds.insertBuild(library.patched)
        XCTAssertTrue(try library.builds.fetchSaveDeclarations(buildID: b).isEmpty)
    }

    func testDeletingABaseTakesItsPatchedBuildsAndAnEmptiedGame() throws {
        let library = try Library()
        let plan = try library.operations.planBuildDeletion(buildID: library.base.id)

        XCTAssertEqual(plan.dependentBuilds.map(\.id), [library.patched.id])
        XCTAssertEqual(plan.emptiedGames.map(\.id), [library.game.id])
        XCTAssertEqual(Set(plan.records.buildIDs), [library.base.id, library.patched.id])
        XCTAssertEqual(plan.records.gameIDs, [library.game.id])
        XCTAssertEqual(plan.records.saveProfileIDs, [library.profile.id])
        XCTAssertEqual(plan.records.saveStateIDs, [library.state.id])

        try library.operations.delete(plan)
        XCTAssertNil(try library.games.fetchGame(id: library.game.id))
        XCTAssertNil(try library.builds.fetchBuild(id: library.patched.id))
    }

    func testDeletingOneOfSeveralBuildsTakesOnlyItsOwnStates() throws {
        let library = try Library()
        let plan = try library.operations.planBuildDeletion(buildID: library.patched.id)

        XCTAssertEqual(plan.records.buildIDs, [library.patched.id])
        XCTAssertTrue(plan.emptiedGames.isEmpty)
        XCTAssertTrue(plan.records.saveStateIDs.isEmpty, "the state belongs to the base")
    }

    func testAGameCantGoWhileAnotherGamesPatchIsBuiltFromIt() throws {
        let library = try Library()
        try library.builds.moveBuild(id: library.patched.id, toGameID: library.otherGame.id)

        XCTAssertThrowsError(try library.operations.planGameDeletion(gameID: library.game.id)) {
            XCTAssertEqual($0 as? LibraryDeletionError, .dependentBuildsInOtherGames([library.patched.id]))
        }
    }

    func testDeletingClearsWhatPreferredIt() throws {
        let library = try Library()
        var game = library.game
        game.preferredBuildID = library.patched.id
        game.preferredSaveProfileID = library.profile.id
        try library.games.updateGame(game)
        var base = library.base
        base.preferredSaveProfileID = library.profile.id
        try library.builds.updateBuildMetadata(base)

        try library.operations.delete(library.operations.planBuildDeletion(buildID: library.patched.id))
        XCTAssertNil(try library.games.fetchGame(id: game.id)?.preferredBuildID)

        try library.operations.delete(library.operations.planProfileDeletion(profileID: library.profile.id))
        XCTAssertNil(try library.games.fetchGame(id: game.id)?.preferredSaveProfileID)
        XCTAssertNil(try library.builds.fetchBuild(id: base.id)?.preferredSaveProfileID)
    }

    func testRestoreWaitsForWhatItBelongsTo() throws {
        let library = try Library()
        let patched = try library.operations.delete(library.operations.planBuildDeletion(buildID: library.patched.id))
        let profile = try library.operations.delete(library.operations.planProfileDeletion(profileID: library.profile.id))
        let game = try library.operations.delete(library.operations.planGameDeletion(gameID: library.game.id))

        XCTAssertThrowsError(try library.operations.restore(deletionID: profile.id)) {
            XCTAssertEqual($0 as? LibraryDeletionError, .gameIsDeleted(library.game.id))
        }
        try library.operations.restore(deletionID: game.id)
        try library.operations.restore(deletionID: profile.id)
        XCTAssertNotNil(try library.saveProfiles.fetchSaveProfile(id: library.profile.id))

        // Another Build keeps the Game live once the base goes.
        try library.builds.insertBuild(Build(
            id: UUID(), gameID: library.game.id, system: .gameBoy, displayName: "Rev 1", imageAssetID: library.base.imageAssetID,
            imageSHA256: String(repeating: "c", count: 64), sourceKind: .importedImage,
            createdAt: library.base.createdAt, modifiedAt: library.base.createdAt
        ))
        let base = try library.operations.delete(library.operations.planBuildDeletion(buildID: library.base.id))
        XCTAssertThrowsError(try library.operations.restore(deletionID: patched.id)) {
            XCTAssertEqual($0 as? LibraryDeletionError, .baseBuildIsDeleted(library.base.id))
        }
        try library.operations.restore(deletionID: base.id)
        try library.operations.restore(deletionID: patched.id)
        XCTAssertTrue(Set(try library.builds.fetchBuilds(gameID: library.game.id).map(\.id)).isSuperset(of: [library.base.id, library.patched.id]))
    }

    func testDeletingOneStateTakesOnlyThatState() throws {
        let library = try Library()
        let plan = try library.operations.planStateDeletion(stateID: library.state.id)

        XCTAssertEqual(plan.kind, .saveState)
        XCTAssertEqual(plan.title, "Save State")
        XCTAssertEqual(plan.gameID, library.game.id)
        XCTAssertEqual(plan.records, LibraryRecordSet(saveStateIDs: [library.state.id]))

        let deleted = try library.operations.delete(plan)
        XCTAssertTrue(try library.states.fetchSaveStates(saveProfileID: library.profile.id).isEmpty)
        XCTAssertNotNil(try library.saveProfiles.fetchSaveProfile(id: library.profile.id), "the profile stays")
        XCTAssertThrowsError(try library.operations.planStateDeletion(stateID: library.state.id)) {
            XCTAssertEqual($0 as? LibraryDeletionError, .saveStateNotFound(library.state.id))
        }

        try library.operations.restore(deletionID: deleted.id)
        XCTAssertEqual(try library.states.fetchSaveState(id: library.state.id), library.state)
    }

    func testAStateComesBackOnlyToItsProfileAndBuild() throws {
        let library = try Library()
        let state = try library.operations.delete(library.operations.planStateDeletion(stateID: library.state.id))
        let profile = try library.operations.delete(library.operations.planProfileDeletion(profileID: library.profile.id))

        XCTAssertThrowsError(try library.operations.restore(deletionID: state.id)) {
            XCTAssertEqual($0 as? LibraryDeletionError, .saveProfileIsDeleted(library.profile.id))
        }
        try library.operations.restore(deletionID: profile.id)
        try library.operations.restore(deletionID: state.id)

        let onPatched = try library.addState(onBuild: library.patched.id)
        let patchedState = try library.operations.delete(library.operations.planStateDeletion(stateID: onPatched.id))
        try library.operations.delete(library.operations.planBuildDeletion(buildID: library.patched.id))
        XCTAssertThrowsError(try library.operations.restore(deletionID: patchedState.id)) {
            XCTAssertEqual($0 as? LibraryDeletionError, .buildIsDeleted(library.patched.id))
        }
    }

    func testPurgingAProfileTakesItsStatesDeletedElsewhere() throws {
        let library = try Library()
        let alone = try library.operations.delete(library.operations.planStateDeletion(stateID: library.state.id))
        let onPatched = try library.addState(onBuild: library.patched.id)
        let patched = try library.operations.delete(library.operations.planBuildDeletion(buildID: library.patched.id))
        XCTAssertEqual(patched.records.saveStateIDs, [onPatched.id])
        let profile = try library.operations.delete(library.operations.planProfileDeletion(profileID: library.profile.id))

        try library.operations.purge(deletionID: profile.id)

        let remaining = try library.operations.recentlyDeleted()
        XCTAssertEqual(remaining.map(\.id), [patched.id], "the lone state's deletion goes; the Build's stays")
        XCTAssertEqual(remaining.first?.records, LibraryRecordSet(buildIDs: [library.patched.id]))
        XCTAssertFalse(remaining.contains { $0.id == alone.id })
        XCTAssertEqual(
            Set(try library.deletions.fetchTombstones().map(\.recordID)),
            [library.profile.id, library.state.id, onPatched.id]
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.stateFile.path))
    }

    func testOnlyDeletionsPastThirtyDaysArePurgedWithTheirFiles() throws {
        let library = try Library()
        let old = try library.operations.delete(library.operations.planProfileDeletion(profileID: library.profile.id))
        library.clock.advance(by: LibraryDeletion.retention - 60)
        let recent = try library.operations.delete(library.operations.planBuildDeletion(buildID: library.patched.id))
        library.clock.advance(by: 120)

        XCTAssertEqual(try library.operations.purgeExpired(), 1)

        XCTAssertEqual(try library.operations.recentlyDeleted().map(\.id), [recent.id])
        XCTAssertEqual(Set(try library.deletions.fetchTombstones().map(\.recordID)), Set(old.records.all.map(\.id)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.stateFile.path), "the state's file goes with it")
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.romFile.path), "the ROM is still used")
    }
}

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_700_000_000)
    var now: Date { lock.withLock { value } }
    func advance(by interval: TimeInterval) { lock.withLock { value += interval } }
}

/// A Game with a Base Build, a Build patched from it, a profile and a state on the base, and an
/// empty second Game.
private struct Library {
    let clock = Clock()
    let games: InMemoryGameRepository
    let builds: InMemoryBuildRepository
    let saveProfiles = InMemorySaveProfileRepository()
    let states = InMemorySaveStateRepository()
    let recipes = InMemoryPatchRecipeRepository()
    let assets = InMemoryAssetRepository()
    let deletions: InMemoryLibraryDeletionRepository
    let store: ManagedFileStore
    let game: Game
    let otherGame: Game
    let base: Build
    let patched: Build
    let profile: SaveProfile
    let state: SaveState
    let romFile: URL
    let stateFile: URL

    init() throws {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let store = try ManagedFileStore(rootURL: FileManager.default.temporaryDirectory.appendingPathComponent("deletion-tests-\(UUID())", isDirectory: true))
        let assets = assets
        self.store = store
        game = Game(id: UUID(), primaryTitle: "Test", systemFamily: "gameboy", createdAt: created, modifiedAt: created)
        otherGame = Game(id: UUID(), primaryTitle: "Other", systemFamily: "gameboy", createdAt: created, modifiedAt: created)
        games = InMemoryGameRepository([game, otherGame])

        func asset(_ kind: ManagedAssetKind, _ path: String) throws -> (ManagedAsset, URL) {
            let url = try store.managedURL(relativePath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([1]).write(to: url)
            let value = ManagedAsset(
                id: UUID(), kind: kind, storageClass: .userData, contentSHA256: String(repeating: "a", count: 64),
                byteLength: 1, relativePath: path, createdAt: created
            )
            try assets.insertAsset(value)
            return (value, url)
        }
        let (rom, romURL) = try asset(.sourceImage, "SourceROMs/test.gb")
        let (generated, _) = try asset(.generatedImage, "GeneratedROMs/test.gb")
        let (stateAsset, stateURL) = try asset(.saveState, "States/test.state")
        romFile = romURL
        stateFile = stateURL

        base = Build(
            id: UUID(), gameID: game.id, system: .gameBoy, displayName: "Original", imageAssetID: rom.id,
            imageSHA256: String(repeating: "a", count: 64), sourceKind: .importedImage, isBase: true,
            createdAt: created, modifiedAt: created
        )
        patched = Build(
            id: UUID(), gameID: game.id, system: .gameBoy, displayName: "Hack", imageAssetID: generated.id,
            imageSHA256: String(repeating: "b", count: 64), sourceKind: .patchRecipe, parentBuildID: base.id,
            createdAt: created.addingTimeInterval(1), modifiedAt: created
        )
        builds = InMemoryBuildRepository([base, patched])
        try recipes.insertPatchRecipe(PatchRecipe(
            id: UUID(), resultBuildID: patched.id, baseBuildID: base.id,
            expectedResultSHA256: patched.imageSHA256, items: [], createdAt: created
        ))
        profile = SaveProfile(id: UUID(), gameID: game.id, displayName: "Main", createdAt: created, modifiedAt: created)
        try saveProfiles.insertSaveProfile(profile)
        state = SaveState(
            id: UUID(), buildID: base.id, saveProfileID: profile.id,
            core: CoreDescriptor(identifier: "sameboy", version: "1.0.3"), stateSerializationVersion: "1",
            stateAssetID: stateAsset.id, kind: .manual, playtimeSeconds: 0, createdAt: created
        )
        try states.insertSaveState(state)
        deletions = InMemoryLibraryDeletionRepository(
            games: games, builds: builds, profiles: saveProfiles, states: states, recipes: recipes, assets: assets
        )
    }

    /// A manual state on the Build with the profile, and its own file.
    func addState(onBuild buildID: UUID) throws -> SaveState {
        let path = "States/\(UUID().uuidString).state"
        let url = try store.managedURL(relativePath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([2]).write(to: url)
        let asset = ManagedAsset(
            id: UUID(), kind: .saveState, storageClass: .userData, contentSHA256: String(repeating: "d", count: 64),
            byteLength: 1, relativePath: path, createdAt: state.createdAt
        )
        try assets.insertAsset(asset)
        let added = SaveState(
            id: UUID(), buildID: buildID, saveProfileID: profile.id, core: state.core,
            stateSerializationVersion: state.stateSerializationVersion, stateAssetID: asset.id,
            kind: .manual, playtimeSeconds: 0, createdAt: state.createdAt.addingTimeInterval(1)
        )
        try states.insertSaveState(added)
        return added
    }

    var operations: LibraryDeletionOperations {
        let clock = clock
        return LibraryDeletionOperations(
            games: games, builds: builds, profiles: saveProfiles, states: states, recipes: recipes,
            deletions: deletions, assetStore: store, transactions: PassthroughTransactionRunner(), now: { clock.now }
        )
    }
}

@Suite("In-memory metadata lifecycle")
struct InMemoryMetadataLifecycleTests {
    @Test("deleted owners hide provenance, restoration recovers it, and purge removes it")
    func deletion() throws {
        let library = try Library()
        let title = MetadataProvenance(field: .title, source: .filename, confidence: .low,
            providedValue: "Offered", recordedAt: library.clock.now)
        let name = MetadataProvenance(field: .displayName, source: .patch, confidence: .high,
            providedValue: "Patched", recordedAt: library.clock.now)
        try library.games.saveMetadataProvenance(title, ownerID: library.game.id)
        try library.builds.saveMetadataProvenance(name, ownerID: library.patched.id)
        let deleted = try library.operations.delete(library.operations.planGameDeletion(gameID: library.game.id))
        #expect(try library.games.fetchMetadataProvenance(ownerID: library.game.id).isEmpty)
        #expect(try library.builds.fetchMetadataProvenance(ownerID: library.patched.id).isEmpty)
        try library.operations.restore(deletionID: deleted.id)
        #expect(try library.games.fetchMetadataProvenance(ownerID: library.game.id) == [title])
        #expect(try library.builds.fetchMetadataProvenance(ownerID: library.patched.id) == [name])
        let again = try library.operations.delete(library.operations.planGameDeletion(gameID: library.game.id))
        _ = try library.deletions.purgeDeletion(id: again.id, at: library.clock.now)
        try library.games.insertGame(library.game)
        try library.builds.insertBuild(library.patched)
        #expect(try library.games.fetchMetadataProvenance(ownerID: library.game.id).isEmpty)
        #expect(try library.builds.fetchMetadataProvenance(ownerID: library.patched.id).isEmpty)
    }
}

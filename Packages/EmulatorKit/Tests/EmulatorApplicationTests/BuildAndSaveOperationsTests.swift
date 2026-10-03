import AssetStorage
import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import XCTest

final class BuildAndSaveOperationsTests: XCTestCase {
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
        let second = try XCTUnwrap(harness.builds.fetchBuilds(gameID: harness.game.id).first { !$0.isBase })
        let newGame = try harness.buildOperations().promoteBuild(
            buildID: second.id,
            title: "Standalone Copy",
            mode: .copy
        )
        let copied = try XCTUnwrap(harness.builds.fetchBuilds(gameID: newGame.id).first)

        XCTAssertNotEqual(copied.id, second.id)
        XCTAssertEqual(copied.imageAssetID, second.imageAssetID)
        XCTAssertEqual(copied.imageSHA256, second.imageSHA256)
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
        BuildOperations(games: games, builds: builds, profiles: profiles, now: { now })
    }

    func setPreferredBuild(_ id: UUID) throws {
        try buildOperations().setPreferredBuild(gameID: game.id, buildID: id)
    }

    func createProfile(name: String, battery: Data) throws -> SaveProfile {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).sav")
        try battery.write(to: source)
        return try ImportBatterySave(
            games: games,
            profiles: profiles,
            assets: assets,
            assetStore: store,
            now: { now }
        ).execute(gameID: game.id, sourceURL: source, name: name)
    }

    func persistentSaveBytes(profileID: UUID) throws -> Data? {
        guard let profile = try profiles.fetchSaveProfile(id: profileID),
              let assetID = profile.persistentSaveAssetID,
              let asset = try assets.fetchAsset(id: assetID) else { return nil }
        return try store.readData(at: store.managedURL(relativePath: asset.relativePath))
    }

    func createStandaloneGame(title: String) throws -> Game {
        let newGame = Game(id: UUID(), primaryTitle: title, systemFamily: "gameboy", createdAt: now, modifiedAt: now)
        try games.insertGame(newGame)
        let build = Build(
            id: UUID(),
            gameID: newGame.id,
            system: .gameBoy,
            displayName: "Original",
            imageAssetID: UUID(),
            imageSHA256: String(repeating: "c", count: 64),
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

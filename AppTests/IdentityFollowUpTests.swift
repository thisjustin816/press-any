import EmulatorApplication
import EmulatorDomain
import Foundation
import GameIdentity
import Importing
import XCTest
@testable import PressAny

@MainActor
final class IdentityFollowUpTests: XCTestCase {
    func testEditingBatchSuggestionBackToCurrentTitleProtectsIt() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let japan = try fixture.review(1).commit()
        let usa = try fixture.review(0)
        usa.acceptProposedTitle = false
        _ = try usa.commit()
        let model = NameReviewViewModel(games: fixture.container.repositories.games, builds: fixture.container.repositories.builds,
            assets: fixture.container.repositories.assets, index: fixture.index, preference: ReleasePreference(),
            operations: fixture.container.buildOperations)
        model.load()
        XCTAssertEqual(model.gameItems.count, 1)
        model.gameItems[0].title = japan.game.primaryTitle
        XCTAssertTrue(model.apply())
        let game = try XCTUnwrap(fixture.container.repositories.games.fetchGame(id: japan.game.id))
        XCTAssertEqual(game.primaryTitle, japan.game.primaryTitle)
        XCTAssertTrue(game.hasPlayerTitle)
    }

    func testBatchGameTitlesAcceptEditAndSkipWithoutChangingPreferredBuilds() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let japan = try fixture.review(1).commit()
        try fixture.container.buildOperations.renameGame(gameID: japan.game.id, title: japan.game.primaryTitle)
        let usaReview = try fixture.review(0)
        XCTAssertNil(usaReview.proposedTitle, "preexisting or player titles stay protected during import")
        let usa = try usaReview.commit()
        let edited = try fixture.container.buildOperations.promoteBuild(buildID: usa.build.id, title: "Edited Regional", mode: .copy)
        let skipped = try fixture.container.buildOperations.promoteBuild(buildID: usa.build.id, title: "Skipped Regional", mode: .copy)
        let before = try fixture.container.repositories.games.fetchGames()
        let model = NameReviewViewModel(games: fixture.container.repositories.games, builds: fixture.container.repositories.builds,
            assets: fixture.container.repositories.assets, index: fixture.index, preference: ReleasePreference(),
            operations: fixture.container.buildOperations)
        model.load()
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.gameItems.count, 3)
        XCTAssertEqual(try fixture.container.repositories.games.fetchGames(), before)
        let editedIndex = try XCTUnwrap(model.gameItems.firstIndex { $0.id == edited.id })
        model.gameItems[editedIndex].title = "  My Crystal  "
        let skippedIndex = try XCTUnwrap(model.gameItems.firstIndex { $0.id == skipped.id })
        model.gameItems[skippedIndex].accepted = false
        for index in model.buildItems.indices { model.buildItems[index].accepted = false }
        XCTAssertTrue(model.apply())

        let accepted = try XCTUnwrap(fixture.container.repositories.games.fetchGame(id: japan.game.id))
        XCTAssertEqual(accepted.primaryTitle, "Crystal")
        XCTAssertTrue(accepted.aliases.contains(japan.game.primaryTitle))
        XCTAssertFalse(accepted.hasPlayerTitle)
        let player = try XCTUnwrap(fixture.container.repositories.games.fetchGame(id: edited.id))
        XCTAssertEqual(player.primaryTitle, "My Crystal")
        XCTAssertTrue(player.aliases.contains(edited.primaryTitle))
        XCTAssertTrue(player.hasPlayerTitle)
        XCTAssertEqual(try fixture.container.repositories.games.fetchGame(id: skipped.id), before.first { $0.id == skipped.id })
        for game in before {
            XCTAssertEqual(try fixture.container.repositories.games.fetchGame(id: game.id)?.preferredBuildID, game.preferredBuildID)
        }
        let later = try fixture.review(2, preference: ReleasePreference(regions: ["Japan", "USA", "Europe"]))
        later.destination = .existing(accepted.id)
        later.destinationChanged()
        XCTAssertEqual(later.proposedTitle, "Pocket Monsters Crystal", "accepting opts into later regional proposals")
    }

    func testBetterRegionProposesTitleAndPreferredOnlyDuringReview() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let japan = try fixture.review(1).commit()
        let usa = try fixture.review(0)
        XCTAssertEqual(usa.destination, .existing(japan.game.id))
        XCTAssertEqual(usa.proposedTitle, "Crystal")
        XCTAssertTrue(usa.markAsPreferred)
        XCTAssertEqual(try fixture.container.repositories.games.fetchGame(id: japan.game.id)?.primaryTitle, "Pocket Monsters Crystal")
        usa.acceptProposedTitle = false
        usa.markAsPreferred = false
        let declined = try usa.commit()
        XCTAssertEqual(declined.game.primaryTitle, "Pocket Monsters Crystal")
        XCTAssertEqual(declined.game.preferredBuildID, japan.build.id)
    }

    func testConfirmedRegionalTitleAndPreferredAndPlayerTitleProtection() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let japan = try fixture.review(1).commit()
        let usa = try fixture.review(0)
        let result = try usa.commit()
        XCTAssertEqual(result.game.primaryTitle, "Crystal")
        XCTAssertEqual(result.game.preferredBuildID, result.build.id)
        let europe = try fixture.review(2)
        XCTAssertFalse(europe.markAsPreferred, "Europe is below USA")
        XCTAssertNil(europe.proposedTitle)
        try fixture.container.buildOperations.renameGame(gameID: japan.game.id, title: "My Crystal")
        let renamed = try fixture.review(2)
        XCTAssertNil(renamed.proposedTitle)
        let imported = try renamed.commit()
        XCTAssertEqual(imported.game.primaryTitle, "My Crystal")
    }

    func testOrderAndManualRolesSurviveDestinationChanges() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let usa = try fixture.review(0).commit()
        let japan = try fixture.review(1, preference: ReleasePreference(regions: ["Japan", "USA", "Europe"], languages: ["Ja", "En"]))
        XCTAssertEqual(japan.proposedTitle, "Pocket Monsters Crystal")
        XCTAssertTrue(japan.markAsPreferred)
        japan.markAsPreferred = false
        japan.destination = .newGame
        japan.destinationChanged()
        japan.destination = .existing(usa.game.id)
        japan.destinationChanged()
        XCTAssertFalse(japan.markAsPreferred)
        try ReleasePreferenceStore(store: fixture.container.repositories.settings).save(ReleasePreference(regions: ["Japan", "USA", "Europe"]))
        let reopened = try AppContainer(rootURL: fixture.root)
        XCTAssertEqual(try ReleasePreferenceStore(store: reopened.repositories.settings).load().regions, ["Japan", "USA", "Europe"])
    }

    func testMatchUnknownGameRecordsAbsentBaseAndLaterOffersLink() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let unknown = try fixture.review(3)
        XCTAssertNil(unknown.baseGameReference)
        XCTAssertEqual(unknown.destination, .newGame)
        unknown.matchGame(fixture.dumps[0])
        XCTAssertFalse(unknown.markAsBase)
        XCTAssertEqual(unknown.baseGameReference?.title, "Crystal")
        XCTAssertEqual(try fixture.container.repositories.games.fetchGames().count, 0)
        let hack = try unknown.commit()
        XCTAssertNil(hack.build.parentBuildID)
        XCTAssertEqual(hack.build.baseGameReference?.familyName, fixture.dumps[0].name)
        let base = try fixture.review(0)
        XCTAssertEqual(base.destination, .existing(hack.game.id))
        XCTAssertTrue(base.offersBaseLink)
        XCTAssertTrue(base.markAsBase)
        XCTAssertNil(base.proposedTitle, "a hack keeps its own title when the base arrives")
        base.markAsPreferred = false
        let linked = try base.commit()
        XCTAssertTrue(linked.build.isBase)
        XCTAssertEqual(try fixture.container.repositories.builds.fetchBuild(id: hack.build.id)?.baseGameReference, hack.build.baseGameReference)
    }

    func testExplicitMatchToLibraryAndEditedRoleStayUnderReview() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let base = try fixture.review(0).commit()
        let unknown = try fixture.review(3)
        unknown.matchGame(base.game)
        unknown.matchedAsHack = false
        XCTAssertEqual(unknown.baseGameReference?.libraryGameID, base.game.id)
        XCTAssertFalse(unknown.markAsBase)
        unknown.markAsBase = true
        unknown.destination = .newGame
        unknown.destinationChanged()
        XCTAssertTrue(unknown.markAsBase, "the player explicitly changed Base")
        unknown.markAsBase = false
        unknown.destination = .existing(base.game.id)
        unknown.destinationChanged()
        let result = try unknown.commit()
        XCTAssertNil(result.build.hackTitle, "matched as another Build")
        XCTAssertEqual(result.build.baseGameReference?.libraryGameID, base.game.id)
        XCTAssertFalse(result.build.isBase)
    }

    func testFamilyMergeRefusesDuplicateImagesBeforeMovingAnyGame() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let original = try fixture.review(0).commit()
        let copy = try fixture.container.buildOperations.promoteBuild(buildID: original.build.id, title: "Copy", mode: .copy)
        let model = FamilyMergeReviewViewModel(games: fixture.container.repositories.games, builds: fixture.container.repositories.builds,
            index: fixture.index, operations: fixture.container.buildOperations)
        model.load()
        XCTAssertEqual(model.items.count, 1)
        model.items[0].accepted = true
        model.confirm()
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(try fixture.container.repositories.games.fetchGames().count, 2)
        XCTAssertNotNil(try fixture.container.repositories.games.fetchGame(id: copy.id))
        XCTAssertEqual(try fixture.container.repositories.builds.fetchBuild(id: original.build.id)?.gameID, original.game.id)
    }

    func testFamilyMergeIsReviewedAndUsesChosenSubsetAndSurvivingTitle() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        let usa = try fixture.review(0).commit()
        let japan = try fixture.review(1)
        japan.destination = .newGame
        japan.destinationChanged()
        let separate = try japan.commit()
        let europe = try fixture.review(2)
        europe.destination = .newGame
        europe.destinationChanged()
        let unselected = try europe.commit()
        let profile = try fixture.container.createBlankSaveProfile.execute(gameID: separate.game.id, name: "Main")
        let model = FamilyMergeReviewViewModel(games: fixture.container.repositories.games, builds: fixture.container.repositories.builds,
            index: fixture.index, operations: fixture.container.buildOperations)
        model.load()
        XCTAssertEqual(model.items.count, 1)
        XCTAssertFalse(model.canMerge)
        model.confirm()
        XCTAssertEqual(try fixture.container.repositories.games.fetchGames().count, 3)
        model.items[0].accepted = true
        model.items[0].selected = [usa.game.id, separate.game.id]
        model.items[0].survivorID = usa.game.id
        model.items[0].title = "Player's Crystal"
        model.confirm()
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(try fixture.container.repositories.games.fetchGame(id: separate.game.id))
        XCTAssertNotNil(try fixture.container.repositories.games.fetchGame(id: unselected.game.id))
        XCTAssertEqual(try fixture.container.repositories.builds.fetchBuild(id: separate.build.id)?.gameID, usa.game.id)
        XCTAssertEqual(try fixture.container.repositories.saveProfiles.fetchSaveProfile(id: profile.id)?.gameID, usa.game.id)
        let survivor = try XCTUnwrap(fixture.container.repositories.games.fetchGame(id: usa.game.id))
        XCTAssertEqual(survivor.primaryTitle, "Player's Crystal")
        XCTAssertTrue(survivor.hasPlayerTitle)
        XCTAssertTrue(survivor.matchesSearch("Pocket Monsters Crystal"))
    }

    @MainActor
    private final class Fixture {
        let root: URL
        let container: AppContainer
        let dumps: [KnownDump]
        let index: KnownDumpIndex
        let coordinator: ImportCoordinator
        let files: [URL]

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            container = try AppContainer(rootURL: root)
            var images: [Data] = []
            var urls: [URL] = []
            for number in 0..<4 {
                var bytes = Data(repeating: 0, count: 0x8000)
                bytes[0x200] = UInt8(number + 1)
                images.append(bytes)
                let url = root.appendingPathComponent(number == 3 ? "Crystal Plus.gb" : "Release\(number).gb")
                try bytes.write(to: url)
                urls.append(url)
            }
            let names = ["Crystal (USA)", "Pocket Monsters Crystal (Japan)", "Crystal (Europe)"]
            let regions = ["USA", "Japan", "Europe"]
            var releases: [KnownDump] = []
            for number in 0..<3 {
                let title = number == 1 ? "Pocket Monsters Crystal" : "Crystal"
                let language = number == 1 ? "Ja" : "En"
                let parent: String? = number == 0 ? nil : names[0]
                let file = KnownDumpFile(sha1: SHA1Digest.data(images[number]), size: Int64(images[number].count))
                releases.append(KnownDump(name: names[number], system: .gameBoy, title: title,
                    region: regions[number], languages: language, parent: parent, files: [file]))
            }
            dumps = releases
            index = try KnownDumpIndex(catalog: KnownDumpCatalog(source: "synthetic", generated: "", systems: [], games: dumps))
            files = urls
            coordinator = ImportCoordinator(analyzer: ROMImportAnalyzer(builds: container.repositories.builds, games: container.repositories.games,
                fingerprints: container.repositories.fingerprints,
                toolchainReports: container.repositories.toolchainReports,
                assetStore: container.fileStore, knownDumps: index), committer: container.importCommitter,
                assetStore: container.fileStore)
        }

        func review(_ number: Int, preference: ReleasePreference = ReleasePreference()) throws -> ImportReviewViewModel {
            ImportReviewViewModel(analysis: try coordinator.analyzeROM(at: files[number]), games: try container.repositories.games.fetchGames(),
                coordinator: coordinator, existingBuilds: { self.container.builds(in: $0) }, knownDumps: index, releasePreference: preference)
        }

        func cleanUp() { try? FileManager.default.removeItem(at: root) }
    }
}

import AssetStorage
import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import GameIdentity
import XCTest
@testable import Importing

final class KnownDumpImportTests: XCTestCase {
    private var root: URL!
    private var store: ManagedFileStore!
    private let games = InMemoryGameRepository()
    private let builds = InMemoryBuildRepository()
    private let fingerprints = InMemoryImageFingerprintRepository()
    private let reports = InMemoryToolchainReportRepository()
    private lazy var assets = InMemoryAssetRepository(fingerprints: fingerprints)

    // Three releases of one family, and an image No-Intro doesn't know.
    private let usa = TestROM.make(title: "CRITTERS", payloadByte: 1)
    private let japan = TestROM.make(title: "CRITTERS", payloadByte: 2)
    private let europe = TestROM.make(title: "CRITTERS", payloadByte: 3)
    private let homebrew = TestROM.make(title: "HOMEBREW", payloadByte: 4)
    // Aftermarket homebrew No-Intro knows, and a bad copy of it.
    private let moon = TestROM.make(title: "MOONGARDEN", payloadByte: 5)
    private let moonBad = TestROM.make(title: "MOONGARDEN", payloadByte: 6)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("KnownDumpImport-\(UUID())", isDirectory: true)
        store = try ManagedFileStore(rootURL: root.appendingPathComponent("Managed", isDirectory: true))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func index() throws -> KnownDumpIndex {
        let parent = "Pocket Critters - Red Version (USA, Europe)"
        let games = [
            KnownDump(
                name: parent, system: .gameBoy, title: "Pocket Critters - Red Version", region: "USA, Europe", languages: "En",
                files: [KnownDumpFile(sha1: SHA1Digest.data(usa), size: Int64(usa.count))]
            ),
            KnownDump(
                name: "Pocket Critters - Aka (Japan) (Rev 1)", system: .gameBoy, title: "Pocket Critters - Aka",
                region: "Japan", languages: "Ja", version: "Rev 1", parent: parent,
                files: [KnownDumpFile(sha1: SHA1Digest.data(japan), size: Int64(japan.count))]
            ),
            KnownDump(
                name: "Pocket Critters - Rot (Germany) (Beta 2)", system: .gameBoy, title: "Pocket Critters - Rot",
                region: "Germany", languages: "De", status: "Beta 2", parent: parent,
                files: [KnownDumpFile(sha1: SHA1Digest.data(europe), size: Int64(europe.count))]
            ),
            KnownDump(
                name: "Moon Garden (World) (En,Fr) (v1.1) (Aftermarket) (Unl)", system: .gameBoy, title: "Moon Garden",
                region: "World", languages: "En,Fr", version: "v1.1", aftermarket: true, unlicensed: true,
                files: [
                    KnownDumpFile(sha1: SHA1Digest.data(moon), size: Int64(moon.count)),
                    KnownDumpFile(sha1: SHA1Digest.data(moonBad), size: Int64(moonBad.count), bad: true),
                ]
            ),
        ]
        return try KnownDumpIndex(catalog: KnownDumpCatalog(
            source: "test",
            generated: "2026-10-06",
            systems: [.init(system: .gameBoy, dat: "Nintendo - Game Boy", version: "1", games: games.count, files: 5)],
            games: games
        ))
    }

    private func analyze(_ data: Data, named filename: String, target: UUID? = nil) throws -> ROMImportAnalysis {
        let file = root.appendingPathComponent(filename)
        try data.write(to: file)
        let analyzer = ROMImportAnalyzer(builds: builds, games: games,
            fingerprints: fingerprints,
            toolchainReports: reports,
            assetStore: store, knownDumps: try index())
        return try analyzer.analyzeROM(at: file, targetGameID: target)
    }

    private func commit(_ analysis: ROMImportAnalysis, into gameID: UUID? = nil) throws -> ROMImportResult {
        let committer = ImportCommitter(
            games: games,
            builds: builds,
            assets: assets,
            toolchainReports: reports,
            fingerprints: fingerprints,
            assetStore: store,
            transactions: PassthroughTransactionRunner()
        )
        return try committer.commit(ROMImportPlan(
            analysis: analysis,
            disposition: analysis.exactExistingBuildID.map { .duplicateExisting(buildID: $0) }
                ?? gameID.map { .addBuild(gameID: $0) }
                ?? .createGame(title: analysis.filenameMetadata.suggestedTitle),
            buildDisplayName: analysis.filenameMetadata.suggestedBuildName,
            markAsBase: gameID == nil
        ))
    }

    func testAReleaseAddsEveryRegionalTitleAsASearchAlias() throws {
        let red = try commit(try analyze(usa, named: "red.gb"))
        XCTAssertTrue(red.game.matchesSearch("pocket critters - aka"))
        XCTAssertTrue(red.game.matchesSearch("Pocket Critters - Rot"))
        let aka = try commit(try analyze(japan, named: "aka.gb"), into: red.game.id)
        XCTAssertEqual(aka.game.primaryTitle, red.game.primaryTitle, "joining a family never renames by itself")
        XCTAssertEqual(Set(aka.game.aliases).count, 3)
    }

    func testBaseGameLineageExistsWithoutABaseAndOffersTheBaseLater() throws {
        let index = try index()
        let reference = index.reference(to: try XCTUnwrap(index.dump(sha1: SHA1Digest.data(usa))))
        let committer = ImportCommitter(games: games, builds: builds, assets: assets,
            toolchainReports: reports,
            fingerprints: fingerprints,
            assetStore: store, transactions: PassthroughTransactionRunner())
        let hack = try committer.commit(ROMImportPlan(
            analysis: analyze(homebrew, named: "Critters Plus.gb"), disposition: .createGame(title: "Critters Plus"),
            buildDisplayName: "Hack", markAsBase: false, baseGameReference: reference))
        XCTAssertNil(hack.build.parentBuildID, "no invented image identity")
        XCTAssertEqual(hack.build.baseGameReference, reference)
        XCTAssertFalse(hack.build.isBase)
        let base = try analyze(usa, named: "base.gb")
        XCTAssertEqual(base.baseLineageGameIDs, [hack.game.id])
        XCTAssertEqual(base.suggestedGameID, hack.game.id)
        let linked = try committer.commit(ROMImportPlan(analysis: base, disposition: .addBuild(gameID: hack.game.id),
            buildDisplayName: "Original", markAsBase: true, markAsPreferred: false))
        XCTAssertTrue(linked.build.isBase)
        XCTAssertEqual(try builds.fetchBuild(id: hack.build.id)?.baseGameReference, reference)
        XCTAssertEqual(linked.game.primaryTitle, "Critters Plus")
    }

    func testConfirmedTitleProposalKeepsOldTitleAsAliasAndProtectsPlayerTitle() throws {
        let first = try commit(try analyze(japan, named: "aka.gb"))
        let committer = ImportCommitter(games: games, builds: builds, assets: assets,
            toolchainReports: reports,
            fingerprints: fingerprints,
            assetStore: store, transactions: PassthroughTransactionRunner())
        let better = try committer.commit(ROMImportPlan(analysis: analyze(usa, named: "red.gb"), disposition: .addBuild(gameID: first.game.id),
            buildDisplayName: "USA", markAsBase: false, markAsPreferred: true, proposedGameTitle: "Pocket Critters - Red Version"))
        XCTAssertEqual(better.game.primaryTitle, "Pocket Critters - Red Version")
        XCTAssertEqual(better.game.preferredBuildID, better.build.id)
        XCTAssertTrue(better.game.aliases.contains(first.game.primaryTitle))
        var player = better.game
        player.primaryTitle = "My Critters"
        player.hasPlayerTitle = true
        try games.updateGame(player)
        let protected = try committer.commit(ROMImportPlan(analysis: analyze(europe, named: "rot.gb"), disposition: .addBuild(gameID: player.id),
            buildDisplayName: "Europe", markAsBase: false, proposedGameTitle: "Pocket Critters - Rot"))
        XCTAssertEqual(protected.game.primaryTitle, "My Critters")
        let hack = try committer.commit(ROMImportPlan(analysis: analyze(homebrew, named: "Critters DX.gb"),
            disposition: .addBuild(gameID: player.id), buildDisplayName: "Critters DX", markAsBase: false,
            markAsPreferred: true, proposedGameTitle: "Critters DX", proposedGameTitleIsPlayers: true))
        XCTAssertEqual(hack.game.primaryTitle, "Critters DX", "a title the player chose in review replaces theirs")
        XCTAssertTrue(hack.game.hasPlayerTitle)
        XCTAssertTrue(hack.game.aliases.contains("My Critters"))
    }

    func testFamilyGroupingUsesImageEvidenceAndDoesNotChangeTheLibrary() throws {
        let red = try commit(try analyze(usa, named: "red.gb"))
        let aka = try commit(try analyze(japan, named: "aka.gb"))
        _ = try commit(try analyze(homebrew, named: "Pocket Critters - Rot.gb"))
        let suggestions = try FamilyGameSuggester(games: games, builds: builds, index: index()).suggestions()
        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(Set(suggestions[0].games.map(\.id)), [red.game.id, aka.game.id])
        XCTAssertEqual(try games.fetchGames().count, 3, "suggesting does not merge")
    }

    func testAKnownDumpTakesItsCanonicalNameAndKeepsTheFilename() throws {
        let analysis = try analyze(usa, named: "critters_red.gb")
        XCTAssertEqual(analysis.knownDump?.name, "Pocket Critters - Red Version (USA, Europe)")
        XCTAssertEqual(analysis.filenameMetadata.suggestedTitle, "Pocket Critters - Red Version")
        XCTAssertEqual(analysis.filenameMetadata.buildMetadata.region, "USA, Europe")
        XCTAssertEqual(analysis.filenameMetadata.buildMetadata.language, "En")
        XCTAssertEqual(analysis.filenameMetadata.normalizedFilename, "Pocket Critters - Red Version (USA, Europe).gb")
        XCTAssertEqual(analysis.originalFilename, "critters_red.gb")
        XCTAssertEqual(analysis.imageSHA1, SHA1Digest.data(usa))

        let result = try commit(analysis)
        XCTAssertEqual(result.build.imageSHA1, SHA1Digest.data(usa))
        XCTAssertEqual(try builds.fetchBuild(id: result.build.id)?.imageSHA1, SHA1Digest.data(usa))
    }

    func testAReleaseJoinsTheGameHoldingItsFamilyWhateverItsTitle() throws {
        let red = try commit(try analyze(usa, named: "red.gb"))
        let aka = try analyze(japan, named: "aka.gb")

        XCTAssertEqual(aka.filenameMetadata.suggestedTitle, "Pocket Critters - Aka", "a regional title of its own")
        XCTAssertEqual(aka.familyGameIDs, [red.game.id])
        XCTAssertEqual(aka.suggestedGameID, red.game.id)
    }

    func testFamilyMembersInSeveralGamesLeaveTheChoiceToThePlayer() throws {
        let red = try commit(try analyze(usa, named: "red.gb"))
        let aka = try commit(try analyze(japan, named: "aka.gb"))
        // The Japanese release ended up in a Game of its own.
        XCTAssertNotEqual(red.game.id, aka.game.id)

        let rot = try analyze(europe, named: "rot.gb")
        XCTAssertEqual(Set(rot.familyGameIDs), [red.game.id, aka.game.id])
        XCTAssertNil(rot.suggestedGameID)
        XCTAssertEqual(try analyze(europe, named: "rot.gb", target: aka.game.id).suggestedGameID, aka.game.id, "a chosen Game still wins")
    }

    func testNoIntroFieldsNameTheBuildAndAftermarketAndUnlStayOut() throws {
        let aka = try analyze(japan, named: "aka.gb")
        XCTAssertEqual(aka.filenameMetadata.buildMetadata.revision, "1")
        XCTAssertEqual(aka.filenameMetadata.suggestedBuildName, "Rev 1")

        let rot = try analyze(europe, named: "rot.gb")
        XCTAssertEqual(rot.filenameMetadata.buildMetadata.status, "Beta 2")
        XCTAssertEqual(rot.filenameMetadata.releaseKind, .development)

        let garden = try analyze(moon, named: "moon_garden_v1_1.gb")
        XCTAssertEqual(garden.filenameMetadata.suggestedTitle, "Moon Garden")
        XCTAssertEqual(garden.filenameMetadata.buildMetadata.versionString, "1.1")
        XCTAssertEqual(garden.filenameMetadata.buildMetadata.language, "En, Fr")
        XCTAssertNil(garden.filenameMetadata.buildMetadata.status, "Aftermarket and Unl aren't a status")
        XCTAssertEqual(garden.filenameMetadata.suggestedBuildName, "v1.1")
        XCTAssertEqual(garden.knownFile?.bad, false)

        let badCopy = try analyze(moonBad, named: "moon.gb")
        XCTAssertEqual(badCopy.knownDump?.title, "Moon Garden", "a bad copy is still a copy of the game")
        XCTAssertEqual(badCopy.knownFile?.bad, true)
    }

    func testAnUnknownImageIsAnalyzedAsBefore() throws {
        let analysis = try analyze(homebrew, named: "My Homebrew (World) [v1.2].gb")
        XCTAssertNil(analysis.knownDump)
        XCTAssertEqual(analysis.familyGameIDs, [])
        XCTAssertEqual(analysis.filenameMetadata.suggestedTitle, "My Homebrew")
        XCTAssertEqual(analysis.imageSHA1, SHA1Digest.data(homebrew), "every import keeps its SHA-1")
    }

    func testImportingTheSameImageAgainFillsAMissingSHA1() throws {
        let first = try commit(try analyze(usa, named: "red.gb"))
        // As a Build imported before SHA-1 was kept.
        var old = first.build
        old.imageSHA1 = nil
        try builds.updateBuildMetadata(old)

        let again = try analyze(usa, named: "red copy.gb")
        XCTAssertEqual(again.exactExistingBuildID, first.build.id)
        let result = try commit(again)
        XCTAssertEqual(result.build.imageSHA1, SHA1Digest.data(usa))
        XCTAssertEqual(try builds.fetchBuild(id: first.build.id)?.imageSHA1, SHA1Digest.data(usa))
    }
}

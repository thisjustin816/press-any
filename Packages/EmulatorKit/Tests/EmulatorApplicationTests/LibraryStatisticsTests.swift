import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import Testing

struct LibraryStatisticsTests {
    private let date = Date(timeIntervalSince1970: 1_000)

    @Test func rollupsUseBuildPlaytimeAndProfileSessionsAndLatestDate() throws {
        let game = makeGame("Example")
        let other = makeGame("Other")
        let builds = InMemoryBuildRepository([
            makeBuild(game, seconds: 120), makeBuild(game, seconds: 60), makeBuild(other, seconds: 900)
        ])
        let profiles = InMemorySaveProfileRepository([
            makeProfile(game, sessions: 2, lastPlayed: date),
            makeProfile(game, sessions: 3, lastPlayed: date.addingTimeInterval(60)),
            makeProfile(game), makeProfile(other, sessions: 8, lastPlayed: date.addingTimeInterval(900))
        ])
        let result = try FetchGameStatistics(games: InMemoryGameRepository([game, other]), builds: builds, profiles: profiles).execute()
        let stats = try #require(result[game.id])
        #expect(stats.totalPlaytimeSeconds == 180)
        #expect(stats.sessionCount == 5)
        #expect(stats.lastPlayedAt == date.addingTimeInterval(60))
        #expect(stats.addedAt == game.createdAt)
        #expect(stats.hasBeenPlayed)
        #expect(result[other.id]?.totalPlaytimeSeconds == 900)
    }

    @Test func neverPlayedGamesHaveEmptyStatistics() throws {
        let empty = makeGame("Empty")
        let game = makeGame("Unplayed")
        let result = try FetchGameStatistics(
            games: InMemoryGameRepository([empty, game]),
            builds: InMemoryBuildRepository([makeBuild(game)]),
            profiles: InMemorySaveProfileRepository([makeProfile(game)])
        ).execute()
        for game in [empty, game] {
            let stats = try #require(result[game.id])
            #expect(stats.totalPlaytimeSeconds == 0)
            #expect(stats.sessionCount == 0)
            #expect(stats.lastPlayedAt == nil)
            #expect(stats.addedAt == game.createdAt)
            #expect(!stats.hasBeenPlayed)
        }
    }

    @Test func recentlyDeletedBuildsAndProfilesDoNotCountAndRestoreReturnsThem() throws {
        let game = makeGame("Example")
        let live = makeBuild(game, seconds: 60)
        let deleted = makeBuild(game, seconds: 120)
        let liveProfile = makeProfile(game, sessions: 1, lastPlayed: date)
        let deletedProfile = makeProfile(game, sessions: 4, lastPlayed: date.addingTimeInterval(60))
        let games = InMemoryGameRepository([game])
        let builds = InMemoryBuildRepository([live, deleted])
        let profiles = InMemorySaveProfileRepository([liveProfile, deletedProfile])
        let deletions = InMemoryLibraryDeletionRepository(
            games: games, builds: builds, profiles: profiles, states: InMemorySaveStateRepository(),
            recipes: InMemoryPatchRecipeRepository(), assets: InMemoryAssetRepository()
        )
        let deletion = LibraryDeletion(
            id: UUID(), kind: .build, title: deleted.displayName, gameID: game.id, deletedAt: date,
            records: LibraryRecordSet(buildIDs: [deleted.id], saveProfileIDs: [deletedProfile.id])
        )
        try deletions.insertDeletion(deletion)
        #expect(try builds.fetchAllBuilds().map(\.id) == [live.id])
        #expect(try profiles.fetchAllSaveProfiles().map(\.id) == [liveProfile.id])
        let fetch = FetchGameStatistics(games: games, builds: builds, profiles: profiles)
        let stats = try #require(fetch.execute()[game.id])
        #expect(stats.totalPlaytimeSeconds == 60)
        #expect(stats.sessionCount == 1)
        #expect(stats.lastPlayedAt == date)
        try deletions.restoreDeletion(id: deletion.id)
        let restored = try #require(fetch.execute()[game.id])
        #expect(restored.totalPlaytimeSeconds == 180)
        #expect(restored.sessionCount == 5)
        #expect(restored.lastPlayedAt == deletedProfile.lastPlayedAt)
    }

    @Test(arguments: LibrarySort.allCases)
    func sortOrdersAndTitleTies(sort: LibrarySort) throws {
        let alpha = makeGame("alpha")
        let beta = makeGame("Beta", added: date.addingTimeInterval(20))
        let gamma = makeGame("Gamma", added: date.addingTimeInterval(20))
        let never = makeGame("Aardvark", added: date.addingTimeInterval(10))
        let games = [gamma, never, beta, alpha]
        let stats = try FetchGameStatistics(
            games: InMemoryGameRepository(games),
            builds: InMemoryBuildRepository([
                makeBuild(alpha, seconds: 60), makeBuild(beta, seconds: 120), makeBuild(gamma, seconds: 120)
            ]),
            profiles: InMemorySaveProfileRepository([
                makeProfile(alpha, sessions: 1, lastPlayed: date),
                makeProfile(beta, sessions: 1, lastPlayed: date.addingTimeInterval(60)),
                makeProfile(gamma, sessions: 1, lastPlayed: date.addingTimeInterval(60))
            ])
        ).execute()
        let systems: [UUID: GameSystem] = [alpha.id: .gameBoyColor, beta.id: .gameBoy, gamma.id: .gameBoy, never.id: .gameBoyColor]
        let expected: [Game]
        switch sort {
        // Without Build metadata or manual positions, those sorts fall back to titles.
        case .title, .hackAuthor, .version, .manual: expected = [never, alpha, beta, gamma]
        case .recentlyPlayed, .playtime: expected = [beta, gamma, alpha, never]
        case .recentlyAdded: expected = [beta, gamma, never, alpha]
        case .recentlyChanged: expected = [alpha, beta, gamma, never]
        case .system: expected = [beta, gamma, never, alpha]
        }
        #expect(sort.sorted(games: games, systems: systems, statistics: stats).map(\.id) == expected.map(\.id))
    }

    @Test func playedZeroTimeSortsBeforeNeverPlayedAndUnplayedTiesUseTitle() throws {
        let played = makeGame("Zulu")
        let alpha = makeGame("Alpha")
        let beta = makeGame("Beta")
        let games = [beta, alpha, played]
        let stats = try FetchGameStatistics(
            games: InMemoryGameRepository(games), builds: InMemoryBuildRepository(),
            profiles: InMemorySaveProfileRepository([makeProfile(played, sessions: 1, lastPlayed: date)])
        ).execute()
        for sort in [LibrarySort.recentlyPlayed, .playtime] {
            #expect(sort.sorted(games: games, systems: [:], statistics: stats).map(\.id) == [played.id, alpha.id, beta.id])
        }
        #expect(LibrarySort.title.sorted(games: games, systems: [:], statistics: [:]).map(\.id) == [alpha.id, beta.id, played.id])
    }

    @Test func buildPlaytimeWithoutAProfileDateStillSortsBeforeNeverPlayed() throws {
        let played = makeGame("Zulu")
        let never = makeGame("Alpha")
        let games = [never, played]
        let stats = try FetchGameStatistics(
            games: InMemoryGameRepository(games),
            builds: InMemoryBuildRepository([makeBuild(played, seconds: 60)]),
            profiles: InMemorySaveProfileRepository()
        ).execute()
        #expect(stats[played.id]?.lastPlayedAt == nil)
        for sort in [LibrarySort.recentlyPlayed, .playtime] {
            #expect(sort.sorted(games: games, systems: [:], statistics: stats).map(\.id) == [played.id, never.id])
        }
    }

    @Test func hackAuthorUsesThePreferredBuildAToZWithMissingAuthorsLast() {
        let zed = makeGame("Alpha")
        let ann = makeGame("Zulu")
        let annAgain = makeGame("Beta")
        let none = makeGame("Aardvark")
        let blank = makeGame("Able", preferred: true)
        let preferredBob = makeGame("Gamma", preferred: true)
        let builds = [
            makeBuild(zed, author: "zed"), makeBuild(ann, author: "Ann"), makeBuild(annAgain, author: " ann "),
            makeBuild(none), makeBuild(blank, author: "  "),
            // The Game's first Build has an earlier author, but its Preferred Build decides.
            makeBuild(preferredBob, author: "Aaron"), makeBuild(preferredBob, id: preferredBob.preferredBuildID, author: "Bob")
        ]
        let games = [zed, ann, annAgain, none, blank, preferredBob]
        let preferred = LibrarySort.preferredBuilds(games: games, builds: builds)
        #expect(preferred[preferredBob.id]?.author == "Bob")
        #expect(preferred[zed.id]?.author == "zed")
        #expect(LibrarySort.hackAuthor.sorted(games: games, systems: [:], statistics: [:], preferredBuilds: preferred).map(\.id)
            == [annAgain, ann, preferredBob, zed, none, blank].map(\.id))
    }

    @Test func versionSortsNewestFirstWithMissingVersionsLastAndTitleTies() {
        let ten = makeGame("Ten")
        let nine = makeGame("Nine")
        let beta = makeGame("Beta")
        let tieB = makeGame("Two B")
        let tieA = makeGame("Two A")
        let none = makeGame("Aardvark")
        let builds = [
            makeBuild(ten, version: "1.10"), makeBuild(nine, version: "1.9"), makeBuild(beta, version: "1.10-beta.2"),
            makeBuild(tieB, version: "2.0"), makeBuild(tieA, version: "2.0.0"), makeBuild(none)
        ]
        let games = [none, nine, ten, beta, tieB, tieA]
        let preferred = LibrarySort.preferredBuilds(games: games, builds: builds)
        #expect(LibrarySort.version.sorted(games: games, systems: [:], statistics: [:], preferredBuilds: preferred).map(\.id)
            == [tieA, tieB, ten, beta, nine, none].map(\.id))
    }

    @Test func recentlyChangedUsesTheNewestBuildAddedOrChanged() {
        let edited = makeGame("Edited")
        let added = makeGame("Zulu")
        let tie = makeGame("Alpha")
        let empty = makeGame("Aardvark")
        let builds = [
            makeBuild(edited, created: date, modified: date.addingTimeInterval(500)),
            makeBuild(added, created: date.addingTimeInterval(100)), makeBuild(added, created: date.addingTimeInterval(400)),
            makeBuild(tie, created: date.addingTimeInterval(400))
        ]
        let games = [empty, tie, added, edited]
        let stats = GameStatistics.rollup(games: games, builds: builds, profiles: [])
        #expect(stats[edited.id]?.lastBuildChangeAt == date.addingTimeInterval(500))
        #expect(stats[added.id]?.lastBuildChangeAt == date.addingTimeInterval(400))
        #expect(stats[empty.id]?.lastBuildChangeAt == nil)
        #expect(LibrarySort.recentlyChanged.sorted(games: games, systems: [:], statistics: stats).map(\.id)
            == [edited, tie, added, empty].map(\.id))
    }

    @Test func manualPlacesPositionedGamesFirstAndTheRestByTitle() {
        let first = makeGame("Zulu")
        let second = makeGame("Mike")
        let secondTie = makeGame("Bravo")
        let unplacedB = makeGame("Beta")
        let unplacedA = makeGame("Alpha")
        let games = [unplacedB, second, unplacedA, first, secondTie]
        let positions = [first.id: 0, second.id: 1, secondTie.id: 1]
        #expect(LibrarySort.manual.sorted(games: games, systems: [:], statistics: [:], manualPositions: positions).map(\.id)
            == [first, secondTie, second, unplacedA, unplacedB].map(\.id))
    }

    @Test func manualReorderKeepsHiddenGamesInTheirPlaces() {
        let ids = (0..<5).map { _ in UUID() }
        let (a, b, c, d, e) = (ids[0], ids[1], ids[2], ids[3], ids[4])
        #expect(LibrarySort.manualOrder(current: ids, rearrangedVisible: [e, a, c]) == [e, b, a, d, c])
        #expect(LibrarySort.manualOrder(current: ids, rearrangedVisible: [b, a, c, d, e]) == [b, a, c, d, e])
    }

    @Test func manualPositionsSurviveRestoreAndGoWhenPurged() throws {
        let kept = makeGame("Kept")
        let deleted = makeGame("Deleted")
        let games = InMemoryGameRepository([kept, deleted])
        let deletions = InMemoryLibraryDeletionRepository(
            games: games, builds: InMemoryBuildRepository(), profiles: InMemorySaveProfileRepository(),
            states: InMemorySaveStateRepository(), recipes: InMemoryPatchRecipeRepository(), assets: InMemoryAssetRepository()
        )
        try games.setManualOrder([deleted.id, kept.id])
        let deletion = LibraryDeletion(id: UUID(), kind: .game, title: deleted.primaryTitle, gameID: deleted.id,
            deletedAt: date, records: LibraryRecordSet(gameIDs: [deleted.id]))
        try deletions.insertDeletion(deletion)
        #expect(try games.fetchManualPositions() == [kept.id: 1])
        #expect(throws: BuildOperationError.gameNotFound(deleted.id)) { try games.setManualOrder([deleted.id]) }
        try deletions.restoreDeletion(id: deletion.id)
        #expect(try games.fetchManualPositions() == [deleted.id: 0, kept.id: 1])
        try deletions.insertDeletion(deletion)
        _ = try deletions.purgeDeletion(id: deletion.id, at: date)
        try games.insertGame(deleted)
        #expect(try games.fetchManualPositions() == [kept.id: 1])
    }

    private func makeGame(_ title: String, added: Date? = nil, preferred: Bool = false) -> Game {
        Game(id: UUID(), primaryTitle: title, systemFamily: "gameBoy", preferredBuildID: preferred ? UUID() : nil,
             createdAt: added ?? date, modifiedAt: date)
    }

    private func makeBuild(
        _ game: Game, id: UUID? = nil, seconds: Double = 0, author: String? = nil, version: String? = nil,
        created: Date? = nil, modified: Date? = nil
    ) -> Build {
        Build(id: id ?? UUID(), gameID: game.id, system: .gameBoy, displayName: "Build", imageAssetID: UUID(),
              imageSHA256: UUID().uuidString, sourceKind: .importedImage, versionString: version,
              versionSortKey: Build.versionSortKey(for: version), author: author, totalPlaytimeSeconds: seconds,
              createdAt: created ?? date, modifiedAt: modified ?? created ?? date)
    }

    private func makeProfile(_ game: Game, sessions: Int = 0, lastPlayed: Date? = nil) -> SaveProfile {
        SaveProfile(id: UUID(), gameID: game.id, displayName: "Main", totalPlaytimeSeconds: sessions > 0 ? 999 : 0,
                    sessionCount: sessions, lastPlayedAt: lastPlayed, createdAt: date, modifiedAt: date)
    }
}

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
        case .title: expected = [never, alpha, beta, gamma]
        case .recentlyPlayed, .playtime: expected = [beta, gamma, alpha, never]
        case .recentlyAdded: expected = [beta, gamma, never, alpha]
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

    private func makeGame(_ title: String, added: Date? = nil) -> Game {
        Game(id: UUID(), primaryTitle: title, systemFamily: "gameBoy", createdAt: added ?? date, modifiedAt: date)
    }

    private func makeBuild(_ game: Game, seconds: Double = 0) -> Build {
        Build(id: UUID(), gameID: game.id, system: .gameBoy, displayName: "Build", imageAssetID: UUID(),
              imageSHA256: UUID().uuidString, sourceKind: .importedImage, totalPlaytimeSeconds: seconds,
              createdAt: date, modifiedAt: date)
    }

    private func makeProfile(_ game: Game, sessions: Int = 0, lastPlayed: Date? = nil) -> SaveProfile {
        SaveProfile(id: UUID(), gameID: game.id, displayName: "Main", totalPlaytimeSeconds: sessions > 0 ? 999 : 0,
                    sessionCount: sessions, lastPlayedAt: lastPlayed, createdAt: date, modifiedAt: date)
    }
}

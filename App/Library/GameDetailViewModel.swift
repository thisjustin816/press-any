import Combine
import EmulatorApplication
import EmulatorDomain
import Foundation

@MainActor
final class GameDetailViewModel: ObservableObject {
    @Published private(set) var game: Game?
    @Published private(set) var builds: [Build] = []
    @Published private(set) var saveProfiles: [SaveProfile] = []
    @Published private(set) var errorMessage: String?

    let gameID: UUID

    private let games: any GameRepository
    private let buildRepository: any BuildRepository
    private let profiles: any SaveProfileRepository
    private let buildOperations: BuildOperations
    private let createBlank: CreateBlankSaveProfile
    private let duplicateProfile: DuplicateSaveProfile

    init(
        gameID: UUID,
        games: any GameRepository,
        builds: any BuildRepository,
        profiles: any SaveProfileRepository,
        buildOperations: BuildOperations,
        createBlank: CreateBlankSaveProfile,
        duplicateProfile: DuplicateSaveProfile
    ) {
        self.gameID = gameID
        self.games = games
        self.buildRepository = builds
        self.profiles = profiles
        self.buildOperations = buildOperations
        self.createBlank = createBlank
        self.duplicateProfile = duplicateProfile
    }

    var preferredBuild: Build? {
        guard let preferred = game?.preferredBuildID else { return builds.first }
        return builds.first { $0.id == preferred } ?? builds.first
    }

    func reload() {
        do {
            game = try games.fetchGame(id: gameID)
            builds = try buildRepository.fetchBuilds(gameID: gameID).sorted(by: Self.buildSort)
            saveProfiles = try profiles.fetchSaveProfiles(gameID: gameID).sorted {
                $0.createdAt < $1.createdAt
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func launchContext(build: Build? = nil, saveProfile: SaveProfile? = nil) throws -> LaunchContext {
        guard let selectedBuild = build ?? preferredBuild else {
            throw ResolvePreferredLaunchContextError.noBuilds(gameID)
        }
        let selectedProfile: SaveProfile
        if let saveProfile {
            selectedProfile = saveProfile
        } else {
            let resolver = ResolvePreferredSaveProfile(
                games: games,
                builds: buildRepository,
                profiles: profiles,
                createBlank: createBlank
            )
            selectedProfile = try resolver.execute(gameID: gameID, buildID: selectedBuild.id)
        }
        return LaunchContext(
            gameID: gameID,
            buildID: selectedBuild.id,
            saveProfileID: selectedProfile.id
        )
    }

    func setPreferredBuild(_ build: Build) {
        do {
            try buildOperations.setPreferredBuild(gameID: gameID, buildID: build.id)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createBlankProfile(name: String) {
        do {
            _ = try createBlank.execute(gameID: gameID, name: name)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func duplicate(_ profile: SaveProfile, name: String) {
        do {
            _ = try duplicateProfile.execute(sourceProfileID: profile.id, name: name)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func promote(_ build: Build, title: String, mode: ReorganizationMode) throws -> Game {
        let result = try buildOperations.promoteBuild(buildID: build.id, title: title, mode: mode)
        reload()
        return result
    }

    private static func buildSort(_ lhs: Build, _ rhs: Build) -> Bool {
        if lhs.isBase != rhs.isBase { return lhs.isBase && !rhs.isBase }
        if lhs.versionSortKey != rhs.versionSortKey {
            return (lhs.versionSortKey ?? "") < (rhs.versionSortKey ?? "")
        }
        return lhs.createdAt < rhs.createdAt
    }
}

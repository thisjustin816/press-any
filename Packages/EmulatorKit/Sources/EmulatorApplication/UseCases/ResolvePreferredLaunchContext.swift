import EmulatorDomain
import Foundation

public enum ResolvePreferredLaunchContextError: Error, Equatable {
    case gameNotFound(UUID)
    case noBuilds(UUID)
    case preferredBuildBelongsToDifferentGame(buildID: UUID, gameID: UUID)
}

/// Resolves the deterministic one-tap Play context for a Game.
///
/// Preferred Build is explicit when set. Otherwise the resolver favors a Base Build, then the
/// oldest Build, and persists that initial choice so later test-build launches never silently
/// replace the Game's normal one-tap target.
public struct ResolvePreferredLaunchContext: Sendable {
    private let games: any GameRepository
    private let builds: any BuildRepository
    private let profiles: any SaveProfileRepository
    private let profileResolver: ResolvePreferredSaveProfile
    private let now: @Sendable () -> Date

    public init(
        games: any GameRepository,
        builds: any BuildRepository,
        profiles: any SaveProfileRepository,
        assetDependencies: SaveProfileResolverDependencies,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.games = games
        self.builds = builds
        self.profiles = profiles
        self.profileResolver = ResolvePreferredSaveProfile(
            games: games,
            builds: builds,
            profiles: profiles,
            createBlank: CreateBlankSaveProfile(
                games: games,
                profiles: profiles,
                now: now,
                makeID: assetDependencies.makeID
            )
        )
        self.now = now
    }

    /// Convenience initializer for normal app use. `makeID` remains injectable in tests.
    public init(
        games: any GameRepository,
        builds: any BuildRepository,
        profiles: any SaveProfileRepository,
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.init(
            games: games,
            builds: builds,
            profiles: profiles,
            assetDependencies: SaveProfileResolverDependencies(makeID: makeID),
            now: now
        )
    }

    public func execute(gameID: UUID) throws -> LaunchContext {
        guard var game = try games.fetchGame(id: gameID) else {
            throw ResolvePreferredLaunchContextError.gameNotFound(gameID)
        }

        let build: Build
        if let preferredBuildID = game.preferredBuildID,
           let preferred = try builds.fetchBuild(id: preferredBuildID) {
            guard preferred.gameID == gameID else {
                throw ResolvePreferredLaunchContextError.preferredBuildBelongsToDifferentGame(
                    buildID: preferredBuildID,
                    gameID: gameID
                )
            }
            build = preferred
        } else {
            let available = try builds.fetchBuilds(gameID: gameID)
            guard let fallback = available.sorted(by: Self.buildPreference).first else {
                throw ResolvePreferredLaunchContextError.noBuilds(gameID)
            }
            build = fallback
            game.preferredBuildID = fallback.id
            game.modifiedAt = now()
            try games.updateGame(game)
        }

        let profile = try profileResolver.execute(gameID: gameID, buildID: build.id)
        return LaunchContext(gameID: gameID, buildID: build.id, saveProfileID: profile.id)
    }

    private static func buildPreference(_ lhs: Build, _ rhs: Build) -> Bool {
        if lhs.isBase != rhs.isBase { return lhs.isBase && !rhs.isBase }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

public struct SaveProfileResolverDependencies: Sendable {
    fileprivate let makeID: @Sendable () -> UUID

    public init(makeID: @escaping @Sendable () -> UUID = UUID.init) {
        self.makeID = makeID
    }
}

import EmulatorDomain
import Foundation

public enum ReorganizationMode: Equatable, Sendable {
    case move
    case copy
}

public enum BuildOperationError: Error, Equatable {
    case buildNotFound(UUID)
    case gameNotFound(UUID)
    case buildBelongsToDifferentGame(buildID: UUID, gameID: UUID)
    case profileNotFound(UUID)
    case profileBelongsToDifferentGame(profileID: UUID, gameID: UUID)
}

public struct BuildOperations: Sendable {
    private let games: any GameRepository
    private let builds: any BuildRepository
    private let profiles: any SaveProfileRepository
    private let transactions: any LibraryTransactionRunner
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID

    public init(
        games: any GameRepository,
        builds: any BuildRepository,
        profiles: any SaveProfileRepository,
        transactions: any LibraryTransactionRunner = PassthroughTransactionRunner(),
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.games = games
        self.builds = builds
        self.profiles = profiles
        self.transactions = transactions
        self.now = now
        self.makeID = makeID
    }

    public func setPreferredBuild(gameID: UUID, buildID: UUID) throws {
        guard var game = try games.fetchGame(id: gameID) else { throw BuildOperationError.gameNotFound(gameID) }
        guard let build = try builds.fetchBuild(id: buildID) else { throw BuildOperationError.buildNotFound(buildID) }
        guard build.gameID == gameID else {
            throw BuildOperationError.buildBelongsToDifferentGame(buildID: buildID, gameID: gameID)
        }
        game.preferredBuildID = buildID
        game.modifiedAt = now()
        try games.updateGame(game)
    }

    public func setPreferredSaveProfile(buildID: UUID, profileID: UUID?) throws {
        guard var build = try builds.fetchBuild(id: buildID) else { throw BuildOperationError.buildNotFound(buildID) }
        if let profileID {
            guard let profile = try profiles.fetchSaveProfile(id: profileID) else {
                throw BuildOperationError.profileNotFound(profileID)
            }
            guard profile.gameID == build.gameID else {
                throw BuildOperationError.profileBelongsToDifferentGame(profileID: profileID, gameID: build.gameID)
            }
        }
        build.preferredSaveProfileID = profileID
        build.modifiedAt = now()
        try builds.updateBuildMetadata(build)
    }

    public func promoteBuild(
        buildID: UUID,
        title: String,
        mode: ReorganizationMode
    ) throws -> Game {
        guard let sourceBuild = try builds.fetchBuild(id: buildID) else {
            throw BuildOperationError.buildNotFound(buildID)
        }
        let timestamp = now()
        return try transactions.run { [games, builds, sourceBuild, makeID] in
            let newGame = Game(
                id: makeID(),
                primaryTitle: title,
                systemFamily: "gameboy",
                createdAt: timestamp,
                modifiedAt: timestamp
            )
            try games.insertGame(newGame)

            let promoted: Build
            switch mode {
            case .move:
                try builds.moveBuild(id: sourceBuild.id, toGameID: newGame.id)
                guard let moved = try builds.fetchBuild(id: sourceBuild.id) else {
                    throw BuildOperationError.buildNotFound(sourceBuild.id)
                }
                promoted = moved
            case .copy:
                promoted = Self.copyBuild(sourceBuild, id: makeID(), gameID: newGame.id, timestamp: timestamp)
                try builds.insertBuild(promoted)
            }

            var updatedNewGame = newGame
            updatedNewGame.preferredBuildID = promoted.id
            try games.updateGame(updatedNewGame)

            if mode == .move, var oldGame = try games.fetchGame(id: sourceBuild.gameID) {
                let remaining = try builds.fetchBuilds(gameID: oldGame.id).sorted(by: Self.preferredBuildSort)
                if remaining.isEmpty {
                    try games.deleteGame(id: oldGame.id)
                } else if oldGame.preferredBuildID == sourceBuild.id {
                    oldGame.preferredBuildID = remaining.first?.id
                    oldGame.modifiedAt = timestamp
                    try games.updateGame(oldGame)
                }
            }
            return updatedNewGame
        }
    }

    public func mergeGame(sourceGameID: UUID, into targetGameID: UUID, mode: ReorganizationMode) throws {
        guard sourceGameID != targetGameID else { return }
        guard let sourceGame = try games.fetchGame(id: sourceGameID) else { throw BuildOperationError.gameNotFound(sourceGameID) }
        guard let targetGame = try games.fetchGame(id: targetGameID) else { throw BuildOperationError.gameNotFound(targetGameID) }
        let sourceBuilds = try builds.fetchBuilds(gameID: sourceGame.id).sorted(by: Self.preferredBuildSort)
        let timestamp = now()

        try transactions.run { [games, builds, makeID, targetGame] in
            var updatedTargetGame = targetGame
            var firstMergedBuildID: UUID?
            for source in sourceBuilds {
                switch mode {
                case .move:
                    try builds.moveBuild(id: source.id, toGameID: targetGameID)
                    if firstMergedBuildID == nil { firstMergedBuildID = source.id }
                case .copy:
                    let copy = Self.copyBuild(source, id: makeID(), gameID: targetGameID, timestamp: timestamp)
                    try builds.insertBuild(copy)
                    if firstMergedBuildID == nil { firstMergedBuildID = copy.id }
                }
            }
            if updatedTargetGame.preferredBuildID == nil {
                updatedTargetGame.preferredBuildID = firstMergedBuildID
                updatedTargetGame.modifiedAt = timestamp
                try games.updateGame(updatedTargetGame)
            }
            if mode == .move {
                try games.deleteGame(id: sourceGameID)
            }
        }
    }

    private static func copyBuild(_ source: Build, id: UUID, gameID: UUID, timestamp: Date) -> Build {
        Build(
            id: id,
            gameID: gameID,
            system: source.system,
            displayName: source.displayName,
            imageAssetID: source.imageAssetID,
            imageSHA256: source.imageSHA256,
            sourceKind: source.sourceKind,
            parentBuildID: source.parentBuildID,
            isBase: source.isBase,
            region: source.region,
            language: source.language,
            revision: source.revision,
            versionString: source.versionString,
            versionSortKey: source.versionSortKey,
            preferredSaveProfileID: nil,
            corePin: source.corePin,
            createdAt: timestamp,
            modifiedAt: timestamp
        )
    }

    private static func preferredBuildSort(_ lhs: Build, _ rhs: Build) -> Bool {
        if lhs.isBase != rhs.isBase { return lhs.isBase && !rhs.isBase }
        return lhs.createdAt < rhs.createdAt
    }
}

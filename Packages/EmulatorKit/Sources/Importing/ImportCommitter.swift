import EmulatorApplication
import EmulatorDomain
import Foundation

public enum ImportCommitterError: Error, Equatable {
    case gameNotFound(UUID)
    case buildNotFound(UUID)
    case sourceAssetMissing(UUID)
}

public struct ImportCommitter: Sendable {
    private let games: any GameRepository
    private let builds: any BuildRepository
    private let assets: any ManagedAssetRepository
    private let toolchainReports: any ToolchainReportRepository
    private let assetStore: any AssetStore
    private let transactions: any LibraryTransactionRunner
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID

    public init(
        games: any GameRepository,
        builds: any BuildRepository,
        assets: any ManagedAssetRepository,
        toolchainReports: any ToolchainReportRepository,
        assetStore: any AssetStore,
        transactions: any LibraryTransactionRunner,
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.games = games
        self.builds = builds
        self.assets = assets
        self.toolchainReports = toolchainReports
        self.assetStore = assetStore
        self.transactions = transactions
        self.now = now
        self.makeID = makeID
    }

    public func commit(_ plan: ROMImportPlan) throws -> ROMImportResult {
        if case .duplicateExisting(let buildID) = plan.disposition {
            defer { try? assetStore.removeIfExists(plan.analysis.stagedURL.deletingLastPathComponent()) }
            guard let build = try builds.fetchBuild(id: buildID) else {
                throw ImportCommitterError.buildNotFound(buildID)
            }
            guard let game = try games.fetchGame(id: build.gameID) else {
                throw ImportCommitterError.gameNotFound(build.gameID)
            }
            guard let asset = try assets.fetchAsset(id: build.imageAssetID) else {
                throw ImportCommitterError.sourceAssetMissing(build.imageAssetID)
            }
            // Importing the same image again is how a damaged or missing source file gets
            // repaired: committing checks the stored file and replaces it if it doesn't match.
            if asset.storageClass == .source {
                _ = try assetStore.commitSourceROM(stagedURL: plan.analysis.stagedURL, sha256: plan.analysis.sha256)
            }
            // The same image gives the same findings, but a newer detector may find more.
            for report in plan.analysis.toolchainReports {
                try toolchainReports.saveReport(report, buildID: build.id, detectedAt: now())
            }
            return ROMImportResult(
                game: game,
                build: build,
                sourceAsset: asset,
                createdNewGame: false,
                createdNewBuild: false
            )
        }

        let existingAsset = try assets.fetchSourceAsset(kind: .sourceImage, sha256: plan.analysis.sha256)
        let destination = try assetStore.sourceImageURL(sha256: plan.analysis.sha256)
        let fileExistedBeforeCommit = assetStore.fileExists(at: destination)
        let committedURL = try assetStore.commitSourceROM(
            stagedURL: plan.analysis.stagedURL,
            sha256: plan.analysis.sha256
        )
        let createdUnreferencedFile = existingAsset == nil && !fileExistedBeforeCommit

        do {
            let result = try transactions.run { [games, builds, assets, toolchainReports, assetStore, now, makeID] in
                let timestamp = now()
                let sourceAsset: ManagedAsset
                if let existingAsset {
                    sourceAsset = existingAsset
                } else {
                    sourceAsset = ManagedAsset(
                        id: makeID(),
                        kind: .sourceImage,
                        storageClass: .source,
                        contentSHA256: plan.analysis.sha256,
                        byteLength: plan.analysis.byteLength,
                        relativePath: try assetStore.managedRelativePath(for: committedURL),
                        originalFilename: plan.analysis.originalFilename,
                        integrityStatus: .verified,
                        createdAt: timestamp
                    )
                    try assets.insertAsset(sourceAsset)
                }

                let game: Game
                let createdNewGame: Bool
                switch plan.disposition {
                case .createGame(let title):
                    game = Game(
                        id: makeID(),
                        primaryTitle: title,
                        systemFamily: "gameboy",
                        createdAt: timestamp,
                        modifiedAt: timestamp
                    )
                    try games.insertGame(game)
                    createdNewGame = true
                case .addBuild(let gameID):
                    guard let existingGame = try games.fetchGame(id: gameID) else {
                        throw ImportCommitterError.gameNotFound(gameID)
                    }
                    game = existingGame
                    createdNewGame = false
                case .duplicateExisting:
                    preconditionFailure("Handled before transaction")
                }

                let build = Build(
                    id: makeID(),
                    gameID: game.id,
                    system: plan.analysis.header.system,
                    displayName: plan.buildDisplayName,
                    imageAssetID: sourceAsset.id,
                    imageSHA256: plan.analysis.sha256,
                    sourceKind: .importedImage,
                    isBase: plan.markAsBase,
                    createdAt: timestamp,
                    modifiedAt: timestamp
                )
                try builds.insertBuild(build)
                for report in plan.analysis.toolchainReports {
                    try toolchainReports.saveReport(report, buildID: build.id, detectedAt: timestamp)
                }

                var returnedGame = game
                if createdNewGame {
                    returnedGame.preferredBuildID = build.id
                    returnedGame.modifiedAt = timestamp
                    try games.updateGame(returnedGame)
                }

                return ROMImportResult(
                    game: returnedGame,
                    build: build,
                    sourceAsset: sourceAsset,
                    createdNewGame: createdNewGame,
                    createdNewBuild: true
                )
            }
            try? assetStore.removeIfExists(plan.analysis.stagedURL.deletingLastPathComponent())
            return result
        } catch {
            if createdUnreferencedFile {
                try? assetStore.removeIfExists(committedURL)
            }
            try? assetStore.removeIfExists(plan.analysis.stagedURL.deletingLastPathComponent())
            throw error
        }
    }
}

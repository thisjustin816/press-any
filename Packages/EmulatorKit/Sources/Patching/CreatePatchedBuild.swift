import EmulatorApplication
import EmulatorDomain
import Foundation
import Importing
import ToolchainDetection

public enum CreatePatchedBuildError: Error, Equatable {
    case gameNotFound(UUID)
    case baseBuildNotFound(UUID)
    case baseBuildBelongsToDifferentGame(buildID: UUID, gameID: UUID)
    /// The patches produced something too short to hold a cartridge header.
    case resultNotAROM(byteCount: Int)
    /// The Game already holds the ROM the patches make, as this Build. A Game keeps one Build per
    /// image, so applying the patch again would duplicate it.
    case resultAlreadyInGame(buildName: String)
}

extension CreatePatchedBuildError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .resultAlreadyInGame(let buildName):
            "This patch makes a ROM that's already in this Game as “\(buildName)”."
        case .resultNotAROM:
            "The patch didn't make a Game Boy ROM."
        case .gameNotFound, .baseBuildNotFound, .baseBuildBelongsToDifferentGame:
            nil
        }
    }
}

public struct CreatePatchedBuild: Sendable {
    public struct PatchInput: Sendable {
        public let url: URL
        public let enabled: Bool
        /// Apply Anyway: the user chose to apply the patch to a base it does not expect.
        public let ignoreBaseMismatch: Bool

        public init(url: URL, enabled: Bool = true, ignoreBaseMismatch: Bool = false) {
            self.url = url
            self.enabled = enabled
            self.ignoreBaseMismatch = ignoreBaseMismatch
        }
    }

    public struct Input: Sendable {
        public let gameID: UUID
        public let baseBuildID: UUID
        public let patches: [PatchInput]
        public let displayName: String
        public let isBase: Bool
        public let makePreferred: Bool
        public let metadata: BuildImportMetadata
        public let suggestedDisplayName: String?
        public let gameTitle: String?

        public init(
            gameID: UUID,
            baseBuildID: UUID,
            patches: [PatchInput],
            displayName: String,
            isBase: Bool = false,
            makePreferred: Bool = true,
            metadata: BuildImportMetadata = BuildImportMetadata(),
            suggestedDisplayName: String? = nil,
            gameTitle: String? = nil
        ) {
            self.gameID = gameID
            self.baseBuildID = baseBuildID
            self.patches = patches
            self.displayName = displayName
            self.isBase = isBase
            self.makePreferred = makePreferred
            self.metadata = metadata
            self.suggestedDisplayName = suggestedDisplayName
            self.gameTitle = gameTitle
        }

        public init(
            gameID: UUID,
            baseBuildID: UUID,
            patchURLs: [URL],
            displayName: String,
            isBase: Bool = false,
            makePreferred: Bool = true,
            metadata: BuildImportMetadata = BuildImportMetadata(),
            suggestedDisplayName: String? = nil,
            gameTitle: String? = nil
        ) {
            self.init(
                gameID: gameID,
                baseBuildID: baseBuildID,
                patches: patchURLs.map { PatchInput(url: $0) },
                displayName: displayName,
                isBase: isBase,
                makePreferred: makePreferred,
                metadata: metadata,
                suggestedDisplayName: suggestedDisplayName,
                gameTitle: gameTitle
            )
        }
    }

    private struct ImportedPatch: Sendable {
        let asset: ManagedAsset
        let needsAssetInsert: Bool
        let newlyCommittedURL: URL?
    }

    private let games: any GameRepository
    private let builds: any BuildRepository
    private let recipes: any PatchRecipeRepository
    private let assets: any ManagedAssetRepository
    private let toolchainReports: any ToolchainReportRepository
    private let assetStore: any AssetStore
    private let detectors: ToolchainDetectorRegistry
    private let patcher: any PatchApplying
    private let transactions: any LibraryTransactionRunner
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID

    public init(
        games: any GameRepository,
        builds: any BuildRepository,
        recipes: any PatchRecipeRepository,
        assets: any ManagedAssetRepository,
        toolchainReports: any ToolchainReportRepository,
        assetStore: any AssetStore,
        detectors: ToolchainDetectorRegistry = .standard,
        patcher: any PatchApplying = PatchStackApplier(),
        transactions: any LibraryTransactionRunner = PassthroughTransactionRunner(),
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.games = games
        self.builds = builds
        self.recipes = recipes
        self.assets = assets
        self.toolchainReports = toolchainReports
        self.assetStore = assetStore
        self.detectors = detectors
        self.patcher = patcher
        self.transactions = transactions
        self.now = now
        self.makeID = makeID
    }

    public func execute(_ input: Input) throws -> Build {
        guard let game = try games.fetchGame(id: input.gameID) else {
            throw CreatePatchedBuildError.gameNotFound(input.gameID)
        }
        guard let baseBuild = try builds.fetchBuild(id: input.baseBuildID) else {
            throw CreatePatchedBuildError.baseBuildNotFound(input.baseBuildID)
        }
        guard baseBuild.gameID == input.gameID else {
            throw CreatePatchedBuildError.baseBuildBelongsToDifferentGame(
                buildID: input.baseBuildID,
                gameID: input.gameID
            )
        }

        let resolver = ResolveImageForLaunch(
            builds: builds,
            recipes: recipes,
            assets: assets,
            assetStore: assetStore,
            patcher: patcher
        )
        let baseURL = try resolver.resolve(buildID: baseBuild.id)
        var output = try assetStore.readData(at: baseURL)
        var imported: [ImportedPatch] = []
        var recipeItems: [PatchRecipeItem] = []

        do {
            for (position, patchInput) in input.patches.enumerated() {
                var patch = try importPatch(at: patchInput.url)
                // The same file twice in one stack is one source asset.
                if let earlier = imported.first(where: { $0.asset.contentSHA256 == patch.asset.contentSHA256 }) {
                    patch = ImportedPatch(asset: earlier.asset, needsAssetInsert: false, newlyCommittedURL: nil)
                }
                imported.append(patch)
                recipeItems.append(PatchRecipeItem(
                    position: position,
                    patchAssetID: patch.asset.id,
                    enabled: patchInput.enabled,
                    ignoresBaseMismatch: patchInput.ignoreBaseMismatch,
                    expectedInputSHA256: patchInput.enabled ? assetStore.hashData(output) : nil
                ))
                guard patchInput.enabled else { continue }
                output = try patcher.apply(
                    patch: assetStore.readData(
                        at: try assetStore.managedURL(relativePath: patch.asset.relativePath)
                    ),
                    fileExtension: patchInput.url.pathExtension,
                    to: output,
                    ignoringBaseMismatch: patchInput.ignoreBaseMismatch
                )
            }

            // The result's own header decides the hardware, by the rules import uses, since a patch
            // can make a Game Boy game a Game Boy Color one or the reverse. Checksums aren't
            // checked: homebrew and hacks often leave them stale, and import only warns about them.
            let header: GBROMHeader
            do {
                header = try GBROMHeaderParser.parse(output)
            } catch {
                throw CreatePatchedBuildError.resultNotAROM(byteCount: output.count)
            }

            let resultSHA = assetStore.hashData(output)
            // Checked before anything is written, so the Game is left as it was.
            if let existing = try builds.fetchBuilds(gameID: input.gameID).first(where: { $0.imageSHA256 == resultSHA }) {
                throw CreatePatchedBuildError.resultAlreadyInGame(buildName: existing.displayName)
            }
            let generatedURL = assetStore.generatedImageURL(sha256: resultSHA)
            let generatedExistedBefore = assetStore.fileExists(at: generatedURL)
            try assetStore.writeDataAtomically(output, to: generatedURL)

            let timestamp = now()
            let generatedPath = try assetStore.managedRelativePath(for: generatedURL)
            // Another Build with the same result already records this cache file; share it.
            let existingGenerated = try assets.fetchAsset(relativePath: generatedPath)
            let generatedAsset = existingGenerated ?? ManagedAsset(
                id: makeID(),
                kind: .generatedImage,
                storageClass: .cache,
                contentSHA256: resultSHA,
                byteLength: Int64(output.count),
                relativePath: generatedPath,
                integrityStatus: .verified,
                createdAt: timestamp
            )
            let build = Build(
                id: makeID(),
                gameID: input.gameID,
                system: header.system,
                displayName: input.displayName,
                imageAssetID: generatedAsset.id,
                imageSHA256: resultSHA,
                sourceKind: .patchRecipe,
                parentBuildID: baseBuild.id,
                isBase: input.isBase,
                region: input.metadata.region,
                language: input.metadata.language,
                revision: input.metadata.revision,
                versionString: input.metadata.versionString,
                versionSortKey: input.metadata.versionSortKey,
                baseGameReference: baseBuild.baseGameReference,
                baseTitle: input.metadata.baseTitle ?? game.primaryTitle,
                hackTitle: input.metadata.hackTitle,
                author: input.metadata.author,
                translation: input.metadata.translation,
                status: input.metadata.status,
                createdAt: timestamp,
                modifiedAt: timestamp
            )
            let reports = detectors.detect(image: output, system: build.system)
            let assetsToInsert = imported.filter(\.needsAssetInsert).map(\.asset)
            let recipe = PatchRecipe(
                id: makeID(),
                resultBuildID: build.id,
                baseBuildID: baseBuild.id,
                expectedResultSHA256: resultSHA,
                items: recipeItems,
                createdAt: timestamp
            )

            do {
                try transactions.run { [assets, builds, games, recipes, toolchainReports, assetsToInsert] in
                    for asset in assetsToInsert { try assets.insertAsset(asset) }
                    if existingGenerated == nil { try assets.insertAsset(generatedAsset) }
                    try builds.insertBuild(build)
                    let provenance = PatchMetadataProvenance(input: input, gameTitle: game.primaryTitle)
                    let inheritedTitle = try games.fetchMetadataProvenance(ownerID: game.id).first { $0.field == .title }
                    for row in provenance.buildRows(build: build, game: game, inheritedTitle: inheritedTitle, at: timestamp) {
                        try builds.saveMetadataProvenance(row, ownerID: build.id)
                    }
                    try recipes.insertPatchRecipe(recipe)
                    if input.makePreferred || input.gameTitle != nil {
                        var updatedGame = game
                        if input.makePreferred { updatedGame.preferredBuildID = build.id }
                        if let title = input.gameTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                            updatedGame.addAliases([updatedGame.primaryTitle])
                            updatedGame.primaryTitle = title
                            updatedGame.hasPlayerTitle = provenance.titleRow(value: title, previous: inheritedTitle, at: timestamp).source == .player
                        }
                        updatedGame.modifiedAt = timestamp
                        try games.updateGame(updatedGame)
                        if input.gameTitle != nil, updatedGame.primaryTitle != game.primaryTitle {
                            try games.saveMetadataProvenance(
                                provenance.titleRow(value: updatedGame.primaryTitle, previous: inheritedTitle, at: timestamp), ownerID: game.id)
                        }
                    }
                    for report in reports {
                        try toolchainReports.saveReport(report, buildID: build.id, detectedAt: timestamp)
                    }
                }
            } catch {
                if !generatedExistedBefore { try? assetStore.removeIfExists(generatedURL) }
                throw error
            }
            return build
        } catch {
            cleanupUncommittedPatchFiles(imported)
            throw error
        }
    }

    private func importPatch(at sourceURL: URL) throws -> ImportedPatch {
        try ImportSizeLimit.patch.check(fileAt: sourceURL)
        let transactionID = makeID()
        let stagedURL = try assetStore.stageCopy(from: sourceURL, transactionID: transactionID)
        defer { try? assetStore.removeIfExists(stagedURL.deletingLastPathComponent()) }

        let sha = try assetStore.hashFile(at: stagedURL)
        if let existing = try assets.fetchSourceAsset(kind: .sourcePatch, sha256: sha) {
            // Committing again checks the stored file and repairs it if it was damaged.
            let storedExtension = URL(fileURLWithPath: existing.relativePath).pathExtension
            _ = try assetStore.commitSourcePatch(stagedURL: stagedURL, sha256: sha, extension: storedExtension)
            return ImportedPatch(asset: existing, needsAssetInsert: false, newlyCommittedURL: nil)
        }

        let fileExtension = sourceURL.pathExtension.isEmpty ? "patch" : sourceURL.pathExtension
        let destinationExisted = assetStore.fileExists(
            at: try assetStore.sourcePatchURL(sha256: sha, extension: fileExtension)
        )
        let destination = try assetStore.commitSourcePatch(
            stagedURL: stagedURL,
            sha256: sha,
            extension: fileExtension
        )
        let asset = ManagedAsset(
            id: makeID(),
            kind: .sourcePatch,
            storageClass: .source,
            contentSHA256: sha,
            byteLength: try assetStore.fileByteLength(at: destination),
            relativePath: try assetStore.managedRelativePath(for: destination),
            originalFilename: sourceURL.lastPathComponent,
            integrityStatus: .verified,
            createdAt: now()
        )
        return ImportedPatch(
            asset: asset,
            needsAssetInsert: true,
            newlyCommittedURL: destinationExisted ? nil : destination
        )
    }

    private func cleanupUncommittedPatchFiles(_ imported: [ImportedPatch]) {
        for patch in imported where patch.needsAssetInsert {
            guard (try? assets.fetchAsset(id: patch.asset.id)) == nil,
                  let url = patch.newlyCommittedURL else { continue }
            try? assetStore.removeIfExists(url)
        }
    }
}

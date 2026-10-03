import EmulatorApplication
import EmulatorDomain
import Foundation

public enum CreatePatchedBuildError: Error, Equatable {
    case gameNotFound(UUID)
    case baseBuildNotFound(UUID)
    case baseBuildBelongsToDifferentGame(buildID: UUID, gameID: UUID)
}

public struct CreatePatchedBuild: Sendable {
    public struct PatchInput: Sendable {
        public let url: URL
        public let enabled: Bool

        public init(url: URL, enabled: Bool = true) {
            self.url = url
            self.enabled = enabled
        }
    }

    public struct Input: Sendable {
        public let gameID: UUID
        public let baseBuildID: UUID
        public let patches: [PatchInput]
        public let displayName: String
        public let isBase: Bool

        public init(
            gameID: UUID,
            baseBuildID: UUID,
            patches: [PatchInput],
            displayName: String,
            isBase: Bool = false
        ) {
            self.gameID = gameID
            self.baseBuildID = baseBuildID
            self.patches = patches
            self.displayName = displayName
            self.isBase = isBase
        }

        public init(
            gameID: UUID,
            baseBuildID: UUID,
            patchURLs: [URL],
            displayName: String,
            isBase: Bool = false
        ) {
            self.init(
                gameID: gameID,
                baseBuildID: baseBuildID,
                patches: patchURLs.map { PatchInput(url: $0) },
                displayName: displayName,
                isBase: isBase
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
    private let assetStore: any AssetStore
    private let patcher: any PatchApplying
    private let transactions: any LibraryTransactionRunner
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> UUID

    public init(
        games: any GameRepository,
        builds: any BuildRepository,
        recipes: any PatchRecipeRepository,
        assets: any ManagedAssetRepository,
        assetStore: any AssetStore,
        patcher: any PatchApplying = PatchStackApplier(),
        transactions: any LibraryTransactionRunner = PassthroughTransactionRunner(),
        now: @escaping @Sendable () -> Date = Date.init,
        makeID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.games = games
        self.builds = builds
        self.recipes = recipes
        self.assets = assets
        self.assetStore = assetStore
        self.patcher = patcher
        self.transactions = transactions
        self.now = now
        self.makeID = makeID
    }

    public func execute(_ input: Input) throws -> Build {
        guard try games.fetchGame(id: input.gameID) != nil else {
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

        do {
            for patchInput in input.patches {
                let patch = try importPatch(at: patchInput.url)
                imported.append(patch)
                guard patchInput.enabled else { continue }
                output = try patcher.apply(
                    patch: assetStore.readData(
                        at: try assetStore.managedURL(relativePath: patch.asset.relativePath)
                    ),
                    fileExtension: patchInput.url.pathExtension,
                    to: output
                )
            }

            let resultSHA = assetStore.hashData(output)
            let generatedURL = assetStore.generatedImageURL(sha256: resultSHA)
            let generatedExistedBefore = assetStore.fileExists(at: generatedURL)
            try assetStore.writeDataAtomically(output, to: generatedURL)

            let timestamp = now()
            let generatedAsset = ManagedAsset(
                id: makeID(),
                kind: .generatedImage,
                storageClass: .cache,
                contentSHA256: resultSHA,
                byteLength: Int64(output.count),
                relativePath: try assetStore.managedRelativePath(for: generatedURL),
                integrityStatus: .verified,
                createdAt: timestamp
            )
            let build = Build(
                id: makeID(),
                gameID: input.gameID,
                system: baseBuild.system,
                displayName: input.displayName,
                imageAssetID: generatedAsset.id,
                imageSHA256: resultSHA,
                sourceKind: .patchRecipe,
                parentBuildID: baseBuild.id,
                isBase: input.isBase,
                createdAt: timestamp,
                modifiedAt: timestamp
            )
            let patchAssets = imported.map(\.asset)
            let assetsToInsert = imported.filter(\.needsAssetInsert).map(\.asset)
            let recipe = PatchRecipe(
                id: makeID(),
                resultBuildID: build.id,
                baseBuildID: baseBuild.id,
                expectedResultSHA256: resultSHA,
                items: patchAssets.enumerated().map { index, asset in
                    PatchRecipeItem(
                        position: index,
                        patchAssetID: asset.id,
                        enabled: input.patches[index].enabled
                    )
                },
                createdAt: timestamp
            )

            do {
                try transactions.run { [assets, builds, recipes, assetsToInsert] in
                    for asset in assetsToInsert { try assets.insertAsset(asset) }
                    try assets.insertAsset(generatedAsset)
                    try builds.insertBuild(build)
                    try recipes.insertPatchRecipe(recipe)
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
        let transactionID = makeID()
        let stagedURL = try assetStore.stageCopy(from: sourceURL, transactionID: transactionID)
        defer { try? assetStore.removeIfExists(stagedURL.deletingLastPathComponent()) }

        let sha = try assetStore.hashFile(at: stagedURL)
        if let existing = try assets.fetchSourceAsset(kind: .sourcePatch, sha256: sha) {
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

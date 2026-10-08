import EmulatorApplication
import EmulatorDomain
import Foundation

public enum ResolveImageForLaunchError: Error, Equatable {
    case buildNotFound(UUID)
    case assetNotFound(UUID)
    case recipeNotFound(UUID)
    case integrityMismatch(expected: String, actual: String)
    case stepInputMismatch(position: Int, expected: String, actual: String)
    case cyclicBuildLineage(UUID)
    case patchFilenameMissing(UUID)
}

public struct ResolveImageForLaunch: Sendable {
    private let builds: any BuildRepository
    private let recipes: any PatchRecipeRepository
    private let assets: any ManagedAssetRepository
    private let assetStore: any AssetStore
    private let patcher: any PatchApplying
    private let trimCache: TrimPatchedROMCache?
    private let inFlight: InFlightFiles?

    /// `inFlight` holds each image while it's resolved, a patched Build's bases included, so
    /// cache trimming can't remove one between finding it and reading it.
    public init(
        builds: any BuildRepository,
        recipes: any PatchRecipeRepository,
        assets: any ManagedAssetRepository,
        assetStore: any AssetStore,
        patcher: any PatchApplying = PatchStackApplier(),
        trimCache: TrimPatchedROMCache? = nil,
        inFlight: InFlightFiles? = nil
    ) {
        self.builds = builds
        self.recipes = recipes
        self.assets = assets
        self.assetStore = assetStore
        self.patcher = patcher
        self.trimCache = trimCache
        self.inFlight = inFlight
    }

    /// The image's location, which nothing holds once this returns. A caller that reads it later
    /// holds it first, as a running game does, or uses `readImage`.
    public func resolve(buildID: UUID) throws -> URL {
        let lease = inFlight?.lease()
        defer { lease?.end() }
        return try resolve(buildID: buildID, visited: [], lease: lease)
    }

    public func readImage(buildID: UUID) throws -> Data {
        let lease = inFlight?.lease()
        defer { lease?.end() }
        return try assetStore.readData(at: resolve(buildID: buildID, visited: [], lease: lease))
    }

    public func resolveImageForLaunch(buildID: UUID) throws -> URL {
        try resolve(buildID: buildID)
    }

    private func resolve(buildID: UUID, visited: Set<UUID>, lease: InFlightFiles.Lease?) throws -> URL {
        guard !visited.contains(buildID) else {
            throw ResolveImageForLaunchError.cyclicBuildLineage(buildID)
        }
        guard let build = try builds.fetchBuild(id: buildID) else {
            throw ResolveImageForLaunchError.buildNotFound(buildID)
        }
        guard let asset = try assets.fetchAsset(id: build.imageAssetID) else {
            throw ResolveImageForLaunchError.assetNotFound(build.imageAssetID)
        }

        lease?.hold(asset.relativePath)
        let assetURL = try assetStore.managedURL(relativePath: asset.relativePath)
        if assetStore.fileExists(at: assetURL) {
            let actual = try assetStore.hashFile(at: assetURL)
            if actual == build.imageSHA256 { return assetURL }
            if build.sourceKind == .importedImage {
                throw ResolveImageForLaunchError.integrityMismatch(expected: build.imageSHA256, actual: actual)
            }
        } else if build.sourceKind == .importedImage {
            throw ResolveImageForLaunchError.assetNotFound(build.imageAssetID)
        }

        guard let recipe = try recipes.fetchPatchRecipe(resultBuildID: build.id) else {
            throw ResolveImageForLaunchError.recipeNotFound(build.id)
        }

        var nextVisited = visited
        nextVisited.insert(buildID)
        let baseURL = try resolve(buildID: recipe.baseBuildID, visited: nextVisited, lease: lease)
        var output = try assetStore.readData(at: baseURL)

        for item in recipe.items.filter(\.enabled).sorted(by: { $0.position < $1.position }) {
            if let expected = item.expectedInputSHA256 {
                let actual = assetStore.hashData(output)
                guard actual == expected else {
                    throw ResolveImageForLaunchError.stepInputMismatch(
                        position: item.position, expected: expected, actual: actual
                    )
                }
            }
            guard let patchAsset = try assets.fetchAsset(id: item.patchAssetID) else {
                throw ResolveImageForLaunchError.assetNotFound(item.patchAssetID)
            }
            let patchURL = try assetStore.managedURL(relativePath: patchAsset.relativePath)
            guard assetStore.fileExists(at: patchURL) else {
                throw ResolveImageForLaunchError.assetNotFound(item.patchAssetID)
            }
            let actualPatchHash = try assetStore.hashFile(at: patchURL)
            guard actualPatchHash == patchAsset.contentSHA256 else {
                throw ResolveImageForLaunchError.integrityMismatch(
                    expected: patchAsset.contentSHA256,
                    actual: actualPatchHash
                )
            }
            let filename = patchAsset.originalFilename ?? patchURL.lastPathComponent
            let fileExtension = URL(fileURLWithPath: filename).pathExtension
            guard !fileExtension.isEmpty else {
                throw ResolveImageForLaunchError.patchFilenameMissing(patchAsset.id)
            }
            output = try patcher.apply(
                patch: assetStore.readData(at: patchURL),
                fileExtension: fileExtension,
                to: output,
                ignoringBaseMismatch: item.ignoresBaseMismatch
            )
        }

        let actualResultHash = assetStore.hashData(output)
        guard actualResultHash == recipe.expectedResultSHA256,
              actualResultHash == build.imageSHA256 else {
            throw ResolveImageForLaunchError.integrityMismatch(
                expected: recipe.expectedResultSHA256,
                actual: actualResultHash
            )
        }

        let generatedURL = assetStore.generatedImageURL(sha256: actualResultHash)
        // Best effort: the write reports a full disk itself.
        _ = try? trimCache?.execute(incomingBytes: Int64(output.count))
        try assetStore.writeDataAtomically(output, to: generatedURL)
        return generatedURL
    }
}

public typealias PatchDerivedImageResolver = ResolveImageForLaunch

extension ResolveImageForLaunch: BuildImageResolving {
    public func resolveImageURL(buildID: UUID) throws -> URL {
        try resolve(buildID: buildID)
    }
}

extension ResolveImageForLaunchError: LocalizedError {
    public var errorDescription: String? {
        guard case let .stepInputMismatch(position, expected, actual) = self else { return nil }
        return "Patch step \(position + 1) received a different input.\nExpected SHA-256: \(expected)\nActual SHA-256: \(actual)"
    }
}

import EmulatorDomain
import Foundation

public enum ClearPatchedROMCacheError: Error, Equatable {
    case activeBuildNotFound(UUID)
    case activeImageAssetNotFound(UUID)
}

public struct ClearPatchedROMCache: Sendable {
    private let assets: any ManagedAssetInventoryRepository
    private let builds: any BuildRepository
    private let cache: GeneratedImageCache

    public init(
        assets: any ManagedAssetInventoryRepository,
        builds: any BuildRepository,
        recipes: any PatchRecipeRepository,
        assetStore: any AssetStore,
        inFlight: InFlightFiles? = nil
    ) {
        self.assets = assets
        self.builds = builds
        cache = GeneratedImageCache(assets: assets, builds: builds, recipes: recipes, assetStore: assetStore,
            inFlight: inFlight)
    }

    public func execute(activeBuildID: UUID? = nil) throws {
        let protectedPath = try activeImagePath(buildID: activeBuildID)
        for asset in try cache.removableImages() where asset.relativePath != protectedPath {
            _ = try cache.remove(asset)
        }
    }

    private func activeImagePath(buildID: UUID?) throws -> String? {
        guard let buildID else { return nil }
        guard let build = try builds.fetchBuild(id: buildID) else {
            throw ClearPatchedROMCacheError.activeBuildNotFound(buildID)
        }
        guard let asset = try assets.fetchAsset(id: build.imageAssetID) else {
            throw ClearPatchedROMCacheError.activeImageAssetNotFound(build.imageAssetID)
        }
        return asset.relativePath
    }
}

/// The rules every removal of generated images follows, whether the player clears the cache or
/// it's trimmed for space.
struct GeneratedImageCache: Sendable {
    let assets: any ManagedAssetInventoryRepository
    let builds: any BuildRepository
    let recipes: any PatchRecipeRepository
    let assetStore: any AssetStore
    let inFlight: InFlightFiles?

    /// Generated images that launch can rebuild if they're removed.
    func removableImages() throws -> [ManagedAsset] {
        // Launch uses an intact cached ROM and rebuilds only a missing one, so a ROM whose base or
        // patches are gone is the only copy left.
        try assets.fetchAssets().filter { asset in
            guard asset.kind == .generatedImage else { return false }
            guard let build = try builds.fetchBuild(imageSHA256: asset.contentSHA256) else { return true }
            return try canRebuild(build)
        }
    }

    /// Removes the image's file unless an operation holds it. Returns whether a file was removed.
    func remove(_ asset: ManagedAsset) throws -> Bool {
        let url = try assetStore.managedURL(relativePath: asset.relativePath)
        let remove = { [assetStore] () throws -> Bool in
            guard assetStore.fileExists(at: url) else { return false }
            try assetStore.removeIfExists(url)
            return true
        }
        guard let inFlight else { return try remove() }
        return try inFlight.removeUnlessHeld(asset.relativePath, remove)
    }

    private func canRebuild(_ build: Build, visited: Set<UUID> = []) throws -> Bool {
        guard !visited.contains(build.id),
              let recipe = try recipes.fetchPatchRecipe(resultBuildID: build.id),
              let base = try builds.fetchBuild(id: recipe.baseBuildID)
        else { return false }
        let baseReady = base.sourceKind == .importedImage
            ? try fileExists(assetID: base.imageAssetID)
            : try canRebuild(base, visited: visited.union([build.id]))
        guard baseReady else { return false }
        return try recipe.items.filter(\.enabled).allSatisfy { try fileExists(assetID: $0.patchAssetID) }
    }

    private func fileExists(assetID: UUID) throws -> Bool {
        guard let asset = try assets.fetchAsset(id: assetID) else { return false }
        return assetStore.fileExists(at: try assetStore.managedURL(relativePath: asset.relativePath))
    }
}

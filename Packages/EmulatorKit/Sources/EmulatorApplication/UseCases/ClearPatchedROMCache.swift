import EmulatorDomain
import Foundation

public enum ClearPatchedROMCacheError: Error, Equatable {
    case activeBuildNotFound(UUID)
    case activeImageAssetNotFound(UUID)
}

public struct ClearPatchedROMCache: Sendable {
    private let assets: any ManagedAssetInventoryRepository
    private let builds: any BuildRepository
    private let recipes: any PatchRecipeRepository
    private let assetStore: any AssetStore

    public init(
        assets: any ManagedAssetInventoryRepository,
        builds: any BuildRepository,
        recipes: any PatchRecipeRepository,
        assetStore: any AssetStore
    ) {
        self.assets = assets
        self.builds = builds
        self.recipes = recipes
        self.assetStore = assetStore
    }

    public func execute(activeBuildID: UUID? = nil) throws {
        let protectedPath = try activeImagePath(buildID: activeBuildID)
        for asset in try assets.fetchAssets() where asset.kind == .generatedImage {
            guard asset.relativePath != protectedPath else { continue }
            // Launch uses an intact cached ROM and rebuilds only a missing one, so a ROM whose base
            // or patches are gone is the only copy left.
            if let build = try builds.fetchBuild(imageSHA256: asset.contentSHA256), try !canRebuild(build) { continue }
            try assetStore.removeIfExists(try assetStore.managedURL(relativePath: asset.relativePath))
        }
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

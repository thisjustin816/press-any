import EmulatorApplication
import EmulatorDomain
import Foundation

public enum EvictGeneratedImageError: Error, Equatable {
    case buildNotFound(UUID)
    /// Only patch-derived Builds have a rebuildable image. An imported image is a source asset.
    case notRebuildable(UUID)
}

/// Removes a patch-derived Build's generated image from the cache. The next launch rebuilds it
/// from the preserved base image and patches and checks it against the recorded digest.
public struct EvictGeneratedImage: Sendable {
    private let builds: any BuildRepository
    private let assets: any ManagedAssetRepository
    private let assetStore: any AssetStore

    public init(
        builds: any BuildRepository,
        assets: any ManagedAssetRepository,
        assetStore: any AssetStore
    ) {
        self.builds = builds
        self.assets = assets
        self.assetStore = assetStore
    }

    /// Returns false when the image was not cached.
    @discardableResult
    public func execute(buildID: UUID) throws -> Bool {
        guard let build = try builds.fetchBuild(id: buildID) else {
            throw EvictGeneratedImageError.buildNotFound(buildID)
        }
        guard build.sourceKind == .patchRecipe,
              let asset = try assets.fetchAsset(id: build.imageAssetID),
              asset.storageClass == .cache else {
            throw EvictGeneratedImageError.notRebuildable(buildID)
        }
        let url = try assetStore.managedURL(relativePath: asset.relativePath)
        guard assetStore.fileExists(at: url) else { return false }
        try assetStore.removeIfExists(url)
        return true
    }
}

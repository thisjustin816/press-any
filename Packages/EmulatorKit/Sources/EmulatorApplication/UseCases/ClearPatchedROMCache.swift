import EmulatorDomain
import Foundation

public enum ClearPatchedROMCacheError: Error, Equatable {
    case activeBuildNotFound(UUID)
    case activeImageAssetNotFound(UUID)
}

public struct ClearPatchedROMCache: Sendable {
    private let assets: any ManagedAssetInventoryRepository
    private let builds: any BuildRepository
    private let assetStore: any AssetStore

    public init(
        assets: any ManagedAssetInventoryRepository,
        builds: any BuildRepository,
        assetStore: any AssetStore
    ) {
        self.assets = assets
        self.builds = builds
        self.assetStore = assetStore
    }

    public func execute(activeBuildID: UUID? = nil) throws {
        let protectedPath = try activeImagePath(buildID: activeBuildID)
        for asset in try assets.fetchAssets() where asset.kind == .generatedImage {
            guard asset.relativePath != protectedPath else { continue }
            try assetStore.removeIfExists(try assetStore.managedURL(relativePath: asset.relativePath))
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

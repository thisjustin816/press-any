import EmulatorDomain
import Foundation

extension ManagedAssetRepository {
    /// Removes the asset's row, then its file, ignoring failures. For cleanup after the asset
    /// stopped being referenced, where a leftover is only an orphaned file for the integrity
    /// checker to find, never a broken reference.
    public func discard(_ asset: ManagedAsset, files assetStore: any AssetStore) {
        try? deleteAsset(id: asset.id)
        if let url = try? assetStore.managedURL(relativePath: asset.relativePath) {
            try? assetStore.removeIfExists(url)
        }
    }

    /// Discards the asset with this ID, if there is one.
    public func discard(assetID: UUID?, files assetStore: any AssetStore) {
        guard let assetID, let asset = try? fetchAsset(id: assetID) else { return }
        discard(asset, files: assetStore)
    }
}

extension SaveProfileRepository {
    /// Removes a profile made moments ago, and its save, ignoring failures. For undoing a copy
    /// whose operation then failed.
    public func discardNewProfile(_ profile: SaveProfile, assets: any ManagedAssetRepository, files assetStore: any AssetStore) {
        try? deleteSaveProfile(id: profile.id)
        assets.discard(assetID: profile.persistentSaveAssetID, files: assetStore)
    }
}

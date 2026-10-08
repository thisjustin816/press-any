import EmulatorApplication
import EmulatorDomain
import Foundation

public struct FillImageFingerprints: Sendable {
    private let assets: any ManagedAssetInventoryRepository
    private let fingerprints: any ImageFingerprintRepository
    private let assetStore: any AssetStore

    public init(assets: any ManagedAssetInventoryRepository, fingerprints: any ImageFingerprintRepository,
                assetStore: any AssetStore) {
        self.assets = assets
        self.fingerprints = fingerprints
        self.assetStore = assetStore
    }

    /// Unreadable images remain unfinished and are retried at the next launch.
    @discardableResult
    public func execute() throws -> Int {
        let sources = try assets.fetchAssets().filter { $0.kind == .sourceImage && $0.storageClass == .source }
        let finished = try fingerprints.fetchFingerprints(imageSHA256s: sources.map(\.contentSHA256))
        var filled = Set<String>()
        for asset in sources where finished[asset.contentSHA256] == nil && !filled.contains(asset.contentSHA256) {
            guard let url = try? assetStore.managedURL(relativePath: asset.relativePath),
                  let bytes = try? assetStore.readData(at: url),
                  assetStore.hashData(bytes) == asset.contentSHA256,
                  let header = try? GBROMHeaderParser.parse(bytes) else { continue }
            try fingerprints.saveFingerprint(ROMBankFingerprint.make(image: bytes, sha256: asset.contentSHA256, header: header))
            filled.insert(asset.contentSHA256)
        }
        return filled.count
    }
}

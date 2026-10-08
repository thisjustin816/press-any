import EmulatorDomain
import Foundation

public enum LibraryStorageCategory: CaseIterable, Hashable, Sendable {
    case gameROMs
    case patches
    case saves
    case saveStates
    case artwork
    case other
    case patchedROMCache
    case quickPlay
}

public struct LibraryStorageUsage: Equatable, Sendable {
    private let categoryBytes: [LibraryStorageCategory: Int64]

    public init(categoryBytes: [LibraryStorageCategory: Int64]) {
        self.categoryBytes = categoryBytes
    }

    public func bytes(in category: LibraryStorageCategory) -> Int64 {
        categoryBytes[category, default: 0]
    }

    public var totalBytes: Int64 { categoryBytes.values.reduce(0, +) }
}

public struct MeasureLibraryStorage: Sendable {
    private let assets: any ManagedAssetInventoryRepository
    private let assetStore: any AssetStore

    public init(assets: any ManagedAssetInventoryRepository, assetStore: any AssetStore) {
        self.assets = assets
        self.assetStore = assetStore
    }

    public func execute() throws -> LibraryStorageUsage {
        var totals: [LibraryStorageCategory: Int64] = [:]
        let quickPlayRoot = assetStore.quickPlayRoot(sessionID: UUID()).deletingLastPathComponent()
        for asset in try assets.fetchAssets() {
            let url = try assetStore.managedURL(relativePath: asset.relativePath)
            if url.path.hasPrefix(quickPlayRoot.path + "/") { continue }
            if asset.kind == .generatedImage, !assetStore.fileExists(at: url) { continue }
            totals[category(for: asset.kind), default: 0] += asset.byteLength
        }
        totals[.quickPlay] = try workspaceBytes(at: quickPlayRoot)
        return LibraryStorageUsage(categoryBytes: totals)
    }

    private func category(for kind: ManagedAssetKind) -> LibraryStorageCategory {
        switch kind {
        case .sourceImage: .gameROMs
        case .sourcePatch: .patches
        case .persistentSave: .saves
        case .saveState, .stateThumbnail: .saveStates
        case .artwork: .artwork
        case .generatedImage: .patchedROMCache
        default: .other
        }
    }

    private func workspaceBytes(at root: URL) throws -> Int64 {
        guard assetStore.fileExists(at: root) else { return 0 }
        var enumerationError: (any Error)?
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else { throw CocoaError(.fileReadUnknown) }
        var bytes: Int64 = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true { bytes += try assetStore.fileByteLength(at: url) }
        }
        if let enumerationError { throw enumerationError }
        return bytes
    }
}

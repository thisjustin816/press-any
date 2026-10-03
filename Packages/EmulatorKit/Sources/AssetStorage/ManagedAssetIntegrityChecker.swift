import EmulatorApplication
import EmulatorDomain
import Foundation

public enum ManagedAssetIntegrityIssue: Equatable, Sendable {
    case missingSource(assetID: UUID, relativePath: String)
    case missingCache(assetID: UUID, relativePath: String)
    case missingUserData(assetID: UUID, relativePath: String)
    case hashMismatch(assetID: UUID, relativePath: String, expected: String, actual: String)
    case orphanSource(relativePath: String)
    case orphanCache(relativePath: String)
}

public struct ManagedAssetIntegrityReport: Equatable, Sendable {
    public let issues: [ManagedAssetIntegrityIssue]
    public let removedRelativePaths: [String]

    public init(issues: [ManagedAssetIntegrityIssue], removedRelativePaths: [String]) {
        self.issues = issues
        self.removedRelativePaths = removedRelativePaths
    }

    public var isClean: Bool { issues.isEmpty }
}

public enum ManagedAssetIntegrityCleanupPolicy: Sendable {
    case reportOnly
    case removeProvableOrphans
}

/// Audits the managed source/cache roots against database inventory without touching
/// user data that cannot be deterministically reconstructed.
public struct ManagedAssetIntegrityChecker: Sendable {
    private let assets: any ManagedAssetInventoryRepository
    private let assetStore: any AssetStore

    public init(
        assets: any ManagedAssetInventoryRepository,
        assetStore: any AssetStore
    ) {
        self.assets = assets
        self.assetStore = assetStore
    }

    public func inspect(
        cleanup: ManagedAssetIntegrityCleanupPolicy = .reportOnly
    ) throws -> ManagedAssetIntegrityReport {
        let inventory = try assets.fetchAssets()
        let knownPaths = Set(inventory.map(\.relativePath))
        var issues: [ManagedAssetIntegrityIssue] = []
        var removed: [String] = []

        for var asset in inventory {
            let url = try assetStore.managedURL(relativePath: asset.relativePath)
            guard assetStore.fileExists(at: url) else {
                switch asset.storageClass {
                case .source:
                    issues.append(.missingSource(assetID: asset.id, relativePath: asset.relativePath))
                case .cache:
                    issues.append(.missingCache(assetID: asset.id, relativePath: asset.relativePath))
                case .userData, .temporary:
                    issues.append(.missingUserData(assetID: asset.id, relativePath: asset.relativePath))
                }
                continue
            }

            // Source and generated cache blobs are immutable/content-addressed. Mutable
            // saves/states have their own transactional checks and are not rehashed here.
            guard asset.storageClass == .source || asset.storageClass == .cache else { continue }
            let actual = try assetStore.hashFile(at: url)
            guard actual != asset.contentSHA256 else { continue }

            issues.append(
                .hashMismatch(
                    assetID: asset.id,
                    relativePath: asset.relativePath,
                    expected: asset.contentSHA256,
                    actual: actual
                )
            )
            if asset.integrityStatus != .corrupt {
                asset.integrityStatus = .corrupt
                try assets.updateMutableAsset(asset)
            }
        }

        let sourceOrphans = try orphanedFiles(
            under: assetStore.rootURL.appendingPathComponent("Source", isDirectory: true),
            knownPaths: knownPaths
        )
        for relativePath in sourceOrphans {
            issues.append(.orphanSource(relativePath: relativePath))
            if cleanup == .removeProvableOrphans {
                let url = try assetStore.managedURL(relativePath: relativePath)
                try assetStore.removeIfExists(url)
                removed.append(relativePath)
            }
        }

        let cacheOrphans = try orphanedFiles(
            under: assetStore.rootURL.appendingPathComponent("Cache/GeneratedROM", isDirectory: true),
            knownPaths: knownPaths
        )
        for relativePath in cacheOrphans {
            issues.append(.orphanCache(relativePath: relativePath))
            if cleanup == .removeProvableOrphans {
                let url = try assetStore.managedURL(relativePath: relativePath)
                try assetStore.removeIfExists(url)
                removed.append(relativePath)
            }
        }

        return ManagedAssetIntegrityReport(
            issues: issues.sorted(by: issueSort),
            removedRelativePaths: removed.sorted()
        )
    }

    private func orphanedFiles(under root: URL, knownPaths: Set<String>) throws -> [String] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [String] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let relative = try assetStore.managedRelativePath(for: url)
            if !knownPaths.contains(relative) { result.append(relative) }
        }
        return result.sorted()
    }

    private func issueSort(_ lhs: ManagedAssetIntegrityIssue, _ rhs: ManagedAssetIntegrityIssue) -> Bool {
        String(describing: lhs) < String(describing: rhs)
    }
}

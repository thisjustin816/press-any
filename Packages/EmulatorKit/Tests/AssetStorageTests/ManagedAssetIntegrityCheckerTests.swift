import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import XCTest
@testable import AssetStorage

final class ManagedAssetIntegrityCheckerTests: XCTestCase {
    func testMissingSourceIsReportedButMetadataIsPreserved() throws {
        let harness = try IntegrityHarness.make()
        let asset = try harness.insertSourceROM(bytes: Data("ROM".utf8))
        let url = try harness.store.managedURL(relativePath: asset.relativePath)
        try harness.store.removeIfExists(url)

        let report = try harness.checker.inspect()

        XCTAssertEqual(report.issues, [.missingSource(assetID: asset.id, relativePath: asset.relativePath)])
        XCTAssertNotNil(try harness.assets.fetchAsset(id: asset.id))
    }

    func testHashMismatchMarksImmutableAssetCorrupt() throws {
        let harness = try IntegrityHarness.make()
        let asset = try harness.insertSourceROM(bytes: Data("GOOD".utf8))
        let url = try harness.store.managedURL(relativePath: asset.relativePath)
        try harness.store.writeDataAtomically(Data("BAD".utf8), to: url)

        let report = try harness.checker.inspect()

        XCTAssertEqual(report.issues.count, 1)
        guard case .hashMismatch(let assetID, _, _, _) = report.issues[0] else {
            return XCTFail("Expected hash mismatch")
        }
        XCTAssertEqual(assetID, asset.id)
        XCTAssertEqual(try harness.assets.fetchAsset(id: asset.id)?.integrityStatus, .corrupt)
    }

    func testProvableOrphanSourceAndCacheCanBeRemoved() throws {
        let harness = try IntegrityHarness.make()
        let source = try harness.store.sourceImageURL(sha256: String(repeating: "a", count: 64))
        let cache = harness.store.generatedImageURL(sha256: String(repeating: "b", count: 64))
        try harness.store.writeDataAtomically(Data("orphan source".utf8), to: source)
        try harness.store.writeDataAtomically(Data("orphan cache".utf8), to: cache)

        let report = try harness.checker.inspect(cleanup: .removeProvableOrphans)

        XCTAssertTrue(report.issues.contains(.orphanSource(relativePath: try harness.store.managedRelativePath(for: source))))
        XCTAssertTrue(report.issues.contains(.orphanCache(relativePath: try harness.store.managedRelativePath(for: cache))))
        XCTAssertFalse(harness.store.fileExists(at: source))
        XCTAssertFalse(harness.store.fileExists(at: cache))
    }
}

private struct IntegrityHarness {
    let store: ManagedFileStore
    let assets: InMemoryAssetRepository
    let checker: ManagedAssetIntegrityChecker

    static func make() throws -> IntegrityHarness {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("EmulatorKit-Integrity-\(UUID().uuidString)", isDirectory: true)
        let store = try ManagedFileStore(rootURL: root)
        let assets = InMemoryAssetRepository()
        return IntegrityHarness(
            store: store,
            assets: assets,
            checker: ManagedAssetIntegrityChecker(assets: assets, assetStore: store)
        )
    }

    func insertSourceROM(bytes: Data) throws -> ManagedAsset {
        let source = rootTempFile(bytes)
        let staged = try store.stageCopy(from: source, transactionID: UUID())
        let sha = try store.hashFile(at: staged)
        let destination = try store.commitSourceROM(stagedURL: staged, sha256: sha)
        let asset = ManagedAsset(
            id: UUID(),
            kind: .sourceImage,
            storageClass: .source,
            contentSHA256: sha,
            byteLength: Int64(bytes.count),
            relativePath: try store.managedRelativePath(for: destination),
            integrityStatus: .verified,
            createdAt: Date()
        )
        try assets.insertAsset(asset)
        return asset
    }

    private func rootTempFile(_ bytes: Data) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("EmulatorKit-Integrity-Input-\(UUID())")
        try! bytes.write(to: url)
        return url
    }
}

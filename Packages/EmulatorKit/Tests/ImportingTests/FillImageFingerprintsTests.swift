import AssetStorage
import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import Importing
import Testing

@Suite("Launch fingerprint backfill")
struct FillImageFingerprintsTests {
    @Test("backfill retries unreadable images, skips finished work and cache, and removes purged rows")
    func backfill() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ManagedFileStore(rootURL: root)
        let fingerprints = InMemoryImageFingerprintRepository()
        let assets = InMemoryAssetRepository(fingerprints: fingerprints)
        func source(_ title: String, exists: Bool) throws -> (ManagedAsset, Data, URL) {
            let bytes = TestROM.make(title: title)
            let hash = store.hashData(bytes)
            let url = try store.sourceImageURL(sha256: hash)
            if exists { try store.writeDataAtomically(bytes, to: url) }
            let asset = ManagedAsset(id: UUID(), kind: .sourceImage, storageClass: .source, contentSHA256: hash,
                byteLength: Int64(bytes.count), relativePath: try store.managedRelativePath(for: url),
                integrityStatus: .verified, createdAt: .distantPast)
            try assets.insertAsset(asset)
            return (asset, bytes, url)
        }
        let good = try source("READABLE", exists: true)
        let missing = try source("MISSING", exists: false)
        let damaged = try source("DAMAGED", exists: true)
        try store.writeDataAtomically(Data(repeating: 0xff, count: 0x8000), to: damaged.2)
        let cache = ManagedAsset(id: UUID(), kind: .generatedImage, storageClass: .cache, contentSHA256: "cache",
            byteLength: 0x8000, relativePath: "Cache/GeneratedROM/cache.rom", integrityStatus: .verified, createdAt: .distantPast)
        try assets.insertAsset(cache)
        let fill = FillImageFingerprints(assets: assets, fingerprints: fingerprints, assetStore: store)
        #expect(try fill.execute() == 1)
        let row = try #require(try fingerprints.fetchFingerprints(imageSHA256s: [good.0.contentSHA256])[good.0.contentSHA256])
        #expect(row.headerTitle == "READABLE")
        #expect(row.bankHashes.count == 1)
        #expect(try fingerprints.fetchFingerprints(imageSHA256s: [missing.0.contentSHA256, damaged.0.contentSHA256, "cache"]).isEmpty)
        try store.removeIfExists(good.2)
        #expect(try fill.execute() == 0, "finished images are not read again, even if their files become unreadable")
        try store.writeDataAtomically(missing.1, to: missing.2)
        #expect(try fill.execute() == 1)
        #expect(try fill.execute() == 0)
        #expect(try fingerprints.fetchFingerprints(imageSHA256s: [good.0.contentSHA256])[good.0.contentSHA256] == row)
        try assets.deleteAsset(id: good.0.id)
        #expect(try fingerprints.fetchFingerprints(imageSHA256s: [good.0.contentSHA256]).isEmpty)
    }

    @Test("Check Library Files ignores fingerprint records")
    func integrity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ManagedFileStore(rootURL: root)
        let fingerprints = InMemoryImageFingerprintRepository()
        let assets = InMemoryAssetRepository(fingerprints: fingerprints)
        let image = TestROM.make(title: "MOON GARDEN")
        let sha256 = store.hashData(image)
        let url = try store.sourceImageURL(sha256: sha256)
        try store.writeDataAtomically(image, to: url)
        try assets.insertAsset(.init(id: UUID(), kind: .sourceImage, storageClass: .source, contentSHA256: sha256,
            byteLength: Int64(image.count), relativePath: try store.managedRelativePath(for: url), integrityStatus: .verified, createdAt: .now))
        #expect(try FillImageFingerprints(assets: assets, fingerprints: fingerprints, assetStore: store).execute() == 1)
        #expect(try ManagedAssetIntegrityChecker(assets: assets, assetStore: store).inspect().isClean)
        #expect(try assets.fetchAssets().count == 1)
    }
}

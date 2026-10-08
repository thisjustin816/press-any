import AssetStorage
import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import GRDB
import Importing
import Testing
@testable import PersistenceGRDB

@Suite("Development matching in GRDB")
struct DevelopmentMatchingPersistenceTests {
    @Test("200 Builds need six SELECTs, with aliases, fingerprints and reports fetched in bulk")
    func boundedQueries() throws {
        let database = try AppDatabase.inMemory()
        try database.migrate()
        let repositories = database.makeRepositories()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ManagedFileStore(rootURL: root)
        let file = root.appendingPathComponent("build.gb")
        try TestROM.make(title: "NEW", payloadByte: 1).write(to: file)
        let analyzer = ROMImportAnalyzer(builds: repositories.builds, games: repositories.games,
            fingerprints: repositories.fingerprints, toolchainReports: repositories.toolchainReports, assetStore: store)
        try database.writer.write { db in
            try GRDBTransactionContext.withDatabase(db) {
                for i in 0..<200 {
                    let sha256 = String(format: "%064x", i)
                    let game = Game(id: UUID(), primaryTitle: "Project \(i)", systemFamily: "gameboy", aliases: ["Alias \(i)"],
                        createdAt: .distantPast, modifiedAt: .distantPast)
                    let asset = ManagedAsset(id: UUID(), kind: .sourceImage, storageClass: .source, contentSHA256: sha256,
                        byteLength: 0x8000, relativePath: "Source/ROM/\(sha256).rom", integrityStatus: .verified, createdAt: .distantPast)
                    let build = Build(id: UUID(), gameID: game.id, system: .gameBoy, displayName: "Build", imageAssetID: asset.id,
                        imageSHA256: sha256, sourceKind: .importedImage, createdAt: .distantPast, modifiedAt: .distantPast)
                    try repositories.games.insertGame(game)
                    try repositories.assets.insertAsset(asset)
                    try repositories.builds.insertBuild(build)
                    try repositories.fingerprints.saveFingerprint(.init(imageSHA256: sha256, bankSize: 0x4000,
                        bankHashes: [UInt64(i)], headerTitle: "PROJECT\(i)", cartridgeType: 0, ramSizeCode: 0, cgbFlag: 0))
                    try repositories.toolchainReports.saveReport(.init(detector: "synthetic", detectorVersion: "1", corpusRevision: "1",
                        components: []), buildID: build.id, detectedAt: .distantPast)
                }
                var selects: [String] = []
                db.trace { event in
                    let sql = event.description.trimmingCharacters(in: .whitespacesAndNewlines)
                    if sql.hasPrefix("SELECT") { selects.append(sql) }
                }
                defer { db.trace(options: []) }
                let analysis = try analyzer.analyzeROM(at: file, targetGameID: nil)
                #expect(analysis.developmentCandidates.isEmpty)
                #expect(selects.count == 6, "\(selects)")
                #expect(selects.filter { $0.contains("image_fingerprints") }.count == 1)
                #expect(selects.filter { $0.contains("build_toolchain_reports") }.count == 1)
            }
        }
    }

    @Test("backfill persists across repository instances and leaves unreadable sources unfinished")
    func launchBackfill() throws {
        let database = try AppDatabase.inMemory()
        try database.migrate()
        let repositories = database.makeRepositories()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ManagedFileStore(rootURL: root)
        let image = TestROM.make(title: "MOON GARDEN", payloadByte: 1)
        let sha256 = store.hashData(image)
        let url = try store.sourceImageURL(sha256: sha256)
        try store.writeDataAtomically(image, to: url)
        try repositories.assets.insertAsset(.init(id: UUID(), kind: .sourceImage, storageClass: .source, contentSHA256: sha256,
            byteLength: Int64(image.count), relativePath: try store.managedRelativePath(for: url), integrityStatus: .verified, createdAt: .now))
        let missingHash = String(repeating: "f", count: 64)
        try repositories.assets.insertAsset(.init(id: UUID(), kind: .sourceImage, storageClass: .source, contentSHA256: missingHash,
            byteLength: 0x8000, relativePath: "Source/ROM/missing.rom", integrityStatus: .verified, createdAt: .now))
        #expect(try FillImageFingerprints(assets: repositories.assets,
        fingerprints: repositories.fingerprints,
        assetStore: store).execute() == 1)
        #expect(try ManagedAssetIntegrityChecker(assets: repositories.assets, assetStore: store).inspect().issues.count == 1)
        try store.removeIfExists(url)
        let nextLaunch = database.makeRepositories()
        #expect(try FillImageFingerprints(assets: nextLaunch.assets, fingerprints: nextLaunch.fingerprints, assetStore: store).execute() == 0)
        #expect(try nextLaunch.fingerprints.fetchFingerprints(imageSHA256s: [sha256])[sha256]?.headerTitle == "MOON GARDEN")
        #expect(try nextLaunch.fingerprints.fetchFingerprints(imageSHA256s: [missingHash]).isEmpty)
    }

    @Test("a failed import transaction rolls back its fingerprint with the source asset")
    func failedCommit() throws {
        let database = try AppDatabase.inMemory()
        try database.migrate()
        let repositories = database.makeRepositories()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ManagedFileStore(rootURL: root)
        let file = root.appendingPathComponent("build.gb")
        try TestROM.make(title: "MOON").write(to: file)
        let analysis = try ROMImportAnalyzer(builds: repositories.builds, games: repositories.games,
            fingerprints: repositories.fingerprints, toolchainReports: repositories.toolchainReports, assetStore: store)
            .analyzeROM(at: file, targetGameID: nil)
        let missingGame = UUID()
        let committer = ImportCommitter(games: repositories.games, builds: repositories.builds, assets: repositories.assets,
            toolchainReports: repositories.toolchainReports, fingerprints: repositories.fingerprints, assetStore: store,
            transactions: repositories.transactions)
        #expect(throws: ImportCommitterError.gameNotFound(missingGame)) {
            try committer.commit(.init(analysis: analysis, disposition: .addBuild(gameID: missingGame), buildDisplayName: "Build", markAsBase: false))
        }
        #expect(try repositories.fingerprints.fetchFingerprints(imageSHA256s: [analysis.sha256]).isEmpty)
        #expect(try repositories.assets.fetchAssets().isEmpty)
        #expect(!store.fileExists(at: try store.sourceImageURL(sha256: analysis.sha256)))
    }
}

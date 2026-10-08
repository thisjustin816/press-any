import AssetStorage
import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import GameIdentity
import Importing
import Testing
import ToolchainDetection

@Suite("Development import analysis")
struct DevelopmentImportTests {
    @Test("successive filenames find stored header evidence without source-file reads")
    func changedFilenames() throws {
        let h = try Harness()
        defer { try? FileManager.default.removeItem(at: h.root) }
        let first = try h.commit(h.analyze("mygame_v3.gb", title: "MOON GARDEN", payload: 1), title: "Moon Garden")
        let second = try h.commit(h.analyze("mygame-final.gb", title: "MOON GARDEN", payload: 2), gameID: first.game.id)
        #expect(try h.fingerprints.fetchFingerprints(imageSHA256s: [first.build.imageSHA256, second.build.imageSHA256]).count == 2)
        try h.store.removeIfExists(try h.store.sourceImageURL(sha256: first.build.imageSHA256))
        try h.store.removeIfExists(try h.store.sourceImageURL(sha256: second.build.imageSHA256))
        let arriving = try h.analyze("build.gb", title: "MOON GARDEN", payload: 3)
        #expect(arriving.suggestedGameID == nil)
        #expect(arriving.developmentCandidates.first?.gameID == first.game.id)
        #expect(arriving.developmentCandidates.first?.confidence == .high)
        #expect(arriving.developmentCandidates.first?.reasons.contains("same header title") == true)
        #expect(try h.builds.fetchAllBuilds().count == 2, "analysis never attaches the arriving Build")
    }

    @Test("changed header with mostly shared banks and one support is medium")
    func rebuilt() throws {
        let h = try Harness()
        defer { try? FileManager.default.removeItem(at: h.root) }
        let old = TestROM.make(title: "MOON", banks: [1, 2, 3, 4].map { Data(repeating: $0, count: 0x4000) })
        let first = try h.commit(h.analyze("old.gb", image: old), title: "Moon Garden")
        let rebuilt = TestROM.make(title: "LUNAR", cgb: true,
            banks: [9, 2, 3, 4].map { Data(repeating: $0, count: 0x4000) }, cartridgeType: 1)
        let analysis = try h.analyze("new.gb", image: rebuilt)
        #expect(analysis.developmentCandidates.first?.gameID == first.game.id)
        #expect(analysis.developmentCandidates.first?.confidence == .medium)
        #expect(analysis.developmentCandidates.first?.reasons.contains("75% of ROM banks shared") == true)
    }

    @Test("unrelated homebrew with the same cartridge and detected toolchain is not offered")
    func unrelated() throws {
        let h = try Harness()
        defer { try? FileManager.default.removeItem(at: h.root) }
        _ = try h.commit(h.analyze("old.gb", title: "MOON", payload: 1), title: "Moon Garden")
        let analysis = try h.analyze("other.gb", title: "OTHER", payload: 2)
        #expect(!analysis.toolchainReports.isEmpty)
        #expect(analysis.developmentCandidates.isEmpty)
    }

    @Test("No-Intro dumps and exact duplicates bypass development queries")
    func precedence() throws {
        let h = try Harness()
        defer { try? FileManager.default.removeItem(at: h.root) }
        let image = TestROM.make(title: "MOON", payloadByte: 1)
        let dump = KnownDump(name: "Moon (USA)", system: .gameBoy, title: "Moon", region: "USA", languages: "En",
            files: [KnownDumpFile(sha1: SHA1Digest.data(image), size: Int64(image.count))])
        let index = try KnownDumpIndex(catalog: .init(source: "synthetic", generated: "", systems: [], games: [dump]))
        let analyzer = ROMImportAnalyzer(builds: h.builds, games: h.games, fingerprints: UnreadableFingerprints(),
            toolchainReports: UnreadableReports(), assetStore: h.store, knownDumps: index)
        let file = h.root.appendingPathComponent("known.gb")
        try image.write(to: file)
        let known = try analyzer.analyzeROM(at: file, targetGameID: nil)
        #expect(known.knownDump == dump)
        #expect(known.developmentCandidates.isEmpty)
        let result = try h.commit(known, title: "Moon")
        let unknownAnalyzer = ROMImportAnalyzer(builds: h.builds, games: h.games, fingerprints: UnreadableFingerprints(),
            toolchainReports: UnreadableReports(), assetStore: h.store)
        let duplicate = try unknownAnalyzer.analyzeROM(at: file, targetGameID: nil)
        #expect(duplicate.exactExistingBuildID == result.build.id)
        #expect(duplicate.developmentCandidates.isEmpty)
    }

    private struct Harness {
        let root: URL
        let store: ManagedFileStore
        let games = InMemoryGameRepository()
        let builds = InMemoryBuildRepository()
        let fingerprints = InMemoryImageFingerprintRepository()
        let reports = InMemoryToolchainReportRepository()
        let assets: InMemoryAssetRepository

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            store = try ManagedFileStore(rootURL: root)
            assets = InMemoryAssetRepository(fingerprints: fingerprints)
        }

        func analyze(_ filename: String, title: String, payload: UInt8) throws -> ROMImportAnalysis {
            try analyze(filename, image: TestROM.make(title: title, payloadByte: payload))
        }

        func analyze(_ filename: String, image: Data) throws -> ROMImportAnalysis {
            let file = root.appendingPathComponent(filename)
            try image.write(to: file)
            return try ROMImportAnalyzer(builds: builds, games: games, fingerprints: fingerprints,
                toolchainReports: reports, assetStore: store, detectors: .init(detectors: [SyntheticDetector()]))
                .analyzeROM(at: file, targetGameID: nil)
        }

        func commit(_ analysis: ROMImportAnalysis, title: String = "Moon Garden", gameID: UUID? = nil) throws -> ROMImportResult {
            try ImportCommitter(games: games, builds: builds, assets: assets, toolchainReports: reports,
                fingerprints: fingerprints, assetStore: store, transactions: PassthroughTransactionRunner())
                .commit(.init(analysis: analysis, disposition: gameID.map { .addBuild(gameID: $0) } ?? .createGame(title: title),
                    buildDisplayName: "Build", markAsBase: false))
        }
    }
}

private struct SyntheticDetector: ToolchainDetector {
    let identifier = "synthetic"
    func supports(_ system: GameSystem) -> Bool { true }
    func detect(image: Data) -> ToolchainDetectionReport {
        .init(detector: identifier, detectorVersion: "1", corpusRevision: "1", components: [
            .init(kind: .toolchain, name: "GBDK", version: "1", evidence: [.init(signature: "synthetic", offset: 0)]),
        ])
    }
}

private struct UnreadableFingerprints: ImageFingerprintRepository {
    func saveFingerprint(_ fingerprint: ImageFingerprint) throws { throw CocoaError(.fileWriteUnknown) }
    func fetchFingerprints(imageSHA256s: [String]) throws -> [String: ImageFingerprint] { throw CocoaError(.fileReadUnknown) }
    func deleteFingerprint(imageSHA256: String) throws { throw CocoaError(.fileWriteUnknown) }
}

private struct UnreadableReports: ToolchainReportRepository {
    func saveReport(_ report: ToolchainDetectionReport, buildID: UUID, detectedAt: Date) throws { throw CocoaError(.fileWriteUnknown) }
    func fetchReports(buildID: UUID) throws -> [ToolchainDetectionReport] { throw CocoaError(.fileReadUnknown) }
    func fetchAllReports() throws -> [UUID: [ToolchainDetectionReport]] { throw CocoaError(.fileReadUnknown) }
}

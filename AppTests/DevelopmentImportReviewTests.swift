import AssetStorage
import EmulatorApplication
import EmulatorDomain
import Foundation
import GameIdentity
import Importing
import QuickPlay
import Testing
import ToolchainDetection
@testable import PressAny

@MainActor
@Suite("Development Import Review")
struct DevelopmentImportReviewTests {
    @Test("a third build preselects its Game and shows the reasons without importing")
    func thirdBuild() throws {
        let h = try Harness()
        defer { try? FileManager.default.removeItem(at: h.root) }
        let original = try h.review("mygame_v3.gb", image: TestROM.make(title: "MOON GARDEN", payloadByte: 1))
        original.gameTitle = "Moon Garden"
        let first = try original.commit()
        let second = try h.review("mygame-final.gb", image: TestROM.make(title: "MOON GARDEN", payloadByte: 2))
        second.destination = .existing(first.game.id)
        second.destinationChanged()
        _ = try second.commit()
        let third = try h.review("build.gb", image: TestROM.make(title: "MOON GARDEN", payloadByte: 3))
        #expect(third.destination == .existing(first.game.id))
        #expect(third.developmentEvidence?.hasPrefix("Likely another build of Moon Garden:") == true)
        #expect(third.developmentEvidence?.contains("same header title") == true)
        #expect(third.markAsBase && third.markAsPreferred)
        #expect(try h.builds.fetchAllBuilds().count == 2)
    }

    @Test("changed header at medium confidence keeps New Game and lists the suggested Game first")
    func medium() throws {
        let h = try Harness()
        defer { try? FileManager.default.removeItem(at: h.root) }
        let first = try h.review("Moon Garden.gb", image: TestROM.make(title: "MOON",
            banks: [1, 2, 3, 4].map { Data(repeating: $0, count: 0x4000) })).commit()
        _ = try h.review("Alphabet.gb", image: TestROM.make(title: "ALPHABET", payloadByte: 0xee)).commit()
        let rebuilt = TestROM.make(title: "LUNAR", cgb: true,
            banks: [9, 2, 3, 4].map { Data(repeating: $0, count: 0x4000) }, cartridgeType: 1)
        let review = try h.review("new.gb", image: rebuilt)
        #expect(review.destination == .newGame)
        #expect(review.games.first?.id == first.game.id)
        #expect(review.developmentEvidence?.hasPrefix("Possibly another build of Moon Garden:") == true)
        #expect(review.developmentEvidence?.contains("75% of ROM banks shared") == true)
        review.destination = .existing(first.game.id)
        review.destinationChanged()
        #expect(review.plan.disposition == .addBuild(gameID: first.game.id))
        #expect(review.markAsBase && review.markAsPreferred)
        review.markAsBase = false
        review.markAsPreferred = false
        review.destination = .newGame
        review.destinationChanged()
        #expect(!review.markAsBase && !review.markAsPreferred)
    }

    @Test("unrelated homebrew sharing hardware and toolchain has no evidence or preselection")
    func unrelated() throws {
        let h = try Harness()
        defer { try? FileManager.default.removeItem(at: h.root) }
        _ = try h.review("Moon Garden.gb", image: TestROM.make(title: "MOON", payloadByte: 1)).commit()
        let review = try h.review("other.gb", image: TestROM.make(title: "OTHER", payloadByte: 2))
        #expect(review.destination == .newGame)
        #expect(review.developmentEvidence == nil)
    }

    @Test("Quick Play promotion receives the same destination and evidence")
    func promotion() throws {
        let h = try Harness()
        defer { try? FileManager.default.removeItem(at: h.root) }
        let first = try h.review("Moon Garden.gb", image: TestROM.make(title: "MOON", payloadByte: 1)).commit()
        let file = h.root.appendingPathComponent("build.gb")
        try TestROM.make(title: "MOON", payloadByte: 2).write(to: file)
        let normal = h.model(try h.coordinator.analyzeROM(at: file))
        let profiles = InMemorySaveProfileRepository()
        let states = InMemorySaveStateRepository()
        let workspace = QuickPlayWorkspace(profiles: profiles, assets: h.assets, assetStore: h.store)
        let session = try workspace.start(romURL: file)
        let promoter = PromoteQuickPlay(analyzer: h.coordinator.analyzer, committer: h.coordinator.committer,
            workspace: workspace, builds: h.builds, profiles: profiles, states: states, assets: h.assets, assetStore: h.store)
        let promotion = h.model(try promoter.analyze(session, targetGameID: nil))
        #expect(promotion.destination == .existing(first.game.id))
        #expect(promotion.destination == normal.destination)
        #expect(promotion.developmentEvidence == normal.developmentEvidence)
        #expect(try h.builds.fetchAllBuilds().count == 1)
    }

    @Test("a split No-Intro family retains precedence over ranked development candidates")
    func familySplit() throws {
        let h = try Harness()
        defer { try? FileManager.default.removeItem(at: h.root) }
        let first = try h.review("First.gb", image: TestROM.make(title: "FIRST", payloadByte: 1)).commit()
        let second = try h.review("Second.gb", image: TestROM.make(title: "SECOND", payloadByte: 2)).commit()
        let original = try h.coordinator.analyzeROM(at: h.write("new.gb", image: TestROM.make(title: "FIRST", payloadByte: 3)))
        let analysis = ROMImportAnalysis(transactionID: original.transactionID, stagedURL: original.stagedURL,
            originalFilename: original.originalFilename, sha256: original.sha256, byteLength: original.byteLength,
            header: original.header, filenameMetadata: original.filenameMetadata, exactExistingBuildID: nil, suggestedGameID: nil,
            familyGameIDs: [second.game.id, first.game.id], developmentCandidates: original.developmentCandidates)
        let review = h.model(analysis)
        #expect(review.destination == .newGame)
        #expect(Set(review.games.prefix(2).map(\.id)) == Set([first.game.id, second.game.id]))
    }

    @MainActor
    private struct Harness {
        let root: URL
        let store: ManagedFileStore
        let games = InMemoryGameRepository()
        let builds = InMemoryBuildRepository()
        let fingerprints = InMemoryImageFingerprintRepository()
        let reports = InMemoryToolchainReportRepository()
        let assets: InMemoryAssetRepository
        let coordinator: ImportCoordinator

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            store = try ManagedFileStore(rootURL: root)
            assets = InMemoryAssetRepository(fingerprints: fingerprints)
            coordinator = ImportCoordinator(analyzer: ROMImportAnalyzer(builds: builds, games: games, fingerprints: fingerprints,
                toolchainReports: reports, assetStore: store, detectors: .init(detectors: [SyntheticDetector()])),
                committer: ImportCommitter(games: games, builds: builds, assets: assets, toolchainReports: reports,
                    fingerprints: fingerprints, assetStore: store, transactions: PassthroughTransactionRunner()), assetStore: store)
        }

        func write(_ name: String, image: Data) throws -> URL {
            let file = root.appendingPathComponent(name)
            try image.write(to: file)
            return file
        }

        func review(_ name: String, image: Data) throws -> ImportReviewViewModel {
            model(try coordinator.analyzeROM(at: write(name, image: image)))
        }

        func model(_ analysis: ROMImportAnalysis) -> ImportReviewViewModel {
            ImportReviewViewModel(analysis: analysis, games: (try? games.fetchGames()) ?? [], coordinator: coordinator,
                existingBuilds: { (try? builds.fetchBuilds(gameID: $0)) ?? [] })
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
}

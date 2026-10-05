import AssetStorage
import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import XCTest
@testable import Importing

final class ROMImportTests: XCTestCase {
    func testImportSameROMTwiceDetectsExistingBuildAndDeduplicatesBlob() throws {
        let harness = try ImportHarness.make()
        let romURL = try harness.writeExternalROM(TestROM.make(title: "SAME", cgb: false))

        let firstAnalysis = try harness.analyzer.analyzeROM(at: romURL, targetGameID: nil)
        let first = try harness.committer.commit(
            ROMImportPlan(
                analysis: firstAnalysis,
                disposition: .createGame(title: "Same"),
                buildDisplayName: "Original",
                markAsBase: true
            )
        )
        let secondAnalysis = try harness.analyzer.analyzeROM(at: romURL, targetGameID: nil)

        XCTAssertEqual(secondAnalysis.exactExistingBuildID, first.build.id)
        XCTAssertEqual(try harness.sourceROMFileCount(), 1)
    }

    func testAFileLargerThanAnyCartridgeIsRefusedBeforeItIsStaged() throws {
        let harness = try ImportHarness.make()
        let huge = try ImportTestFiles.sparse(at: harness.external.appendingPathComponent("huge.gb"), byteCount: 9 * 1_048_576)

        XCTAssertThrowsError(try harness.analyzer.analyzeROM(at: huge, targetGameID: nil)) {
            XCTAssertEqual($0 as? ImportSizeError, .fileTooLarge(limit: 8 * 1_048_576))
            XCTAssertEqual($0.localizedDescription, "This file is larger than 8 MB, the most this kind of file can be.")
        }
        XCTAssertEqual(ImportTestFiles.stagedItems(under: harness.store.rootURL), [])
    }

    func testImportReviewShowsToolchainFindingsAndTheBuildKeepsThem() throws {
        let harness = try ImportHarness.make()
        // Turbo Rascal's marker is the header title "TRSE GB" with its terminating zero.
        let romURL = try harness.writeExternalROM(TestROM.make(title: "TRSE GB"))
        let analysis = try harness.analyzer.analyzeROM(at: romURL, targetGameID: nil)
        XCTAssertEqual(analysis.toolchainReports.flatMap(\.components).map(\.name), ["Turbo Rascal Syntax Error"])

        let result = try harness.committer.commit(ROMImportPlan(
            analysis: analysis,
            disposition: .createGame(title: "Rascal"),
            buildDisplayName: "Original",
            markAsBase: true
        ))
        XCTAssertEqual(try harness.toolchainReports.fetchReports(buildID: result.build.id), analysis.toolchainReports)
        XCTAssertEqual(result.game.primaryTitle, "Rascal", "detection never names the Game")
    }

    func testAnUnrecognizedImageStoresAnEmptyReport() throws {
        let harness = try ImportHarness.make()
        let romURL = try harness.writeExternalROM(TestROM.make(title: "PLAIN"))
        let result = try harness.committer.commit(ROMImportPlan(
            analysis: try harness.analyzer.analyzeROM(at: romURL, targetGameID: nil),
            disposition: .createGame(title: "Plain"),
            buildDisplayName: "Original",
            markAsBase: true
        ))

        let reports = try harness.toolchainReports.fetchReports(buildID: result.build.id)
        XCTAssertEqual(reports.map(\.detector), ["gbtoolsid"], "unknown is a result, not a missing one")
        XCTAssertEqual(reports.first?.components, [])
    }

    func testAddingABuildByDetectionLeavesTheGameAsItWas() throws {
        let harness = try ImportHarness.make()
        let first = try harness.committer.commit(ROMImportPlan(
            analysis: try harness.analyzer.analyzeROM(at: harness.writeExternalROM(TestROM.make(title: "PLAIN")), targetGameID: nil),
            disposition: .createGame(title: "Plain"),
            buildDisplayName: "Original",
            markAsBase: true
        ))
        let second = try harness.committer.commit(ROMImportPlan(
            analysis: try harness.analyzer.analyzeROM(at: harness.writeExternalROM(TestROM.make(title: "TRSE GB")), targetGameID: first.game.id),
            disposition: .addBuild(gameID: first.game.id),
            buildDisplayName: "Rebuilt",
            markAsBase: false
        ))

        XCTAssertEqual(second.game.id, first.game.id)
        XCTAssertEqual(try harness.games.fetchGame(id: first.game.id), first.game)
        XCTAssertEqual(try harness.toolchainReports.fetchReports(buildID: second.build.id).first?.components.map(\.name), ["Turbo Rascal Syntax Error"])
    }

    func testImportingTheSameROMAgainRepairsADamagedSourceFile() throws {
        let harness = try ImportHarness.make()
        let romURL = try harness.writeExternalROM(TestROM.make(title: "REPAIR", cgb: false))
        let first = try harness.committer.commit(ROMImportPlan(
            analysis: try harness.analyzer.analyzeROM(at: romURL, targetGameID: nil),
            disposition: .createGame(title: "Repair"),
            buildDisplayName: "Original",
            markAsBase: true
        ))
        let stored = try harness.store.managedURL(relativePath: first.sourceAsset.relativePath)
        try Data("damaged".utf8).write(to: stored)

        let again = try harness.analyzer.analyzeROM(at: romURL, targetGameID: nil)
        _ = try harness.committer.commit(ROMImportPlan(
            analysis: again,
            disposition: .duplicateExisting(buildID: try XCTUnwrap(again.exactExistingBuildID)),
            buildDisplayName: "Original",
            markAsBase: false
        ))
        XCTAssertEqual(try harness.store.hashFile(at: stored), first.build.imageSHA256)
    }

    func testModifiedROMCanAttachAsSecondBuildWithoutChangingGameIdentity() throws {
        let harness = try ImportHarness.make()
        let baseURL = try harness.writeExternalROM(TestROM.make(title: "TEST", cgb: true, payloadByte: 1))
        let baseAnalysis = try harness.analyzer.analyzeROM(at: baseURL, targetGameID: nil)
        let base = try harness.committer.commit(
            ROMImportPlan(
                analysis: baseAnalysis,
                disposition: .createGame(title: "Test"),
                buildDisplayName: "Original",
                markAsBase: true
            )
        )

        let modifiedURL = try harness.writeExternalROM(TestROM.make(title: "TEST", cgb: true, payloadByte: 2))
        let analysis = try harness.analyzer.analyzeROM(at: modifiedURL, targetGameID: base.game.id)
        let result = try harness.committer.commit(
            ROMImportPlan(
                analysis: analysis,
                disposition: .addBuild(gameID: base.game.id),
                buildDisplayName: "Test Build 2",
                markAsBase: false
            )
        )

        XCTAssertEqual(result.game.id, base.game.id)
        XCTAssertNotEqual(result.build.id, base.build.id)
        XCTAssertEqual(try harness.builds.fetchBuilds(gameID: base.game.id).count, 2)
    }

    func testFailedTransactionRemovesOnlyNewlyCreatedManagedFile() throws {
        let harness = try ImportHarness.make(transactionRunner: FailingTransactionRunner())
        let romURL = try harness.writeExternalROM(TestROM.make(title: "FAIL", cgb: false))
        let analysis = try harness.analyzer.analyzeROM(at: romURL, targetGameID: nil)

        XCTAssertThrowsError(
            try harness.committer.commit(
                ROMImportPlan(
                    analysis: analysis,
                    disposition: .createGame(title: "Fail"),
                    buildDisplayName: "Original",
                    markAsBase: true
                )
            )
        )
        XCTAssertEqual(try harness.sourceROMFileCount(), 0)
    }
}

private struct ImportHarness {
    let root: URL
    let external: URL
    let store: ManagedFileStore
    let games: InMemoryGameRepository
    let builds: InMemoryBuildRepository
    let assets: InMemoryAssetRepository
    let toolchainReports: InMemoryToolchainReportRepository
    let analyzer: ROMImportAnalyzer
    let committer: ImportCommitter

    static func make(transactionRunner: any LibraryTransactionRunner = PassthroughTransactionRunner()) throws -> ImportHarness {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("EmulatorKit-ImportTests-\(UUID().uuidString)", isDirectory: true)
        let external = root.appendingPathComponent("External", isDirectory: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let store = try ManagedFileStore(rootURL: root.appendingPathComponent("Managed", isDirectory: true))
        let games = InMemoryGameRepository()
        let builds = InMemoryBuildRepository()
        let assets = InMemoryAssetRepository()
        let toolchainReports = InMemoryToolchainReportRepository()
        let analyzer = ROMImportAnalyzer(builds: builds, assetStore: store)
        let committer = ImportCommitter(
            games: games,
            builds: builds,
            assets: assets,
            toolchainReports: toolchainReports,
            assetStore: store,
            transactions: transactionRunner,
            now: { Date(timeIntervalSince1970: 100) }
        )
        return ImportHarness(
            root: root,
            external: external,
            store: store,
            games: games,
            builds: builds,
            assets: assets,
            toolchainReports: toolchainReports,
            analyzer: analyzer,
            committer: committer
        )
    }

    func writeExternalROM(_ data: Data) throws -> URL {
        let url = external.appendingPathComponent("\(UUID().uuidString).gb")
        try data.write(to: url)
        return url
    }

    func sourceROMFileCount() throws -> Int {
        let root = store.rootURL.appendingPathComponent("Source/ROM", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return 0 }
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        var count = 0
        while let item = enumerator?.nextObject() as? URL {
            if !item.hasDirectoryPath { count += 1 }
        }
        return count
    }
}

private struct TransactionFailure: Error {}

private struct FailingTransactionRunner: LibraryTransactionRunner {
    func run<T: Sendable>(_ operation: @Sendable () throws -> T) throws -> T {
        _ = operation
        throw TransactionFailure()
    }
}

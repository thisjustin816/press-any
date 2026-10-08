import AssetStorage
import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import GameIdentity
import Testing
import XCTest
@testable import Importing

final class ROMImportTests: XCTestCase {
    func testImportPersistsFilenameMetadataAndAnExplicitReviewOverride() throws {
        let harness = try ImportHarness.make()
        let file = harness.external.appendingPathComponent("Example (Europe) (En,Fr) (Rev 2) [v1.10].gb")
        try TestROM.make(title: "EXAMPLE").write(to: file)
        let analysis = try harness.analyzer.analyzeROM(at: file, targetGameID: nil)
        let result = try harness.committer.commit(ROMImportPlan(
            analysis: analysis, disposition: .createGame(title: "Example"), buildDisplayName: "Revision 2", markAsBase: true
        ))
        XCTAssertEqual(result.build.region, "Europe")
        XCTAssertEqual(result.build.language, "En, Fr")
        XCTAssertEqual(result.build.revision, "2")
        XCTAssertEqual(result.build.versionString, "1.10")
        XCTAssertEqual(result.build.versionSortKey, BuildImportMetadata(versionString: "1.10").versionSortKey)
        XCTAssertEqual(try harness.builds.fetchBuild(id: result.build.id), result.build)
        XCTAssertEqual(result.sourceAsset.originalFilename, file.lastPathComponent)

        let nextFile = harness.external.appendingPathComponent("Example (Japan) [v2.0].gb")
        try TestROM.make(title: "EXAMPLE", payloadByte: 1).write(to: nextFile)
        let next = try harness.committer.commit(ROMImportPlan(
            analysis: try harness.analyzer.analyzeROM(at: nextFile, targetGameID: result.game.id),
            disposition: .addBuild(gameID: result.game.id), buildDisplayName: "Custom", markAsBase: false,
            markAsPreferred: true,
            metadata: BuildImportMetadata(
                region: "World",
                versionString: "beta",
                baseTitle: "Example",
                hackTitle: "Example Plus",
                author: "Tester",
                translation: "Spanish",
                status: "Beta"
            )
        ))
        XCTAssertEqual(next.build.region, "World")
        XCTAssertNil(next.build.language)
        XCTAssertNil(next.build.revision)
        XCTAssertEqual(next.build.versionString, "beta")
        XCTAssertNil(next.build.versionSortKey)
        XCTAssertEqual(next.build.baseTitle, "Example")
        XCTAssertEqual(next.build.hackTitle, "Example Plus")
        XCTAssertEqual(next.build.author, "Tester")
        XCTAssertEqual(next.build.translation, "Spanish")
        XCTAssertEqual(next.build.status, "Beta")
        XCTAssertEqual(next.game.id, result.game.id)
        XCTAssertEqual(next.game.preferredBuildID, next.build.id)
        XCTAssertEqual(try harness.games.fetchGame(id: result.game.id)?.preferredBuildID, next.build.id)
        XCTAssertEqual(try harness.builds.fetchBuild(id: result.build.id), result.build)
    }

    func testNonzeroHeaderRevisionIsFallbackAndCanBeClearedInReview() throws {
        let harness = try ImportHarness.make()
        var rom = TestROM.make(title: "REVISION")
        rom[0x14c] = 3
        let file = try harness.writeExternalROM(rom)
        let analysis = try harness.analyzer.analyzeROM(at: file, targetGameID: nil)
        XCTAssertEqual(analysis.header.revisionNumber, 3)
        let plan = ROMImportPlan(analysis: analysis, disposition: .createGame(title: "Revision"), buildDisplayName: "Original", markAsBase: true)
        XCTAssertEqual(plan.metadata.revision, "3")
        let cleared = try harness.committer.commit(ROMImportPlan(
            analysis: analysis, disposition: plan.disposition, buildDisplayName: "Original", markAsBase: true, metadata: BuildImportMetadata()
        ))
        XCTAssertNil(cleared.build.revision)
    }

    func testFilenameRevisionWinsOverHeaderAndDuplicateDoesNotOverwriteMetadata() throws {
        let harness = try ImportHarness.make()
        var rom = TestROM.make(title: "REVISION")
        rom[0x14c] = 3
        let file = harness.external.appendingPathComponent("Example (Rev A).gb")
        try rom.write(to: file)
        let result = try harness.committer.commit(ROMImportPlan(
            analysis: try harness.analyzer.analyzeROM(at: file, targetGameID: nil),
            disposition: .createGame(title: "Example"), buildDisplayName: "Original", markAsBase: true
        ))
        XCTAssertEqual(result.build.revision, "A")
        let again = try harness.committer.commit(ROMImportPlan(
            analysis: try harness.analyzer.analyzeROM(at: file, targetGameID: nil),
            disposition: .duplicateExisting(buildID: result.build.id), buildDisplayName: "Changed", markAsBase: false,
            metadata: BuildImportMetadata(region: "Japan", revision: "9")
        ))
        XCTAssertEqual(again.build, result.build)
        XCTAssertFalse(again.createdNewBuild)
    }

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

    func testImportingANewBaseBuildDemotesThePreviousBase() throws {
        let harness = try ImportHarness.make()
        let first = try harness.committer.commit(ROMImportPlan(
            analysis: try harness.analyzer.analyzeROM(
                at: harness.writeExternalROM(TestROM.make(title: "FIRST", payloadByte: 1)),
                targetGameID: nil
            ),
            disposition: .createGame(title: "Example"),
            buildDisplayName: "1.0",
            markAsBase: true
        ))
        let second = try harness.committer.commit(ROMImportPlan(
            analysis: try harness.analyzer.analyzeROM(
                at: harness.writeExternalROM(TestROM.make(title: "SECOND", payloadByte: 2)),
                targetGameID: first.game.id
            ),
            disposition: .addBuild(gameID: first.game.id),
            buildDisplayName: "2.0",
            markAsBase: true
        ))

        let bases = try harness.builds.fetchBuilds(gameID: first.game.id).filter(\.isBase)
        XCTAssertEqual(bases.map(\.id), [second.build.id])
        XCTAssertEqual(try harness.builds.fetchBuild(id: first.build.id)?.isBase, false)
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

    func testAnotherBuildOfAProjectFindsItsGameByHeaderTitle() throws {
        let harness = try ImportHarness.make()
        func importNewGame(title: String, payload: UInt8) throws -> ROMImportResult {
            let url = try harness.writeExternalROM(TestROM.make(title: title, cgb: true, payloadByte: payload))
            return try harness.committer.commit(ROMImportPlan(
                analysis: try harness.analyzer.analyzeROM(at: url, targetGameID: nil),
                disposition: .createGame(title: title),
                buildDisplayName: "Master",
                markAsBase: true
            ))
        }
        let project = try importNewGame(title: "gametitleNIS", payload: 1)
        _ = try importNewGame(title: "OTHERGAME", payload: 2)

        let next = try harness.writeExternalROM(TestROM.make(title: "gametitleNIS", cgb: true, payloadByte: 3))
        let analysis = try harness.analyzer.analyzeROM(at: next, targetGameID: nil)
        XCTAssertEqual(analysis.headerTitleGameIDs, [project.game.id])

        // A header title shared by Builds in two Games suggests neither.
        _ = try importNewGame(title: "gametitleNIS", payload: 4)
        let ambiguous = try harness.analyzer.analyzeROM(
            at: try harness.writeExternalROM(TestROM.make(title: "gametitleNIS", cgb: true, payloadByte: 5)),
            targetGameID: nil
        )
        XCTAssertEqual(ambiguous.headerTitleGameIDs.count, 2)

        // Titles too short to tell projects apart match nothing.
        _ = try importNewGame(title: "AB", payload: 6)
        let short = try harness.analyzer.analyzeROM(
            at: try harness.writeExternalROM(TestROM.make(title: "AB", cgb: true, payloadByte: 7)),
            targetGameID: nil
        )
        XCTAssertEqual(short.headerTitleGameIDs, [])
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

@Suite("ROM metadata provenance")
struct ROMMetadataProvenanceTests {
    @Test("every parsed Build field keeps its filename source and confidence")
    func filenameFields() throws {
        let harness = try ImportHarness.make()
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let url = harness.external.appendingPathComponent(
            "Crystal Clear (USA) (En,Fr) (Rev A) [Base: Pokemon Crystal] [Hack: Crystal Clear] [Translation: Spanish] [Author: ShockSlayer] [v2.5.10] [Beta].gb")
        try TestROM.make(title: "HEADER").write(to: url)
        let analysis = try harness.analyzer.analyzeROM(at: url, targetGameID: nil)
        let result = try harness.committer.commit(ROMImportPlan(analysis: analysis,
            disposition: .createGame(title: "Crystal Clear"), buildDisplayName: analysis.filenameMetadata.suggestedBuildName, markAsBase: false))
        let rows = try harness.builds.fetchMetadataProvenance(ownerID: result.build.id)
        #expect(rows.count == 10)
        for row in rows {
            #expect(row.source == .filename)
            #expect(row.confidence == .high)
            #expect(row.providedValue == row.field.value(in: result.build))
            #expect(row.recordedAt == Date(timeIntervalSince1970: 100))
        }
        let title = try #require(try harness.games.fetchMetadataProvenance(ownerID: result.game.id).first)
        #expect(title.source == .filename)
        #expect(!result.game.hasPlayerTitle)
    }

    @Test("review-generated distinct names and matched hack titles keep filename evidence")
    func derivedSuggestions() throws {
        let harness = try ImportHarness.make()
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let url = harness.external.appendingPathComponent("Example.gb")
        try TestROM.make(title: "HEADER").write(to: url)
        let analysis = try harness.analyzer.analyzeROM(at: url, targetGameID: nil)
        let reference = BaseGameReference(title: "Base", system: .gameBoy)
        var metadata = BuildImportMetadata(analysis: analysis)
        metadata.baseTitle = "Base"
        metadata.hackTitle = "Example"
        let result = try harness.committer.commit(ROMImportPlan(analysis: analysis,
            disposition: .createGame(title: "Example"), buildDisplayName: "2026-10-07", markAsBase: false,
            metadata: metadata, baseGameReference: reference, suggestedBuildDisplayName: "2026-10-07"))
        let rows = try harness.builds.fetchMetadataProvenance(ownerID: result.build.id)
        #expect(rows.first { $0.field == .displayName }?.source == .filename)
        #expect(rows.first { $0.field == .displayName }?.providedValue == "2026-10-07")
        #expect(rows.first { $0.field == .hackTitle }?.source == .filename)
        #expect(rows.first { $0.field == .baseTitle }?.source == .player)
    }

    @Test("matched No-Intro base titles keep their source and review can clear them", arguments: [false, true])
    func matchedBaseTitle(clear: Bool) throws {
        let harness = try ImportHarness.make()
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let url = harness.external.appendingPathComponent("Example.gb")
        try TestROM.make(title: "HEADER").write(to: url)
        let analysis = try harness.analyzer.analyzeROM(at: url, targetGameID: nil)
        let reference = BaseGameReference(title: "Catalog Base", system: .gameBoy,
            familyName: "Catalog Base (USA)", releaseName: "Catalog Base (USA)")
        let result = try harness.committer.commit(ROMImportPlan(analysis: analysis,
            disposition: .createGame(title: "Example"), buildDisplayName: analysis.filenameMetadata.suggestedBuildName,
            markAsBase: false, metadata: clear ? BuildImportMetadata() : nil, baseGameReference: reference))
        let row = try #require(try harness.builds.fetchMetadataProvenance(ownerID: result.build.id).first { $0.field == .baseTitle })
        #expect(row.source == (clear ? .player : .noIntro))
        #expect(row.confidence == (clear ? nil : .high))
        #expect(row.providedValue == "Catalog Base")
        #expect(result.build.baseTitle == (clear ? nil : "Catalog Base"))
        #expect(result.build.baseGameReference == reference)
    }

    @Test("adopting a filename hack title records filename provenance on the Game")
    func adoptedHackTitle() throws {
        let harness = try ImportHarness.make()
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let game = Game(id: UUID(), primaryTitle: "Base", systemFamily: "gameboy", hasPlayerTitle: true,
            createdAt: Date(timeIntervalSince1970: 10), modifiedAt: Date(timeIntervalSince1970: 10))
        try harness.games.insertGame(game)
        let url = harness.external.appendingPathComponent("Base - Base Plus [Hack] [v1.2].gb")
        try TestROM.make(title: "HEADER").write(to: url)
        let analysis = try harness.analyzer.analyzeROM(at: url, targetGameID: game.id)
        let result = try harness.committer.commit(ROMImportPlan(analysis: analysis,
            disposition: .addBuild(gameID: game.id), buildDisplayName: analysis.filenameMetadata.suggestedBuildName,
            markAsBase: false, markAsPreferred: true, proposedGameTitle: "Base Plus"))
        #expect(result.game.primaryTitle == "Base Plus")
        #expect(!result.game.hasPlayerTitle)
        let row = try #require(try harness.games.fetchMetadataProvenance(ownerID: game.id).first)
        #expect(row.source == .filename)
        #expect(row.confidence == .high)
        #expect(row.providedValue == "Base Plus")
        #expect(try harness.games.fetchGame(id: game.id)?.hasPlayerTitle == false)
    }

    @Test("filename confidence survives import", arguments: ["Example.gb", "Example [Unknown].gb", "Example (USA).gb"])
    func confidence(filename: String) throws {
        let harness = try ImportHarness.make()
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let url = harness.external.appendingPathComponent(filename)
        try TestROM.make(title: "HEADER").write(to: url)
        let analysis = try harness.analyzer.analyzeROM(at: url, targetGameID: nil)
        let result = try harness.committer.commit(ROMImportPlan(analysis: analysis,
            disposition: .createGame(title: analysis.filenameMetadata.suggestedTitle),
            buildDisplayName: analysis.filenameMetadata.suggestedBuildName, markAsBase: true))
        let rows = try harness.builds.fetchMetadataProvenance(ownerID: result.build.id)
            + harness.games.fetchMetadataProvenance(ownerID: result.game.id)
        #expect(rows.allSatisfy { $0.source == .filename && $0.confidence == MetadataConfidence(analysis.filenameMetadata.confidence) })
    }

    @Test("No-Intro fields have high confidence; unmatched header revision keeps its source", arguments: [false, true])
    func noIntroAndHeader(matched: Bool) throws {
        let harness = try ImportHarness.make()
        defer { try? FileManager.default.removeItem(at: harness.root) }
        var rom = TestROM.make(title: "HEADER")
        rom[0x14c] = 2
        let url = harness.external.appendingPathComponent("Misleading (Japan).gb")
        try rom.write(to: url)
        let dump = KnownDump(name: "Catalog (USA) (En) (v1.2) (Beta)", system: .gameBoy,
            title: "Catalog", region: "USA", languages: "En", status: "Beta", version: "v1.2",
            files: [KnownDumpFile(sha1: SHA1Digest.data(rom), size: Int64(rom.count))])
        let index = try KnownDumpIndex(catalog: KnownDumpCatalog(source: "test", generated: "2026-10-07", systems: [], games: [dump]))
        let analyzer = ROMImportAnalyzer(builds: harness.builds, assetStore: harness.store, knownDumps: matched ? index : nil)
        let analysis = try analyzer.analyzeROM(at: url, targetGameID: nil)
        let result = try harness.committer.commit(ROMImportPlan(analysis: analysis,
            disposition: .createGame(title: analysis.filenameMetadata.suggestedTitle),
            buildDisplayName: analysis.filenameMetadata.suggestedBuildName, markAsBase: true))
        let rows = try harness.builds.fetchMetadataProvenance(ownerID: result.build.id)
        let expected: Set<MetadataField> = matched
            ? [.displayName, .region, .language, .versionString, .status]
            : [.displayName, .region, .revision]
        #expect(Set(rows.map(\.field)) == expected)
        #expect(result.build.revision == (matched ? nil : "2"))
        for row in rows {
            #expect(row.source == (matched ? .noIntro : row.field == .revision ? .romHeader : .filename))
            let confidence = matched ? MetadataConfidence.high : MetadataConfidence(analysis.filenameMetadata.confidence)
            #expect(row.confidence == (row.field == .revision ? nil : confidence))
        }
        #expect(try harness.games.fetchMetadataProvenance(ownerID: result.game.id).first?.source == (matched ? .noIntro : .filename))
        #expect(!result.game.hasPlayerTitle)
    }

    @Test("review edits retain offered values, including cleared fields and edited titles")
    func reviewOverrides() throws {
        let harness = try ImportHarness.make()
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let url = harness.external.appendingPathComponent("Example (USA) (En) [v1.2].gb")
        try TestROM.make(title: "HEADER").write(to: url)
        let analysis = try harness.analyzer.analyzeROM(at: url, targetGameID: nil)
        var metadata = BuildImportMetadata(analysis: analysis)
        metadata.region = "Europe"
        metadata.language = nil
        let result = try harness.committer.commit(ROMImportPlan(analysis: analysis,
            disposition: .createGame(title: "My Example"), buildDisplayName: "Mine", markAsBase: true, metadata: metadata))
        let rows = try harness.builds.fetchMetadataProvenance(ownerID: result.build.id)
        for (field, offered) in [(MetadataField.region, "USA"), (.language, "En"), (.displayName, "v1.2")] {
            let row = try #require(rows.first { $0.field == field })
            #expect(row.source == .player)
            #expect(row.confidence == nil)
            #expect(row.providedValue == offered)
        }
        #expect(rows.first { $0.field == .versionString }?.source == .filename)
        let title = try #require(try harness.games.fetchMetadataProvenance(ownerID: result.game.id).first)
        #expect(title.source == .player)
        #expect(title.providedValue == "Example")
        #expect(result.game.hasPlayerTitle)
        #expect(try harness.games.fetchGame(id: result.game.id)?.hasPlayerTitle == true)
    }

    @Test("a header title fallback is recorded as header evidence")
    func headerTitle() throws {
        let harness = try ImportHarness.make()
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let url = harness.external.appendingPathComponent("(USA).gb")
        try TestROM.make(title: "HEADER").write(to: url)
        let analyzed = try harness.analyzer.analyzeROM(at: url, targetGameID: nil)
        let naming = FilenameMetadata(originalBaseName: "", suggestedTitle: "", suggestedBuildName: "Original",
            normalizedFilename: "", releaseKind: .standard, confidence: .low,
            parentheticalGroups: [], bracketGroups: [], unknownGroups: [])
        let analysis = ROMImportAnalysis(transactionID: analyzed.transactionID, stagedURL: analyzed.stagedURL,
            originalFilename: analyzed.originalFilename, sha256: analyzed.sha256, byteLength: analyzed.byteLength,
            header: analyzed.header, filenameMetadata: naming, exactExistingBuildID: nil, suggestedGameID: nil)
        let result = try harness.committer.commit(ROMImportPlan(analysis: analysis,
            disposition: .createGame(title: "HEADER"), buildDisplayName: analysis.filenameMetadata.suggestedBuildName, markAsBase: true))
        let title = try #require(try harness.games.fetchMetadataProvenance(ownerID: result.game.id).first)
        #expect(title.source == .romHeader)
        #expect(title.confidence == nil)
        #expect(!result.game.hasPlayerTitle)
    }

    @Test("duplicate import keeps player provenance and offered values")
    func duplicate() throws {
        let harness = try ImportHarness.make()
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let url = harness.external.appendingPathComponent("Example [v1.2].gb")
        try TestROM.make(title: "HEADER").write(to: url)
        let first = try harness.analyzer.analyzeROM(at: url, targetGameID: nil)
        let result = try harness.committer.commit(ROMImportPlan(analysis: first, disposition: .createGame(title: "Mine"),
            buildDisplayName: "Mine", markAsBase: true))
        let before = try harness.builds.fetchMetadataProvenance(ownerID: result.build.id)
        let titleBefore = try harness.games.fetchMetadataProvenance(ownerID: result.game.id)
        let again = try harness.analyzer.analyzeROM(at: url, targetGameID: nil)
        _ = try harness.committer.commit(ROMImportPlan(analysis: again, disposition: .duplicateExisting(buildID: result.build.id),
            buildDisplayName: "Other", markAsBase: false))
        #expect(try harness.builds.fetchMetadataProvenance(ownerID: result.build.id) == before)
        #expect(try harness.games.fetchMetadataProvenance(ownerID: result.game.id) == titleBefore)
    }
}

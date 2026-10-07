import AssetStorage
import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import Importing
import Testing
import XCTest
@testable import Patching

final class PatchedBuildTests: XCTestCase {
    func testCreatePatchedBuildPreservesSourcesAndCreatesRecipe() throws {
        let harness = try PatchBuildHarness.make()
        let patchURL = try harness.writePatch(singleByteIPS(offset: 1, value: 0x58), name: "test.ips")

        let build = try harness.creator.execute(
            .init(
                gameID: harness.gameID,
                baseBuildID: harness.baseBuild.id,
                patches: [.init(url: patchURL)],
                displayName: "Patched",
                metadata: .init(baseTitle: "Test", hackTitle: "Test Plus", author: "Hacker", status: "Beta")
            )
        )

        XCTAssertEqual(build.sourceKind, .patchRecipe)
        XCTAssertEqual(build.parentBuildID, harness.baseBuild.id)
        XCTAssertFalse(build.isBase)
        XCTAssertEqual(build.baseTitle, "Test")
        XCTAssertEqual(build.hackTitle, "Test Plus")
        XCTAssertEqual(build.author, "Hacker")
        XCTAssertEqual(build.status, "Beta")
        XCTAssertEqual(try harness.games.fetchGame(id: harness.gameID)?.preferredBuildID, build.id)
        XCTAssertEqual(try harness.outputData(for: build), harness.base(changing: [1: 0x58]))
        let recipe = try XCTUnwrap(harness.recipes.fetchPatchRecipe(resultBuildID: build.id))
        XCTAssertEqual(recipe.baseBuildID, harness.baseBuild.id)
        XCTAssertEqual(recipe.items.count, 1)
        let patchAsset = try XCTUnwrap(harness.assets.fetchAsset(id: recipe.items[0].patchAssetID))
        XCTAssertEqual(patchAsset.kind, .sourcePatch)
        XCTAssertTrue(harness.store.fileExists(at: try harness.store.managedURL(relativePath: patchAsset.relativePath)))
    }

    func testAnOversizedPatchIsRefusedBeforeItIsStaged() throws {
        let harness = try PatchBuildHarness.make()
        let huge = try ImportTestFiles.sparse(at: harness.external.appendingPathComponent("huge.ips"), byteCount: 65 * 1_048_576)
        let stagedBefore = ImportTestFiles.stagedItems(under: harness.store.rootURL)

        XCTAssertThrowsError(try harness.creator.execute(.init(
            gameID: harness.gameID,
            baseBuildID: harness.baseBuild.id,
            patches: [.init(url: huge)],
            displayName: "Patched"
        ))) { XCTAssertEqual($0 as? ImportSizeError, .fileTooLarge(limit: ImportSizeLimit.patch.bytes)) }
        XCTAssertEqual(ImportTestFiles.stagedItems(under: harness.store.rootURL), stagedBefore, "the harness stages its base ROM")
        XCTAssertEqual(try harness.builds.fetchBuilds(gameID: harness.gameID).count, 1)
    }

    func testAPatchedBuildIsDetectedFromItsOwnImage() throws {
        let harness = try PatchBuildHarness.make()
        let target = TestROM.make(title: "TRSE GB")
        let patchURL = try harness.writePatch(
            bpsReplacingWholeImage(expectedSource: harness.baseImage, target: target),
            name: "rascal.bps"
        )

        let build = try harness.creator.execute(
            .init(gameID: harness.gameID, baseBuildID: harness.baseBuild.id, patches: [.init(url: patchURL)], displayName: "Rascal")
        )

        let reports = try harness.toolchainReports.fetchReports(buildID: build.id)
        XCTAssertEqual(reports.flatMap(\.components).map(\.name), ["Turbo Rascal Syntax Error"])
        XCTAssertEqual(try harness.toolchainReports.fetchReports(buildID: harness.baseBuild.id), [], "the base keeps its own")
    }

    func testEvictedGeneratedROMIsRebuiltDeterministically() throws {
        let harness = try PatchBuildHarness.make()
        let patchURL = try harness.writePatch(singleByteIPS(offset: 1, value: 0x58), name: "test.ips")
        let build = try harness.creator.execute(
            .init(gameID: harness.gameID, baseBuildID: harness.baseBuild.id, patches: [.init(url: patchURL)], displayName: "Patched")
        )
        let generatedAsset = try XCTUnwrap(harness.assets.fetchAsset(id: build.imageAssetID))
        let generatedURL = try harness.store.managedURL(relativePath: generatedAsset.relativePath)
        try harness.store.removeIfExists(generatedURL)
        XCTAssertFalse(harness.store.fileExists(at: generatedURL))

        let resolved = try harness.resolver.resolveImageForLaunch(buildID: build.id)

        XCTAssertEqual(resolved, harness.store.generatedImageURL(sha256: build.imageSHA256))
        XCTAssertEqual(try harness.store.readData(at: resolved), harness.base(changing: [1: 0x58]))
        XCTAssertEqual(try harness.store.hashFile(at: resolved), build.imageSHA256)
    }

    func testEvictRemovesOnlyAPatchDerivedImageAndLaunchRebuildsIt() throws {
        let harness = try PatchBuildHarness.make()
        let patchURL = try harness.writePatch(singleByteIPS(offset: 1, value: 0x58), name: "test.ips")
        let build = try harness.creator.execute(
            .init(gameID: harness.gameID, baseBuildID: harness.baseBuild.id, patches: [.init(url: patchURL)], displayName: "Patched")
        )
        let evict = EvictGeneratedImage(builds: harness.builds, assets: harness.assets, assetStore: harness.store)
        let generatedURL = harness.store.generatedImageURL(sha256: build.imageSHA256)

        XCTAssertTrue(try evict.execute(buildID: build.id))
        XCTAssertFalse(harness.store.fileExists(at: generatedURL))
        XCTAssertFalse(try evict.execute(buildID: build.id), "nothing left to evict")
        XCTAssertThrowsError(try evict.execute(buildID: harness.baseBuild.id)) { error in
            XCTAssertEqual(error as? EvictGeneratedImageError, .notRebuildable(harness.baseBuild.id))
        }

        let resolved = try harness.resolver.resolveImageForLaunch(buildID: build.id)
        XCTAssertEqual(try harness.store.hashFile(at: resolved), build.imageSHA256)
    }

    func testWrongBaseNeedsApplyAnywayAndRebuildsTheSameWay() throws {
        let harness = try PatchBuildHarness.make()
        let patchURL = try harness.writePatch(
            bpsReplacingWholeImage(expectedSource: TestROM.make(title: "OTHER BASE", cgb: true), target: TestROM.make(title: "QRS", cgb: true)),
            name: "other-base.bps"
        )

        XCTAssertThrowsError(try harness.creator.execute(
            .init(gameID: harness.gameID, baseBuildID: harness.baseBuild.id, patches: [.init(url: patchURL)], displayName: "Hack")
        )) { error in
            guard case .sourceCRC32Mismatch = error as? PatchError else {
                return XCTFail("Expected source CRC mismatch, got \(error)")
            }
        }
        XCTAssertEqual(try harness.builds.fetchBuilds(gameID: harness.gameID).count, 1, "nothing was created")

        let build = try harness.creator.execute(.init(
            gameID: harness.gameID,
            baseBuildID: harness.baseBuild.id,
            patches: [.init(url: patchURL, ignoreBaseMismatch: true)],
            displayName: "Hack"
        ))
        let recipe = try XCTUnwrap(harness.recipes.fetchPatchRecipe(resultBuildID: build.id))
        XCTAssertEqual(recipe.items.map(\.ignoresBaseMismatch), [true])

        try harness.store.removeIfExists(harness.store.generatedImageURL(sha256: build.imageSHA256))
        let rebuilt = try harness.resolver.resolveImageForLaunch(buildID: build.id)
        XCTAssertEqual(try harness.store.readData(at: rebuilt), TestROM.make(title: "QRS", cgb: true))
    }

    func testACopiedPatchBuildRebuildsItsImageOnItsOwn() throws {
        let harness = try PatchBuildHarness.make()
        let patchURL = try harness.writePatch(singleByteIPS(offset: 1, value: 0x58), name: "test.ips")
        let patched = try harness.creator.execute(
            .init(gameID: harness.gameID, baseBuildID: harness.baseBuild.id, patches: [.init(url: patchURL)], displayName: "Patched")
        )
        let operations = BuildOperations(
            games: harness.games,
            builds: harness.builds,
            profiles: InMemorySaveProfileRepository(),
            states: InMemorySaveStateRepository(),
            recipes: harness.recipes,
            assets: harness.assets,
            assetStore: harness.store
        )
        let separate = try operations.promoteBuild(buildID: patched.id, title: "Hack", mode: .copy)
        let copy = try XCTUnwrap(harness.builds.fetchBuilds(gameID: separate.id).first)

        try EvictGeneratedImage(builds: harness.builds, assets: harness.assets, assetStore: harness.store)
            .execute(buildID: patched.id)
        let rebuilt = try harness.resolver.resolveImageForLaunch(buildID: copy.id)
        XCTAssertEqual(try harness.store.readData(at: rebuilt), harness.base(changing: [1: 0x58]))
    }

    func testApplyingTheSamePatchAgainRepairsADamagedPatchFile() throws {
        let harness = try PatchBuildHarness.make()
        let patchURL = try harness.writePatch(singleByteIPS(offset: 1, value: 0x58), name: "fix.ips")
        let first = try harness.creator.execute(
            .init(gameID: harness.gameID, baseBuildID: harness.baseBuild.id, patches: [.init(url: patchURL)], displayName: "First")
        )
        let recipe = try XCTUnwrap(harness.recipes.fetchPatchRecipe(resultBuildID: first.id))
        let patchAsset = try XCTUnwrap(harness.assets.fetchAsset(id: recipe.items[0].patchAssetID))
        let stored = try harness.store.managedURL(relativePath: patchAsset.relativePath)
        try Data("damaged".utf8).write(to: stored)

        let otherPatch = try harness.writePatch(singleByteIPS(offset: 2, value: 0x59), name: "other.ips")
        _ = try harness.creator.execute(.init(
            gameID: harness.gameID,
            baseBuildID: harness.baseBuild.id,
            patches: [.init(url: otherPatch), .init(url: patchURL)],
            displayName: "Second"
        ))
        XCTAssertEqual(try harness.store.hashFile(at: stored), patchAsset.contentSHA256)
    }

    func testTheSamePatchTwiceInOneStackIsOneSourceAsset() throws {
        let harness = try PatchBuildHarness.make()
        let first = try harness.writePatch(singleByteIPS(offset: 1, value: 0x58), name: "a.ips")
        let second = try harness.writePatch(singleByteIPS(offset: 1, value: 0x58), name: "b.ips")

        let build = try harness.creator.execute(
            .init(gameID: harness.gameID, baseBuildID: harness.baseBuild.id, patches: [.init(url: first), .init(url: second)], displayName: "Twice")
        )
        let recipe = try XCTUnwrap(harness.recipes.fetchPatchRecipe(resultBuildID: build.id))
        XCTAssertEqual(Set(recipe.items.map(\.patchAssetID)).count, 1)
        XCTAssertEqual(recipe.items.count, 2)
    }

    func testBuildsWithTheSamePatchedResultShareOneCacheRecord() throws {
        let harness = try PatchBuildHarness.make()
        let patchURL = try harness.writePatch(singleByteIPS(offset: 1, value: 0x58), name: "test.ips")
        let operations = BuildOperations(
            games: harness.games,
            builds: harness.builds,
            profiles: InMemorySaveProfileRepository(),
            states: InMemorySaveStateRepository(),
            recipes: harness.recipes,
            assets: harness.assets,
            assetStore: harness.store
        )
        let otherGame = try operations.promoteBuild(buildID: harness.baseBuild.id, title: "Copy", mode: .copy)
        let otherBase = try XCTUnwrap(harness.builds.fetchBuilds(gameID: otherGame.id).first)

        let here = try harness.creator.execute(
            .init(gameID: harness.gameID, baseBuildID: harness.baseBuild.id, patches: [.init(url: patchURL)], displayName: "Here")
        )
        let there = try harness.creator.execute(
            .init(gameID: otherGame.id, baseBuildID: otherBase.id, patches: [.init(url: patchURL)], displayName: "There")
        )
        XCTAssertEqual(here.imageAssetID, there.imageAssetID)
    }

    func testPatchStackOrderIsPersistedAndReplayed() throws {
        let harness = try PatchBuildHarness.make()
        let first = try harness.writePatch(singleByteIPS(offset: 0, value: 0x58), name: "first.ips")
        let second = try harness.writePatch(singleByteIPS(offset: 1, value: 0x59), name: "second.ips")
        let build = try harness.creator.execute(
            .init(gameID: harness.gameID, baseBuildID: harness.baseBuild.id, patches: [.init(url: first), .init(url: second)], displayName: "Stack")
        )

        XCTAssertEqual(try harness.outputData(for: build), harness.base(changing: [0: 0x58, 1: 0x59]))
        let recipe = try XCTUnwrap(harness.recipes.fetchPatchRecipe(resultBuildID: build.id))
        XCTAssertEqual(recipe.items.map(\.position), [0, 1])
    }
}

private struct PatchBuildHarness {
    let root: URL
    let external: URL
    let gameID: UUID
    let baseBuild: Build
    /// A Game Boy Color test ROM whose first bytes spell "ABC", for patches to change.
    let baseImage: Data
    let store: ManagedFileStore
    let games: InMemoryGameRepository
    let builds: InMemoryBuildRepository
    let assets: InMemoryAssetRepository
    let recipes: InMemoryPatchRecipeRepository
    let toolchainReports: InMemoryToolchainReportRepository
    let creator: CreatePatchedBuild
    let resolver: PatchDerivedImageResolver

    static func make() throws -> PatchBuildHarness {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("EmulatorKit-PatchBuildTests-\(UUID().uuidString)", isDirectory: true)
        let external = root.appendingPathComponent("External", isDirectory: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let store = try ManagedFileStore(rootURL: root.appendingPathComponent("Managed", isDirectory: true))
        let assets = InMemoryAssetRepository()
        let games = InMemoryGameRepository()
        let builds = InMemoryBuildRepository()
        let recipes = InMemoryPatchRecipeRepository()
        let timestamp = Date(timeIntervalSince1970: 100)
        let gameID = UUID()
        try games.insertGame(Game(
            id: gameID,
            primaryTitle: "Test",
            systemFamily: "gameboy",
            createdAt: timestamp,
            modifiedAt: timestamp
        ))

        var baseImage = TestROM.make(title: "BASE", cgb: true)
        baseImage.replaceSubrange(0..<3, with: Data("ABC".utf8))
        let rawSource = external.appendingPathComponent("base.gb")
        try baseImage.write(to: rawSource)
        let staged = try store.stageCopy(from: rawSource, transactionID: UUID())
        let hash = try store.hashFile(at: staged)
        let committed = try store.commitSourceROM(stagedURL: staged, sha256: hash)
        let asset = ManagedAsset(
            id: UUID(),
            kind: .sourceImage,
            storageClass: .source,
            contentSHA256: hash,
            byteLength: Int64(baseImage.count),
            relativePath: try store.managedRelativePath(for: committed),
            originalFilename: "base.gb",
            integrityStatus: .verified,
            createdAt: timestamp
        )
        try assets.insertAsset(asset)
        let baseBuild = Build(
            id: UUID(),
            gameID: gameID,
            system: .gameBoyColor,
            displayName: "Original",
            imageAssetID: asset.id,
            imageSHA256: hash,
            sourceKind: .importedImage,
            isBase: true,
            createdAt: timestamp,
            modifiedAt: timestamp
        )
        try builds.insertBuild(baseBuild)

        let patcher = PatchStackApplier()
        let toolchainReports = InMemoryToolchainReportRepository()
        let creator = CreatePatchedBuild(
            games: games,
            builds: builds,
            recipes: recipes,
            assets: assets,
            toolchainReports: toolchainReports,
            assetStore: store,
            patcher: patcher,
            now: { timestamp }
        )
        let resolver = PatchDerivedImageResolver(
            builds: builds,
            recipes: recipes,
            assets: assets,
            assetStore: store,
            patcher: patcher
        )
        return PatchBuildHarness(
            root: root,
            external: external,
            gameID: gameID,
            baseBuild: baseBuild,
            baseImage: baseImage,
            store: store,
            games: games,
            builds: builds,
            assets: assets,
            recipes: recipes,
            toolchainReports: toolchainReports,
            creator: creator,
            resolver: resolver
        )
    }

    /// The base image with the given bytes changed.
    func base(changing changes: [Int: UInt8]) -> Data {
        var image = baseImage
        for (offset, value) in changes { image[offset] = value }
        return image
    }

    func writePatch(_ data: Data, name: String) throws -> URL {
        let url = external.appendingPathComponent("\(UUID().uuidString)-\(name)")
        try data.write(to: url)
        return url
    }

    func outputData(for build: Build) throws -> Data {
        let asset = try XCTUnwrap(assets.fetchAsset(id: build.imageAssetID))
        return try store.readData(at: store.managedURL(relativePath: asset.relativePath))
    }
}

/// A BPS patch that writes `target` wholesale and records `expectedSource` as its base.
private func bpsReplacingWholeImage(expectedSource: Data, target: Data) -> Data {
    func number(_ value: Int) -> [UInt8] {
        var data = UInt64(value)
        var bytes: [UInt8] = []
        while true {
            let low = UInt8(data & 0x7f)
            data >>= 7
            if data == 0 {
                bytes.append(0x80 | low)
                return bytes
            }
            bytes.append(low)
            data -= 1
        }
    }
    func littleEndian(_ value: UInt32) -> [UInt8] {
        (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
    }

    var patch = Data("BPS1".utf8)
    patch.append(contentsOf: number(expectedSource.count))
    patch.append(contentsOf: number(target.count))
    patch.append(contentsOf: number(0))
    patch.append(contentsOf: number(((target.count - 1) << 2) | 1))
    patch.append(target)
    patch.append(contentsOf: littleEndian(CRC32.checksum(expectedSource)))
    patch.append(contentsOf: littleEndian(CRC32.checksum(target)))
    patch.append(contentsOf: littleEndian(CRC32.checksum(patch)))
    return patch
}

private func singleByteIPS(offset: Int, value: UInt8) -> Data {
    precondition((0...0xFF_FFFF).contains(offset))
    return Data([
        0x50, 0x41, 0x54, 0x43, 0x48,
        UInt8((offset >> 16) & 0xff), UInt8((offset >> 8) & 0xff), UInt8(offset & 0xff),
        0x00, 0x01,
        value,
        0x45, 0x4f, 0x46,
    ])
}


// A patch that makes a Game Boy game color-only makes a Game Boy Color Build.
extension PatchedBuildTests {
    func testReviewColorizationPatchUsesResultHardwareSystem() throws {
        let h = try PatchBuildHarness.make()
        let timestamp = Date(timeIntervalSince1970: 100)
        let source = TestROM.make(title: "MONO BASE", cgb: false)
        let sourceURL = h.external.appendingPathComponent("mono.gb")
        try source.write(to: sourceURL)
        let staged = try h.store.stageCopy(from: sourceURL, transactionID: UUID())
        let hash = try h.store.hashFile(at: staged)
        let committed = try h.store.commitSourceROM(stagedURL: staged, sha256: hash)
        let asset = ManagedAsset(
            id: UUID(), kind: .sourceImage, storageClass: .source,
            contentSHA256: hash, byteLength: Int64(source.count),
            relativePath: try h.store.managedRelativePath(for: committed),
            originalFilename: "mono.gb", integrityStatus: .verified, createdAt: timestamp
        )
        try h.assets.insertAsset(asset)
        let mono = Build(
            id: UUID(), gameID: h.gameID, system: .gameBoy, displayName: "Mono base",
            imageAssetID: asset.id, imageSHA256: hash, sourceKind: .importedImage,
            isBase: true, createdAt: timestamp, modifiedAt: timestamp
        )
        try h.builds.insertBuild(mono)
        var target = TestROM.make(title: "COLOR ONLY", cgb: true)
        target[0x143] = 0xc0
        var headerChecksum: UInt8 = 0
        for address in 0x134...0x14c { headerChecksum = headerChecksum &- target[address] &- 1 }
        target[0x14d] = headerChecksum
        var globalChecksum: UInt16 = 0
        for address in target.indices where address != 0x14e && address != 0x14f {
            globalChecksum &+= UInt16(target[address])
        }
        target[0x14e] = UInt8(globalChecksum >> 8)
        target[0x14f] = UInt8(globalChecksum & 0xff)
        let patch = try h.writePatch(
            bpsReplacingWholeImage(expectedSource: source, target: target), name: "colorize.bps"
        )
        let result = try h.creator.execute(.init(
            gameID: h.gameID, baseBuildID: mono.id,
            patches: [.init(url: patch)], displayName: "Colorized"
        ))
        XCTAssertEqual(try h.outputData(for: result), target)
        XCTAssertEqual(result.system, .gameBoyColor,
                       "A CGB-only result must not inherit its monochrome base's hardware model")
    }
}

extension PatchedBuildTests {
    func testAPatchToMonochromeMakesAGameBoyBuild() throws {
        let harness = try PatchBuildHarness.make()
        XCTAssertEqual(harness.baseBuild.system, .gameBoyColor)
        let mono = TestROM.make(title: "MONO HACK", cgb: false)
        let patch = try harness.writePatch(
            bpsReplacingWholeImage(expectedSource: harness.baseImage, target: mono), name: "mono.bps"
        )

        let build = try harness.creator.execute(.init(
            gameID: harness.gameID, baseBuildID: harness.baseBuild.id, patches: [.init(url: patch)], displayName: "Mono"
        ))
        XCTAssertEqual(build.system, .gameBoy)
        XCTAssertEqual(try harness.builds.fetchBuild(id: build.id)?.system, .gameBoy, "as stored")
        XCTAssertEqual(try harness.builds.fetchBuild(id: harness.baseBuild.id)?.system, .gameBoyColor, "the base is unchanged")

        // Rebuilding the evicted image gives the same bytes, so the Build's system still fits them.
        try harness.store.removeIfExists(harness.store.generatedImageURL(sha256: build.imageSHA256))
        let rebuilt = try harness.resolver.resolveImageForLaunch(buildID: build.id)
        XCTAssertEqual(try harness.store.readData(at: rebuilt), mono)
    }

    func testAStackIsClassifiedByItsFinalResult() throws {
        let harness = try PatchBuildHarness.make()
        // Clearing the color flag makes the base monochrome; a disabled patch that would put it back
        // is skipped, and a later enabled one that only touches the program leaves it monochrome.
        let clearFlag = try harness.writePatch(singleByteIPS(offset: 0x143, value: 0x00), name: "mono.ips")
        let setFlag = try harness.writePatch(singleByteIPS(offset: 0x143, value: 0xc0), name: "color.ips")
        let program = try harness.writePatch(singleByteIPS(offset: 0x200, value: 0x01), name: "program.ips")

        let build = try harness.creator.execute(.init(
            gameID: harness.gameID,
            baseBuildID: harness.baseBuild.id,
            patches: [.init(url: clearFlag), .init(url: setFlag, enabled: false), .init(url: program)],
            displayName: "Stack"
        ))
        XCTAssertEqual(build.system, .gameBoy)
        XCTAssertEqual(try harness.outputData(for: build), harness.base(changing: [0x143: 0x00, 0x200: 0x01]))
    }

    func testAResultTooShortForAHeaderIsRefusedAndLeavesNothing() throws {
        let harness = try PatchBuildHarness.make()
        let patch = try harness.writePatch(
            bpsReplacingWholeImage(expectedSource: harness.baseImage, target: Data("TINY".utf8)), name: "tiny.bps"
        )
        let assetsBefore = try harness.assets.fetchAssets().count

        XCTAssertThrowsError(try harness.creator.execute(.init(
            gameID: harness.gameID, baseBuildID: harness.baseBuild.id, patches: [.init(url: patch)], displayName: "Tiny"
        ))) { error in
            XCTAssertEqual(error as? CreatePatchedBuildError, .resultNotAROM(byteCount: 4))
        }
        XCTAssertEqual(try harness.builds.fetchBuilds(gameID: harness.gameID).count, 1, "no Build")
        XCTAssertEqual(try harness.assets.fetchAssets().count, assetsBefore, "no assets")
        XCTAssertFalse(harness.store.fileExists(at: harness.store.generatedImageURL(sha256: harness.store.hashData(Data("TINY".utf8)))))
    }

    func testAResultWithAStaleChecksumIsStillAccepted() throws {
        let harness = try PatchBuildHarness.make()
        // Changing a title byte without fixing the checksums, as many hacks do.
        let patch = try harness.writePatch(singleByteIPS(offset: 0x134, value: 0x5a), name: "title.ips")
        let build = try harness.creator.execute(.init(
            gameID: harness.gameID, baseBuildID: harness.baseBuild.id, patches: [.init(url: patch)], displayName: "Hack"
        ))
        XCTAssertEqual(build.system, .gameBoyColor)
    }
}

@Suite("Patch metadata provenance")
struct PatchMetadataProvenanceTests {
    @Test("patch names and metadata keep their source, and an adopted Game title is the player's")
    func patchFields() throws {
        let harness = try PatchBuildHarness.make()
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let patch = harness.external.appendingPathComponent("Test - Test Plus (USA) (En) (Rev A) [Hack] [Author: Hacker] [Translation: Spanish] [v1.2] [Beta].ips")
        try singleByteIPS(offset: 1, value: 0x58).write(to: patch)
        let naming = FilenameMetadataParser.parse(filename: patch.lastPathComponent)
        let displayName = BuildNaming.patchBuildName(for: naming, gameTitle: "Test")
        let build = try harness.creator.execute(.init(gameID: harness.gameID, baseBuildID: harness.baseBuild.id,
            patchURLs: [patch], displayName: displayName, metadata: BuildNaming.patchMetadata(for: naming), gameTitle: "Test Plus"))
        let rows = try harness.builds.fetchMetadataProvenance(ownerID: build.id)
        #expect(rows.count == 10)
        #expect(rows.allSatisfy { $0.source == .patch && $0.confidence == .high && $0.providedValue == $0.field.value(in: build) })
        let title = try #require(try harness.games.fetchMetadataProvenance(ownerID: harness.gameID).first)
        #expect(title.source == .player, "an adopted hack title is the player's")
        #expect(title.providedValue == "Test Plus")
        #expect(try harness.games.fetchGame(id: harness.gameID)?.hasPlayerTitle == true)
        #expect(try harness.games.fetchGame(id: harness.gameID)?.aliases.contains("Test") == true)
    }

    @Test("patch review edits keep the patch's offered name and values")
    func patchReviewEdits() throws {
        let harness = try PatchBuildHarness.make()
        defer { try? FileManager.default.removeItem(at: harness.root) }
        let patch = harness.external.appendingPathComponent("Test Plus (USA) [v1.2].ips")
        try singleByteIPS(offset: 1, value: 0x58).write(to: patch)
        let naming = FilenameMetadataParser.parse(filename: patch.lastPathComponent)
        var metadata = BuildNaming.patchMetadata(for: naming)
        metadata.region = "Europe"
        let build = try harness.creator.execute(.init(gameID: harness.gameID, baseBuildID: harness.baseBuild.id,
            patchURLs: [patch], displayName: "My Patch", metadata: metadata))
        let rows = try harness.builds.fetchMetadataProvenance(ownerID: build.id)
        let name = try #require(rows.first { $0.field == .displayName })
        #expect(name.source == .player)
        #expect(name.providedValue == "Test Plus v1.2")
        let region = try #require(rows.first { $0.field == .region })
        #expect(region.source == .player)
        #expect(region.confidence == nil)
        #expect(region.providedValue == "USA")
        #expect(rows.first { $0.field == .hackTitle }?.source == .patch)
    }
}

import AssetStorage
import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
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
                displayName: "Patched"
            )
        )

        XCTAssertEqual(build.sourceKind, .patchRecipe)
        XCTAssertEqual(build.parentBuildID, harness.baseBuild.id)
        XCTAssertEqual(try harness.outputData(for: build), Data("AXC".utf8))
        let recipe = try XCTUnwrap(harness.recipes.fetchPatchRecipe(resultBuildID: build.id))
        XCTAssertEqual(recipe.baseBuildID, harness.baseBuild.id)
        XCTAssertEqual(recipe.items.count, 1)
        let patchAsset = try XCTUnwrap(harness.assets.fetchAsset(id: recipe.items[0].patchAssetID))
        XCTAssertEqual(patchAsset.kind, .sourcePatch)
        XCTAssertTrue(harness.store.fileExists(at: try harness.store.managedURL(relativePath: patchAsset.relativePath)))
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
        XCTAssertEqual(try harness.store.readData(at: resolved), Data("AXC".utf8))
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
            bpsReplacingWholeImage(expectedSource: Data("ZZZ".utf8), target: Data("QRS".utf8)),
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
        XCTAssertEqual(try harness.store.readData(at: rebuilt), Data("QRS".utf8))
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
            recipes: harness.recipes,
            assets: harness.assets,
            assetStore: harness.store
        )
        let separate = try operations.promoteBuild(buildID: patched.id, title: "Hack", mode: .copy)
        let copy = try XCTUnwrap(harness.builds.fetchBuilds(gameID: separate.id).first)

        try EvictGeneratedImage(builds: harness.builds, assets: harness.assets, assetStore: harness.store)
            .execute(buildID: patched.id)
        let rebuilt = try harness.resolver.resolveImageForLaunch(buildID: copy.id)
        XCTAssertEqual(try harness.store.readData(at: rebuilt), Data("AXC".utf8))
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

        XCTAssertEqual(try harness.outputData(for: build), Data("XYC".utf8))
        let recipe = try XCTUnwrap(harness.recipes.fetchPatchRecipe(resultBuildID: build.id))
        XCTAssertEqual(recipe.items.map(\.position), [0, 1])
    }
}

private struct PatchBuildHarness {
    let root: URL
    let external: URL
    let gameID: UUID
    let baseBuild: Build
    let store: ManagedFileStore
    let games: InMemoryGameRepository
    let builds: InMemoryBuildRepository
    let assets: InMemoryAssetRepository
    let recipes: InMemoryPatchRecipeRepository
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

        let rawSource = external.appendingPathComponent("base.gb")
        try Data("ABC".utf8).write(to: rawSource)
        let staged = try store.stageCopy(from: rawSource, transactionID: UUID())
        let hash = try store.hashFile(at: staged)
        let committed = try store.commitSourceROM(stagedURL: staged, sha256: hash)
        let asset = ManagedAsset(
            id: UUID(),
            kind: .sourceImage,
            storageClass: .source,
            contentSHA256: hash,
            byteLength: 3,
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
        let creator = CreatePatchedBuild(
            games: games,
            builds: builds,
            recipes: recipes,
            assets: assets,
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
            store: store,
            games: games,
            builds: builds,
            assets: assets,
            recipes: recipes,
            creator: creator,
            resolver: resolver
        )
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

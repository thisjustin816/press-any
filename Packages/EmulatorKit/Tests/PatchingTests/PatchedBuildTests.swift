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

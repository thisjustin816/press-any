import AssetStorage
import EmulationCore
import EmulationSession
import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import Importing
import Patching
import QuickPlay
import Testing

@Suite("Library storage")
struct LibraryStorageTests {
    @Test("an empty library and absent Quick Play workspace use no bytes")
    func empty() throws {
        let h = try StorageHarness()
        defer { try? FileManager.default.removeItem(at: h.root) }
        let usage = try h.usage.execute()
        #expect(usage.totalBytes == 0)
        for category in LibraryStorageCategory.allCases { #expect(usage.bytes(in: category) == 0) }
    }

    @Test("asset kinds count once and Quick Play includes kept sessions and untracked files")
    func totals() throws {
        let h = try StorageHarness()
        defer { try? FileManager.default.removeItem(at: h.root) }
        let entries: [(ManagedAssetKind, ManagedAssetStorageClass, Int, LibraryStorageCategory)] = [
            (.sourceImage, .source, 11, .gameROMs),
            (.sourcePatch, .source, 13, .patches),
            (.persistentSave, .userData, 17, .saves),
            (.saveState, .userData, 19, .saveStates),
            (.stateThumbnail, .userData, 23, .saveStates),
            (.artwork, .userData, 29, .artwork),
            (.variableMap, .source, 31, .other),
            (.quickPlayImage, .temporary, 37, .other),
            (.generatedImage, .cache, 41, .patchedROMCache),
        ]
        for (kind, storageClass, count, _) in entries {
            _ = try h.insert(kind: kind, storageClass: storageClass, bytes: Data(repeating: 1, count: count))
        }
        let workspace = QuickPlayWorkspace(profiles: h.profiles, assets: h.assets, assetStore: h.store)
        let pickedROM = h.root.appendingPathComponent("picked.gb")
        try TestROM.make(title: "QUICK PLAY").write(to: pickedROM)
        let kept = try workspace.start(romURL: pickedROM)
        try workspace.writeTemporaryBattery(Data([1, 2, 3]), sessionID: kept.id)
        try h.assets.insertAsset(ManagedAsset(id: UUID(), kind: .quickPlayImage, storageClass: .temporary,
            contentSHA256: kept.imageSHA256, byteLength: Int64(TestROM.make(title: "QUICK PLAY").count),
            relativePath: try h.store.managedRelativePath(for: kept.imageURL), createdAt: Date()))
        let loose = h.store.quickPlayRoot(sessionID: UUID()).appendingPathComponent(".interrupted")
        try h.store.writeDataAtomically(Data([4, 5]), to: loose)
        let quickPlayBytes = try [kept.imageURL, kept.manifestURL, kept.persistentSaveURL, loose]
            .reduce(Int64(0)) { try $0 + h.store.fileByteLength(at: $1) }

        let usage = try h.usage.execute()

        for category in LibraryStorageCategory.allCases where category != .quickPlay {
            #expect(usage.bytes(in: category) == Int64(entries.filter { $0.3 == category }.reduce(0) { $0 + $1.2 }))
        }
        #expect(usage.bytes(in: .quickPlay) == quickPlayBytes)
        #expect(usage.totalBytes == Int64(entries.reduce(0) { $0 + $1.2 }) + quickPlayBytes)
    }

    @Test("clearing protects the running Build and preserves every source and user file")
    func protectedClear() throws {
        let h = try StorageHarness()
        defer { try? FileManager.default.removeItem(at: h.root) }
        var kept: [ManagedAsset] = []
        for kind in [ManagedAssetKind.sourceImage, .sourcePatch, .persistentSave, .saveState, .stateThumbnail, .artwork, .variableMap, .quickPlayImage] {
            kept.append(try h.insert(kind: kind, storageClass: kind == .sourceImage || kind == .sourcePatch ? .source : .userData,
                bytes: Data(kind.rawValue.utf8)))
        }
        let running = try h.insert(kind: .generatedImage, storageClass: .cache, bytes: Data([1, 2]))
        let removable = try h.insert(kind: .generatedImage, storageClass: .cache, bytes: Data([3, 4, 5]))
        let alreadyAbsent = try h.insert(kind: .generatedImage, storageClass: .cache, bytes: Data([6]))
        try h.store.removeIfExists(h.url(for: alreadyAbsent))
        let build = h.build(image: running)
        try h.builds.insertBuild(build)
        var copy = h.build(image: running)
        copy.displayName = "Copy sharing the running image"
        try h.builds.insertBuild(copy)
        let quickPlay = h.store.quickPlayRoot(sessionID: UUID()).appendingPathComponent("rom.bin")
        try h.store.writeDataAtomically(Data([7, 8]), to: quickPlay)
        let before = try h.assets.fetchAssets()

        try h.clear.execute(activeBuildID: build.id)

        for asset in kept + [running] {
            #expect(try h.store.hashFile(at: h.url(for: asset)) == asset.contentSHA256)
        }
        #expect(!h.store.fileExists(at: try h.url(for: removable)))
        #expect(try h.store.readData(at: quickPlay) == Data([7, 8]))
        #expect(try h.assets.fetchAssets() == before)
        #expect(try h.usage.execute().bytes(in: .patchedROMCache) == 2)
        #expect(try h.checker.inspect().isClean)

        try h.clear.execute()
        #expect(try h.usage.execute().bytes(in: .patchedROMCache) == 0)
        #expect(try h.checker.inspect(cleanup: .removeProvableOrphans).isClean)
    }

    @Test("a missing running Build stops clearing before any file is removed")
    func unknownActiveBuild() throws {
        let h = try StorageHarness()
        defer { try? FileManager.default.removeItem(at: h.root) }
        let asset = try h.insert(kind: .generatedImage, storageClass: .cache, bytes: Data([1]))
        #expect(throws: (any Error).self) { try h.clear.execute(activeBuildID: UUID()) }
        #expect(h.store.fileExists(at: try h.url(for: asset)))
    }

    @Test("launch and export rebuild cleared patched ROMs with their recorded hash")
    func rebuild() throws {
        let h = try StorageHarness()
        defer { try? FileManager.default.removeItem(at: h.root) }
        let game = Game(id: UUID(), primaryTitle: "Test", systemFamily: "gameboy", createdAt: Date(), modifiedAt: Date())
        let games = InMemoryGameRepository([game])
        let source = try h.insert(kind: .sourceImage, storageClass: .source, bytes: TestROM.make(title: "BASE"))
        let base = h.build(image: source, gameID: game.id)
        try h.builds.insertBuild(base)
        let patchURL = h.root.appendingPathComponent("change.ips")
        try Data([0x50, 0x41, 0x54, 0x43, 0x48, 0, 0, 1, 0, 1, 0x58, 0x45, 0x4f, 0x46]).write(to: patchURL)
        let recipes = InMemoryPatchRecipeRepository()
        let patched = try CreatePatchedBuild(games: games, builds: h.builds, recipes: recipes, assets: h.assets,
            toolchainReports: InMemoryToolchainReportRepository(), assetStore: h.store)
            .execute(.init(gameID: game.id, baseBuildID: base.id, patchURLs: [patchURL], displayName: "Patched"))
        let resolver = ResolveImageForLaunch(builds: h.builds, recipes: recipes, assets: h.assets, assetStore: h.store)
        let profile = SaveProfile(id: UUID(), gameID: game.id, displayName: "Main", createdAt: Date(), modifiedAt: Date())
        try h.profiles.insertSaveProfile(profile)
        let session = EmulationSession(builds: h.builds, profiles: h.profiles, states: InMemorySaveStateRepository(),
            assets: h.assets, assetStore: h.store, imageResolver: resolver,
            coreRegistry: CoreRegistry(factories: [FakeCoreFactory(descriptor: .init(identifier: "sameboy", version: "1"))]))
        let context = LaunchContext(gameID: game.id, buildID: patched.id, saveProfileID: profile.id)

        try h.clear.execute()
        #expect(try h.checker.inspect().isClean)
        #expect(try h.usage.execute().bytes(in: .patchedROMCache) == 0)
        _ = try session.start(context: context)
        #expect(session.state == .running(context))
        #expect(try h.store.hashFile(at: h.store.generatedImageURL(sha256: patched.imageSHA256)) == patched.imageSHA256)
        #expect(try h.usage.execute().bytes(in: .patchedROMCache) > 0)
        try session.stop(createAutoState: false)

        try h.clear.execute()
        let exported = try ExportLibraryFiles(games: games, builds: h.builds, profiles: h.profiles,
            assets: h.assets, assetStore: h.store, images: resolver)
            .exportROM(buildID: patched.id, to: h.root.appendingPathComponent("Exports"))
        #expect(try h.store.hashFile(at: exported) == patched.imageSHA256)
    }

    @Test("present damaged cache and missing source data still report integrity issues")
    func integrityFailures() throws {
        let h = try StorageHarness()
        defer { try? FileManager.default.removeItem(at: h.root) }
        let generated = try h.insert(kind: .generatedImage, storageClass: .cache, bytes: Data([1]))
        let source = try h.insert(kind: .sourceImage, storageClass: .source, bytes: Data([2]))
        try h.store.writeDataAtomically(Data([3]), to: h.url(for: generated))
        try h.store.removeIfExists(h.url(for: source))
        let report = try h.checker.inspect()
        #expect(report.issues.count == 2)
        #expect(report.issues.contains(.missingSource(assetID: source.id, relativePath: source.relativePath)))
        #expect(try h.assets.fetchAsset(id: generated.id)?.integrityStatus == .corrupt)
    }
}

private struct StorageHarness {
    let root: URL
    let store: ManagedFileStore
    let assets = InMemoryAssetRepository()
    let builds = InMemoryBuildRepository()
    let profiles = InMemorySaveProfileRepository()

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("Storage-\(UUID())")
        store = try ManagedFileStore(rootURL: root.appendingPathComponent("Library"))
    }

    var usage: MeasureLibraryStorage { MeasureLibraryStorage(assets: assets, assetStore: store) }
    var clear: ClearPatchedROMCache { ClearPatchedROMCache(assets: assets, builds: builds, assetStore: store) }
    var checker: ManagedAssetIntegrityChecker { ManagedAssetIntegrityChecker(assets: assets, assetStore: store) }

    func url(for asset: ManagedAsset) throws -> URL { try store.managedURL(relativePath: asset.relativePath) }

    func insert(kind: ManagedAssetKind, storageClass: ManagedAssetStorageClass, bytes: Data) throws -> ManagedAsset {
        let hash = store.hashData(bytes)
        let url = kind == .generatedImage ? store.generatedImageURL(sha256: hash)
            : store.rootURL.appendingPathComponent("Fixtures/\(UUID())")
        try store.writeDataAtomically(bytes, to: url)
        let asset = ManagedAsset(id: UUID(), kind: kind, storageClass: storageClass, contentSHA256: hash,
            byteLength: Int64(bytes.count), relativePath: try store.managedRelativePath(for: url), createdAt: Date())
        try assets.insertAsset(asset)
        return asset
    }

    func build(image: ManagedAsset, gameID: UUID = UUID()) -> Build {
        Build(id: UUID(), gameID: gameID, system: .gameBoy, displayName: "Test", imageAssetID: image.id,
            imageSHA256: image.contentSHA256, sourceKind: image.kind == .generatedImage ? .patchRecipe : .importedImage,
            createdAt: Date(), modifiedAt: Date())
    }
}

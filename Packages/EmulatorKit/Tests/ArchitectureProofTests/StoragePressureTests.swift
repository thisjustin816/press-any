import AssetStorage
import EmulationCore
import EmulationSession
import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import Importing
import Patching
import Testing

@Suite("Patched ROM cache trimming")
struct PatchedROMCacheTrimTests {
    @Test("nothing is trimmed while free space is at the minimum or unknown")
    func enoughSpace() throws {
        let h = try TrimHarness()
        defer { h.cleanUp() }
        let patched = try h.patched(byte: 0x58, createdAt: h.day(1))

        #expect(try h.trim(free: TrimPatchedROMCache.minimumFreeBytes).execute().isEmpty)
        #expect(try h.trim(free: nil).execute().isEmpty)
        #expect(h.isCached(patched))
    }

    @Test("the least recently played image goes first and trimming stops once space is back")
    func leastRecentlyPlayedFirst() throws {
        let h = try TrimHarness()
        defer { h.cleanUp() }
        let playedLongAgo = try h.patched(byte: 0x58, createdAt: h.day(1))
        let playedRecently = try h.patched(byte: 0x59, createdAt: h.day(2))
        let neverPlayed = try h.patched(byte: 0x5A, createdAt: h.day(5))
        try h.played(playedLongAgo, at: h.day(3))
        try h.played(playedRecently, at: h.day(9))
        let size = try h.byteLength(of: playedLongAgo)

        let first = try h.trim(free: TrimPatchedROMCache.minimumFreeBytes - 1).execute()
        #expect(first == [try h.path(of: playedLongAgo)])
        #expect(h.isCached(neverPlayed) && h.isCached(playedRecently))

        let second = try h.trim(free: TrimPatchedROMCache.minimumFreeBytes - size - 1).execute()
        #expect(second == [try h.path(of: neverPlayed), try h.path(of: playedRecently)])
    }

    @Test("an image about to be written counts toward the space needed")
    func incomingBytes() throws {
        let h = try TrimHarness()
        defer { h.cleanUp() }
        let patched = try h.patched(byte: 0x58, createdAt: h.day(1))

        #expect(try h.trim(free: TrimPatchedROMCache.minimumFreeBytes).execute(incomingBytes: 1) == [try h.path(of: patched)])
    }

    @Test("a held image, such as the running game's, and one that can't be rebuilt are kept")
    func keepsHeldAndUnrebuildable() throws {
        let h = try TrimHarness()
        defer { h.cleanUp() }
        let running = try h.patched(byte: 0x58, createdAt: h.day(1))
        let unrebuildable = try h.patched(byte: 0x59, createdAt: h.day(2))
        let other = try h.patched(byte: 0x5A, createdAt: h.day(3))
        let patch = try #require(try h.recipes.fetchPatchRecipe(resultBuildID: unrebuildable.id)?.items.first)
        let patchAsset = try #require(try h.assets.fetchAsset(id: patch.patchAssetID))
        try h.store.removeIfExists(try h.store.managedURL(relativePath: patchAsset.relativePath))
        let inFlight = InFlightFiles()
        let lease = inFlight.lease()
        lease.hold(try h.path(of: running))

        let removed = try h.trim(free: 0, inFlight: inFlight).execute()

        #expect(removed == [try h.path(of: other)])
        #expect(h.isCached(running) && h.isCached(unrebuildable))
        lease.end()
        #expect(try h.trim(free: 0, inFlight: inFlight).execute() == [try h.path(of: running)])
    }

    @Test("a running game's image is held from launch until the session stops")
    func runningGameKept() throws {
        let h = try TrimHarness()
        defer { h.cleanUp() }
        let running = try h.patched(byte: 0x58, createdAt: h.day(1))
        let inFlight = InFlightFiles()
        let session = EmulationSession(builds: h.builds, profiles: h.profiles, states: h.states, assets: h.assets,
            assetStore: h.store,
            imageResolver: ResolveImageForLaunch(builds: h.builds, recipes: h.recipes, assets: h.assets, assetStore: h.store),
            coreRegistry: CoreRegistry(factories: [FakeCoreFactory(descriptor: .init(identifier: "sameboy", version: "1"))]),
            inFlight: inFlight)

        _ = try session.start(context: LaunchContext(gameID: h.game.id, buildID: running.id, saveProfileID: h.profile.id))
        #expect(try h.trim(free: 0, inFlight: inFlight).execute().isEmpty)
        #expect(h.isCached(running))

        try session.stop(createAutoState: false)
        #expect(try h.trim(free: 0, inFlight: inFlight).execute() == [try h.path(of: running)])
    }

    @Test("rebuilding a missing image at launch first trims older ones")
    func trimsBeforeRebuild() throws {
        let h = try TrimHarness()
        defer { h.cleanUp() }
        let older = try h.patched(byte: 0x58, createdAt: h.day(1))
        let launched = try h.patched(byte: 0x59, createdAt: h.day(2))
        try h.store.removeIfExists(h.store.generatedImageURL(sha256: launched.imageSHA256))
        let resolver = ResolveImageForLaunch(builds: h.builds, recipes: h.recipes, assets: h.assets,
            assetStore: h.store, trimCache: h.trim(free: TrimPatchedROMCache.minimumFreeBytes))

        #expect(try h.store.hashFile(at: resolver.resolve(buildID: launched.id)) == launched.imageSHA256)
        #expect(!h.isCached(older))
    }
}

@Suite("In-flight files")
struct InFlightFilesTests {
    @Test("a path stays held until every lease holding it ends")
    func counting() {
        let files = InFlightFiles()
        let first = files.lease()
        let second = files.lease()
        first.hold("Source/ROM/a.rom")
        second.hold("Source/ROM/a.rom")
        first.end()
        #expect(files.isHeld("Source/ROM/a.rom"))
        #expect(!files.removeUnlessHeld("Source/ROM/a.rom") { true })
        second.end()
        #expect(!files.isHeld("Source/ROM/a.rom"))
        #expect(files.removeUnlessHeld("Source/ROM/a.rom") { true })
    }

    @Test("Check Library Files keeps a ROM an import has placed but not yet recorded")
    func sweepDuringImportCommit() throws {
        let h = try SweepHarness()
        defer { h.cleanUp() }
        let inFlight = InFlightFiles()
        let checker = ManagedAssetIntegrityChecker(assets: h.assets, assetStore: h.store, inFlight: inFlight)
        let sweptMidCommit = SweptPaths()
        // The sweep runs just before the commit's records go in, after its file is placed.
        let runner = BeforeTransaction {
            sweptMidCommit.append(try checker.inspect(cleanup: .removeProvableOrphans).removedRelativePaths)
        }

        let result = try h.committer(transactions: runner, inFlight: inFlight).commit(h.plan(title: "PLACED"))

        #expect(sweptMidCommit.paths.isEmpty)
        #expect(h.store.fileExists(at: try h.store.managedURL(relativePath: result.sourceAsset.relativePath)))
    }

    @Test("Check Library Files keeps a ROM an import recorded after the sweep read the inventory")
    func sweepWithStaleInventory() throws {
        let h = try SweepHarness()
        defer { h.cleanUp() }
        let plan = try h.plan(title: "RECORDED")
        let committer = h.committer(transactions: PassthroughTransactionRunner(), inFlight: nil)
        let inventory = InventoryThenCommit(h.assets) { _ = try committer.commit(plan) }
        let checker = ManagedAssetIntegrityChecker(assets: inventory, assetStore: h.store)

        let report = try checker.inspect(cleanup: .removeProvableOrphans)

        let source = try #require(try h.assets.fetchAssets().first { $0.kind == .sourceImage })
        #expect(report.removedRelativePaths.isEmpty)
        #expect(h.store.fileExists(at: try h.store.managedURL(relativePath: source.relativePath)))
    }

    @Test("Check Library Files still removes a file nothing records or holds")
    func sweepRemovesTrueOrphans() throws {
        let h = try SweepHarness()
        defer { h.cleanUp() }
        let orphan = try h.store.sourceImageURL(sha256: String(repeating: "a", count: 64))
        try h.store.writeDataAtomically(Data([1]), to: orphan)
        let checker = ManagedAssetIntegrityChecker(assets: h.assets, assetStore: h.store, inFlight: InFlightFiles())

        let report = try checker.inspect(cleanup: .removeProvableOrphans)

        #expect(report.removedRelativePaths == [try h.store.managedRelativePath(for: orphan)])
        #expect(!h.store.fileExists(at: orphan))
    }
}

private struct TrimHarness {
    let root: URL
    let store: ManagedFileStore
    let assets = InMemoryAssetRepository()
    let builds = InMemoryBuildRepository()
    let recipes = InMemoryPatchRecipeRepository()
    let profiles = InMemorySaveProfileRepository()
    let states = InMemorySaveStateRepository()
    let games: InMemoryGameRepository
    let game: Game
    let base: Build
    let profile: SaveProfile

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("Trim-\(UUID())")
        store = try ManagedFileStore(rootURL: root.appendingPathComponent("Library"))
        game = Game(id: UUID(), primaryTitle: "Test", systemFamily: "gameboy", createdAt: Date(), modifiedAt: Date())
        games = InMemoryGameRepository([game])
        let image = TestROM.make(title: "BASE")
        let url = store.rootURL.appendingPathComponent("Fixtures/base.rom")
        try store.writeDataAtomically(image, to: url)
        let asset = ManagedAsset(id: UUID(), kind: .sourceImage, storageClass: .source,
            contentSHA256: store.hashData(image), byteLength: Int64(image.count),
            relativePath: try store.managedRelativePath(for: url), createdAt: Date())
        try assets.insertAsset(asset)
        base = Build(id: UUID(), gameID: game.id, system: .gameBoy, displayName: "Base", imageAssetID: asset.id,
            imageSHA256: asset.contentSHA256, sourceKind: .importedImage, createdAt: Date(), modifiedAt: Date())
        try builds.insertBuild(base)
        profile = SaveProfile(id: UUID(), gameID: game.id, displayName: "Main", createdAt: Date(), modifiedAt: Date())
        try profiles.insertSaveProfile(profile)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }

    func day(_ number: Int) -> Date { Date(timeIntervalSince1970: Double(number) * 86_400) }

    /// A Build patched from the base by an IPS patch that writes `byte` at offset 1.
    func patched(byte: UInt8, createdAt: Date) throws -> Build {
        let patchURL = root.appendingPathComponent("change-\(byte).ips")
        try Data([0x50, 0x41, 0x54, 0x43, 0x48, 0, 0, 1, 0, 1, byte, 0x45, 0x4f, 0x46]).write(to: patchURL)
        return try CreatePatchedBuild(games: games, builds: builds, recipes: recipes, assets: assets,
            toolchainReports: InMemoryToolchainReportRepository(), assetStore: store, now: { createdAt })
            .execute(.init(gameID: game.id, baseBuildID: base.id, patchURLs: [patchURL], displayName: "Patch \(byte)",
                makePreferred: false))
    }

    func played(_ build: Build, at date: Date) throws {
        try states.insertSaveState(SaveState(id: UUID(), buildID: build.id, saveProfileID: profile.id,
            core: CoreDescriptor(identifier: "sameboy", version: "1"), stateSerializationVersion: "1",
            stateAssetID: UUID(), kind: .auto, playtimeSeconds: 60, createdAt: date))
    }

    func trim(free: Int64?, inFlight: InFlightFiles? = nil) -> TrimPatchedROMCache {
        TrimPatchedROMCache(assets: assets, builds: builds, recipes: recipes, profiles: profiles, states: states,
            assetStore: store, inFlight: inFlight, freeBytes: { free })
    }

    func path(of build: Build) throws -> String {
        try #require(try assets.fetchAsset(id: build.imageAssetID)).relativePath
    }

    func byteLength(of build: Build) throws -> Int64 {
        try #require(try assets.fetchAsset(id: build.imageAssetID)).byteLength
    }

    func isCached(_ build: Build) -> Bool {
        store.fileExists(at: store.generatedImageURL(sha256: build.imageSHA256))
    }
}

private struct SweepHarness {
    let root: URL
    let store: ManagedFileStore
    let assets = InMemoryAssetRepository()
    let builds = InMemoryBuildRepository()
    let games = InMemoryGameRepository()
    let fingerprints = InMemoryImageFingerprintRepository()
    let reports = InMemoryToolchainReportRepository()

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("Sweep-\(UUID())")
        store = try ManagedFileStore(rootURL: root.appendingPathComponent("Library"))
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }

    func plan(title: String) throws -> ROMImportPlan {
        let url = root.appendingPathComponent("\(title).gb")
        try TestROM.make(title: title).write(to: url)
        let analysis = try ROMImportAnalyzer(builds: builds, games: games, fingerprints: fingerprints,
            toolchainReports: reports, assetStore: store).analyzeROM(at: url, targetGameID: nil)
        return ROMImportPlan(analysis: analysis, disposition: .createGame(title: title), buildDisplayName: title,
            markAsBase: true)
    }

    func committer(transactions: any LibraryTransactionRunner, inFlight: InFlightFiles?) -> ImportCommitter {
        ImportCommitter(games: games, builds: builds, assets: assets, toolchainReports: reports,
            fingerprints: fingerprints, assetStore: store, transactions: transactions, inFlight: inFlight)
    }
}

/// Runs `before` ahead of each transaction, when a commit has placed its files but not yet
/// recorded them.
private struct BeforeTransaction: LibraryTransactionRunner {
    let before: @Sendable () throws -> Void

    init(_ before: @escaping @Sendable () throws -> Void) {
        self.before = before
    }

    func run<T: Sendable>(_ operation: @Sendable () throws -> T) throws -> T {
        try before()
        return try operation()
    }
}

private final class SweptPaths: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []

    var paths: [String] { lock.withLock { stored } }

    func append(_ paths: [String]) { lock.withLock { stored += paths } }
}

/// Hands out the inventory as it was, then runs `afterRead` once, as a commit finishing while
/// the sweep walks the folders would.
private final class InventoryThenCommit: ManagedAssetInventoryRepository, @unchecked Sendable {
    private let base: InMemoryAssetRepository
    private var afterRead: (() throws -> Void)?

    init(_ base: InMemoryAssetRepository, afterRead: @escaping () throws -> Void) {
        self.base = base
        self.afterRead = afterRead
    }

    func fetchAssets() throws -> [ManagedAsset] {
        let snapshot = try base.fetchAssets()
        let pending = afterRead
        afterRead = nil
        try pending?()
        return snapshot
    }

    func fetchAsset(id: UUID) throws -> ManagedAsset? { try base.fetchAsset(id: id) }
    func fetchSourceAsset(kind: ManagedAssetKind, sha256: String) throws -> ManagedAsset? {
        try base.fetchSourceAsset(kind: kind, sha256: sha256)
    }
    func fetchAsset(relativePath: String) throws -> ManagedAsset? { try base.fetchAsset(relativePath: relativePath) }
    func insertAsset(_ asset: ManagedAsset) throws { try base.insertAsset(asset) }
    func updateMutableAsset(_ asset: ManagedAsset) throws { try base.updateMutableAsset(asset) }
    func deleteAsset(id: UUID) throws { try base.deleteAsset(id: id) }
}

import AssetStorage
import EmulationCore
import EmulationSession
import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import PersistenceGRDB
import Testing

@Suite("Save state slots and cleanup")
struct SaveStateSlotsAndRetentionTests {
    @Test("save settings have conservative defaults and resolve only at App scope")
    func settingsScope() throws {
        let f = try StateFixture()
        defer { f.removeFiles() }
        let resolver = SettingsResolver(store: f.settings)
        #expect(try resolver.appValue(SaveStateSlots.self, key: .saveStateSlots) == nil)
        #expect(try resolver.appValue(Bool.self, key: .nameNewStates) == nil)
        #expect(try resolver.appValue(KeepSaveStates.self, key: .keepSaveStates) == nil)
        #expect(try resolver.appValue(KeepAutoStates.self, key: .keepAutoStates) == nil)
        for key in [SettingKey.saveStateSlots, .nameNewStates, .keepSaveStates, .keepAutoStates] {
            try f.settings.setValueJSON("10", key: key.rawValue, scope: .build(f.context.buildID))
            #expect(try resolver.resolve(key: key.rawValue, system: .gameBoy, gameID: f.context.gameID, buildID: f.context.buildID) == nil)
            #expect(throws: SettingsResolverError.self) {
                try resolver.edit(key: key.rawValue, at: .build(f.context.buildID), system: .gameBoy,
                    gameID: f.context.gameID, buildID: f.context.buildID)
            }
        }
        try f.settings.set(KeepSaveStates.twentyFive, key: SettingKey.keepSaveStates.rawValue, scope: .app)
        #expect(try resolver.decode(KeepSaveStates.self, key: SettingKey.keepSaveStates.rawValue,
            system: .gameBoy, buildID: f.context.buildID) == .twentyFive)
    }

    @Test("legacy state JSON decodes with no slot and no pin")
    func legacyJSON() throws {
        let f = try StateFixture()
        defer { f.removeFiles() }
        let state = try f.save(.manual, time: 1)
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        json.removeValue(forKey: "slot")
        json.removeValue(forKey: "isPinned")
        #expect(try JSONDecoder().decode(SaveState.self, from: JSONSerialization.data(withJSONObject: json)) == state)
    }

    @Test("manual limits apply only to the saved context", arguments: [KeepSaveStates.ten, .twentyFive, .fifty])
    func manualLimitContexts(keep: KeepSaveStates) throws {
        let f = try StateFixture()
        defer { f.removeFiles() }
        let profile = try f.otherProfile()
        let other = LaunchContext(gameID: f.context.gameID, buildID: f.context.buildID, saveProfileID: profile.id)
        let otherState = try f.save(.manual, time: 0, context: other)
        try f.settings.set(keep, key: SettingKey.keepSaveStates.rawValue, scope: .app)
        for time in 1...(keep.rawValue + 1) { _ = try f.save(.manual, time: Double(time)) }
        #expect(try f.all().count == keep.rawValue)
        #expect(try f.states.fetchSaveState(id: otherState.id) == otherState)
    }

    @Test("unreadable retention keeps older states, and returning manual states are pinned")
    func unreadableRetention() throws {
        let f = try StateFixture()
        defer { f.removeFiles() }
        try f.settings.setValueJSON("invalid", key: SettingKey.keepSaveStates.rawValue, scope: .app)
        for time in 1...12 { _ = try f.save(.manual, time: Double(time)) }
        #expect(try f.all().count == 12)
        let first = try #require(try f.all().last)
        let deleted = try f.operations.delete(f.operations.planStateDeletion(stateID: first.id))
        try f.operations.restore(deletionID: deleted.id)
        #expect(try f.states.fetchSaveState(id: first.id)?.isPinned == true)
        try f.settings.setValueJSON("invalid", key: SettingKey.keepAutoStates.rawValue, scope: .app)
        for time in 13...20 { _ = try f.save(.auto, time: Double(time)) }
        #expect(try f.all().filter { $0.kind == .auto }.count == 8)
    }

    @Test("failed slot replacement rolls back and preserves the previous state and files")
    func failedSlotReplacement() throws {
        let f = try StateFixture(sql: true)
        defer { f.removeFiles() }
        let first = try f.save(.slot, time: 1, slot: 2)
        let before = try f.assets.fetchAssets()
        let service = SaveStateService(states: f.states, assets: f.assets, assetStore: f.store,
            transactions: RollbackSlotTransaction(inner: f.transactions), thumbnails: StateThumbnailEncoder())
        #expect(throws: RollbackSlotTransaction.Failure.self) {
            try service.save(worker: f.worker, context: f.context, kind: .slot, slot: 2, playtimeSeconds: 2,
                frame: EmulatorVideoFrame(width: 1, height: 1, bgra8888: Data([1, 1, 1, 255]), emulatedNanoseconds: 0))
        }
        #expect(try f.all() == [first])
        #expect(Set(try f.assets.fetchAssets().map(\.id)) == Set(before.map(\.id)))
        try service.load(first, worker: f.worker, context: f.context)
        #expect(service.thumbnailData(for: first) != nil)
    }

    @Test("slot replacement keeps identity, label and pin and discards both old files", arguments: [false, true])
    func slotReplacement(sql: Bool) throws {
        let f = try StateFixture(sql: sql)
        defer { f.removeFiles() }
        let first = try f.save(.slot, time: 1, slot: 2)
        let oldAsset = try #require(try f.assets.fetchAsset(id: first.stateAssetID))
        let oldThumbnail = try #require(try first.screenshotAssetID.flatMap { try f.assets.fetchAsset(id: $0) })
        var named = first
        named.label = "Boss"
        named.isPinned = true
        try f.states.updateSaveState(named)
        try f.worker.perform { try $0.loadPersistentSave(Data([7])) }
        let second = try f.save(.slot, time: 2, slot: 2)
        #expect(second.id == first.id)
        #expect(second.kindName == "Slot 2")
        #expect(second.label == "Boss")
        #expect(second.isPinned)
        #expect(second.createdAt > first.createdAt)
        #expect(try f.all() == [second])
        for asset in [oldAsset, oldThumbnail] {
            #expect(try f.assets.fetchAsset(id: asset.id) == nil)
            #expect(!f.store.fileExists(at: try f.store.managedURL(relativePath: asset.relativePath)))
        }
        try f.service(time: 3).load(second, worker: f.worker, context: f.context)
        #expect(try f.worker.perform { try $0.persistentSaveData() } == Data([7]))
    }

    @Test("slots belong to exact Build and Save Profile", arguments: [false, true])
    func slotContexts(sql: Bool) throws {
        let f = try StateFixture(sql: sql)
        defer { f.removeFiles() }
        let otherBuild = Build(id: UUID(), gameID: f.context.gameID, system: .gameBoy, displayName: "Other",
            imageAssetID: f.build.imageAssetID, imageSHA256: String(repeating: "b", count: 64),
            sourceKind: .importedImage, createdAt: f.date, modifiedAt: f.date)
        try f.builds.insertBuild(otherBuild)
        let profile = try f.otherProfile()
        let contexts = [f.context,
            LaunchContext(gameID: f.context.gameID, buildID: otherBuild.id, saveProfileID: f.context.saveProfileID),
            LaunchContext(gameID: f.context.gameID, buildID: f.context.buildID, saveProfileID: profile.id)]
        for context in contexts {
            let first = try f.save(.slot, time: 1, slot: 2, context: context)
            let second = try f.save(.slot, time: 2, slot: 2, context: context)
            #expect(first.id == second.id)
            #expect(try f.states.fetchSaveStates(buildID: context.buildID, saveProfileID: context.saveProfileID) == [second])
        }
    }

    @Test("restoring an occupied slot keeps both payloads and makes the returning state manual",
        arguments: [false, true], [false, true])
    func restoreCollision(sql: Bool, occupied: Bool) throws {
        let f = try StateFixture(sql: sql)
        defer { f.removeFiles() }
        try f.worker.perform { try $0.loadPersistentSave(Data([1])) }
        var first = try f.save(.slot, time: 1, slot: 2)
        first.label = "Earlier"
        first.isPinned = true
        try f.states.updateSaveState(first)
        let deletion = try f.operations.delete(f.operations.planStateDeletion(stateID: first.id))
        var replacement: SaveState?
        if occupied {
            try f.worker.perform { try $0.loadPersistentSave(Data([2])) }
            replacement = try f.save(.slot, time: 2, slot: 2)
        }
        try f.operations.restore(deletionID: deletion.id)
        let restored = try #require(try f.states.fetchSaveState(id: first.id))
        #expect(restored.kind == (occupied ? .manual : .slot))
        #expect(restored.slot == (occupied ? nil : 2))
        #expect(restored.label == "Earlier")
        #expect(restored.isPinned)
        try f.service(time: 3).load(restored, worker: f.worker, context: f.context)
        #expect(try f.worker.perform { try $0.persistentSaveData() } == Data([1]))
        if let replacement {
            try f.service(time: 3).load(replacement, worker: f.worker, context: f.context)
            #expect(try f.worker.perform { try $0.persistentSaveData() } == Data([2]))
        }
    }

    @Test("reassign demotes occupied slots and Quick States and preserves metadata", arguments: [false, true])
    func reassignCollision(sql: Bool) throws {
        let f = try StateFixture(sql: sql)
        defer { f.removeFiles() }
        let profile = try f.otherProfile()
        let target = LaunchContext(gameID: f.context.gameID, buildID: f.context.buildID, saveProfileID: profile.id)
        for kind in [SaveStateKind.slot, .quick] {
            var source = try f.save(kind, time: 1, slot: kind == .slot ? 2 : nil)
            source.isPinned = true
            source.label = "Keep me"
            try f.states.updateSaveState(source)
            let occupied = try f.save(kind, time: 2, slot: kind == .slot ? 2 : nil, context: target)
            try f.states.reassignSaveStates(buildID: f.context.buildID, fromSaveProfileID: f.context.saveProfileID, toSaveProfileID: profile.id)
            let moved = try #require(try f.states.fetchSaveState(id: source.id))
            #expect(moved.kind == .manual)
            #expect(moved.slot == nil)
            #expect(moved.isPinned)
            #expect(moved.label == source.label)
            #expect(moved.stateAssetID == source.stateAssetID)
            #expect(moved.saveProfileID == profile.id)
            #expect(try f.states.fetchSaveState(id: occupied.id) == occupied)
        }
        let freeSlot = try f.save(.slot, time: 3, slot: 3)
        try f.states.reassignSaveStates(buildID: f.context.buildID, fromSaveProfileID: f.context.saveProfileID, toSaveProfileID: profile.id)
        #expect(try f.states.fetchSaveState(id: freeSlot.id)?.slot == 3)
    }

    @Test("manual overflow is one restorable deletion, excludes other kinds and restores pinned", arguments: [false, true])
    func manualCleanup(sql: Bool) throws {
        let f = try StateFixture(sql: sql)
        defer { f.removeFiles() }
        var pinned = try f.save(.manual, time: 1)
        pinned.isPinned = true
        try f.states.updateSaveState(pinned)
        let quick = try f.save(.quick, time: 2)
        let slot = try f.save(.slot, time: 3, slot: 2)
        let auto = try f.save(.auto, time: 4)
        let crash = try f.save(.crashRecovery, time: 5)
        var manual: [SaveState] = []
        for time in 6...17 { manual.append(try f.save(.manual, time: Double(time))) }
        try f.settings.set(KeepSaveStates.ten, key: SettingKey.keepSaveStates.rawValue, scope: .app)
        #expect(try f.all().count == 17, "changing the setting alone keeps all states")
        _ = try f.save(.quick, time: 18)
        #expect(try f.operations.recentlyDeleted().isEmpty)
        let new = try f.save(.manual, time: 19)
        let deleted = try #require(try f.operations.recentlyDeleted().first)
        #expect(try f.operations.recentlyDeleted().count == 1)
        #expect(Set(deleted.records.saveStateIDs) == Set(manual.prefix(3).map(\.id)))
        let live = try f.all()
        #expect(live.contains(new))
        #expect(live.filter { $0.kind == .manual && !$0.isPinned }.count == 10)
        for state in [pinned, slot, auto, crash] { #expect(live.contains(state)) }
        #expect(live.contains { $0.id == quick.id })
        for state in manual.prefix(3) {
            let asset = try #require(try f.assets.fetchAsset(id: state.stateAssetID))
            #expect(f.store.fileExists(at: try f.store.managedURL(relativePath: asset.relativePath)))
        }
        try f.operations.restore(deletionID: deleted.id)
        for state in manual.prefix(3) { #expect(try f.states.fetchSaveState(id: state.id)?.isPinned == true) }
        _ = try f.save(.manual, time: 20)
        for state in manual.prefix(3) { #expect(try f.states.fetchSaveState(id: state.id) != nil) }
    }

    @Test("Auto retention reads the setting at save time and pinned Autos do not count", arguments: KeepAutoStates.allCases)
    func autoCleanup(keep: KeepAutoStates) throws {
        let f = try StateFixture()
        defer { f.removeFiles() }
        var pinned = try f.save(.auto, time: 1)
        pinned.isPinned = true
        try f.states.updateSaveState(pinned)
        try f.settings.set(keep, key: SettingKey.keepAutoStates.rawValue, scope: .app)
        var first: SaveState?
        for time in 2...16 {
            let state = try f.save(.auto, time: Double(time))
            if first == nil { first = state }
        }
        #expect(try f.all().filter { $0.kind == .auto && !$0.isPinned }.count == keep.rawValue)
        #expect(try f.states.fetchSaveState(id: pinned.id) == pinned)
        let expired = try #require(first)
        #expect(try f.assets.fetchAsset(id: expired.stateAssetID) == nil)
        #expect(!f.store.fileExists(at: f.store.stateURL(stateID: expired.id)))
    }

    @Test("without Auto State history only the newest unpinned Auto State is kept, and pinned ones stay")
    func autoCleanupWithoutHistory() throws {
        let f = try StateFixture()
        defer { f.removeFiles() }
        try f.settings.set(KeepAutoStates.ten, key: SettingKey.keepAutoStates.rawValue, scope: .app)
        var pinned = try f.save(.auto, time: 1)
        pinned.isPinned = true
        try f.states.updateSaveState(pinned)
        let older = try (2...5).map { try f.save(.auto, time: Double($0)) }
        #expect(try f.all().filter { $0.kind == .auto && !$0.isPinned }.count == 4)

        f.history.set(false)
        #expect(try f.all().filter { $0.kind == .auto && !$0.isPinned }.count == 4, "losing history deletes nothing by itself")
        let newest = try f.save(.auto, time: 6)
        #expect(try f.all().filter { $0.kind == .auto && !$0.isPinned }.map(\.id) == [newest.id])
        #expect(try f.states.fetchSaveState(id: pinned.id) == pinned)
        for state in older {
            #expect(try f.assets.fetchAsset(id: state.stateAssetID) == nil)
            #expect(!f.store.fileExists(at: f.store.stateURL(stateID: state.id)))
        }
        #expect(try SettingsResolver(store: f.settings).appValue(KeepAutoStates.self, key: .keepAutoStates) == .ten,
            "the stored choice is kept")

        f.history.set(true)
        for time in 7...16 { _ = try f.save(.auto, time: Double(time)) }
        #expect(try f.all().filter { $0.kind == .auto && !$0.isPinned }.count == 10)
    }

    @Test("manual cleanup protects the triggering save when timestamps tie or move backward")
    func newSaveSurvivesClockChanges() throws {
        let f = try StateFixture()
        defer { f.removeFiles() }
        try f.settings.set(KeepSaveStates.ten, key: SettingKey.keepSaveStates.rawValue, scope: .app)
        for _ in 0..<12 {
            let saved = try f.save(.manual, time: 10)
            #expect(try f.states.fetchSaveState(id: saved.id) == saved)
        }
        let saved = try f.save(.manual, time: 1)
        #expect(try f.states.fetchSaveState(id: saved.id) == saved)
        #expect(try f.all().count == 10)
    }

    @Test("a cleanup transaction failure leaves the new manual state saved and all older files intact")
    func failedCleanup() throws {
        let f = try StateFixture()
        defer { f.removeFiles() }
        for time in 1...10 { _ = try f.save(.manual, time: Double(time)) }
        try f.settings.set(KeepSaveStates.ten, key: SettingKey.keepSaveStates.rawValue, scope: .app)
        let refusing = f.deletionOperations(transactions: RefusingCleanupTransaction())
        let service = f.service(time: 11, deletion: refusing)
        let new = try service.save(worker: f.worker, context: f.context, kind: .manual, playtimeSeconds: 11)
        #expect(try f.states.fetchSaveState(id: new.id) == new)
        #expect(try f.all().count == 11)
        #expect(try f.operations.recentlyDeleted().isEmpty)
        try service.load(new, worker: f.worker, context: f.context)
        for state in try f.all() { #expect(f.store.fileExists(at: f.store.stateURL(stateID: state.id))) }
    }
}

private struct RollbackSlotTransaction: LibraryTransactionRunner {
    struct Failure: Error {}
    let inner: any LibraryTransactionRunner
    func run<T: Sendable>(_ operation: @Sendable () throws -> T) throws -> T {
        try inner.run { () throws -> T in
            _ = try operation()
            throw Failure()
        }
    }
}

private struct RefusingCleanupTransaction: LibraryTransactionRunner {
    struct Failure: Error {}
    func run<T: Sendable>(_ operation: @Sendable () throws -> T) throws -> T { throw Failure() }
}

/// Whether Auto State history is kept, changed between saves as an entitlement would be.
private final class HistorySwitch: @unchecked Sendable {
    private let lock = NSLock()
    private var value = true

    var isOn: Bool { lock.withLock { value } }
    func set(_ isOn: Bool) { lock.withLock { value = isOn } }
}

private struct StateThumbnailEncoder: FrameImageEncoding {
    let fileExtension = "png"
    func encode(_ frame: EmulatorVideoFrame) throws -> Data { frame.bgra8888 }
}

private struct StateFixture {
    let root: URL
    let store: ManagedFileStore
    let games: any GameRepository
    let builds: any BuildRepository
    let profiles: any SaveProfileRepository
    let states: any SaveStateRepository
    let recipes: any PatchRecipeRepository
    let assets: any ManagedAssetInventoryRepository
    let deletions: any LibraryDeletionRepository
    let settings: any SettingsStore
    let transactions: any LibraryTransactionRunner
    let context: LaunchContext
    let build: Build
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let worker = SessionWorker(core: FakeEmulatorCore())
    let history = HistorySwitch()

    init(sql: Bool = false) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = try ManagedFileStore(rootURL: root)
        if sql {
            let database = try AppDatabase(url: root.appendingPathComponent("Library.sqlite"))
            try database.migrate()
            let r = database.makeRepositories()
            games = r.games; builds = r.builds; profiles = r.saveProfiles; states = r.saveStates
            recipes = r.patchRecipes; assets = r.assets; deletions = r.deletions; settings = r.settings; transactions = r.transactions
        } else {
            let g = InMemoryGameRepository(), b = InMemoryBuildRepository(), p = InMemorySaveProfileRepository()
            let s = InMemorySaveStateRepository(), r = InMemoryPatchRecipeRepository(), a = InMemoryAssetRepository()
            games = g; builds = b; profiles = p; states = s; recipes = r; assets = a
            deletions = InMemoryLibraryDeletionRepository(games: g, builds: b, profiles: p, states: s, recipes: r, assets: a)
            settings = InMemorySettingsStore(); transactions = PassthroughTransactionRunner()
        }
        let game = Game(id: UUID(), primaryTitle: "Test", systemFamily: "gameboy", createdAt: date, modifiedAt: date)
        let rom = ManagedAsset(id: UUID(), kind: .sourceImage, storageClass: .source, contentSHA256: String(repeating: "a", count: 64),
            byteLength: 0, relativePath: "SourceROMs/test.gb", integrityStatus: .verified, createdAt: date)
        build = Build(id: UUID(), gameID: game.id, system: .gameBoy, displayName: "Test", imageAssetID: rom.id,
            imageSHA256: rom.contentSHA256, sourceKind: .importedImage, isBase: true, createdAt: date, modifiedAt: date)
        let profile = SaveProfile(id: UUID(), gameID: game.id, displayName: "Main", createdAt: date, modifiedAt: date)
        context = LaunchContext(gameID: game.id, buildID: build.id, saveProfileID: profile.id)
        try games.insertGame(game)
        try assets.insertAsset(rom)
        try builds.insertBuild(build)
        try profiles.insertSaveProfile(profile)
    }

    var operations: LibraryDeletionOperations { deletionOperations(transactions: transactions) }
    func deletionOperations(transactions: any LibraryTransactionRunner) -> LibraryDeletionOperations {
        LibraryDeletionOperations(games: games, builds: builds, profiles: profiles, states: states, recipes: recipes,
            deletions: deletions, assetStore: store, transactions: transactions, settings: SettingsResolver(store: settings))
    }
    func service(time: Double, deletion: LibraryDeletionOperations? = nil) -> SaveStateService {
        let timestamp = date.addingTimeInterval(time)
        return SaveStateService(states: states, assets: assets, assetStore: store, settings: SettingsResolver(store: settings),
            deletion: deletion ?? operations, transactions: transactions, thumbnails: StateThumbnailEncoder(),
            keepsAutoStateHistory: { [history] in history.isOn }, now: { timestamp })
    }
    func save(_ kind: SaveStateKind, time: Double, slot: Int? = nil, context: LaunchContext? = nil) throws -> SaveState {
        try service(time: time).save(worker: worker, context: context ?? self.context, kind: kind, slot: slot,
            playtimeSeconds: time, frame: EmulatorVideoFrame(width: 1, height: 1, bgra8888: Data([1, 1, 1, 255]), emulatedNanoseconds: 0))
    }
    func all() throws -> [SaveState] { try states.fetchSaveStates(buildID: context.buildID, saveProfileID: context.saveProfileID) }
    func otherProfile() throws -> SaveProfile {
        let profile = SaveProfile(id: UUID(), gameID: context.gameID, displayName: "Other", createdAt: date, modifiedAt: date)
        try profiles.insertSaveProfile(profile)
        return profile
    }
    func removeFiles() { try? FileManager.default.removeItem(at: root) }
}

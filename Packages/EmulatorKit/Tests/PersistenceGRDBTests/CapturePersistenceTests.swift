import AssetStorage
import EmulationCore
import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import GRDB
import Importing
import QuickPlay
import Testing
@testable import PersistenceGRDB

/// Prints kept in a Game's Captures, on a real database where Recently Deleted, purges and
/// backups apply to them.
@Suite struct CapturePersistenceTests {
    @Test func aPrintSurvivesTheArchiveWithItsRowsAndMargins() throws {
        let slip = try Self.slip(rows: 16, shade: 0x55, bottomMargin: 0)
        var longer = slip
        try longer.append(try PrinterOutput(height: 8, luminance: Data(repeating: 0xAA, count: 160 * 8),
            topMargin: 0, bottomMargin: 3, exposure: 40))
        let decoded = try PrinterSlipArchive.decode(try PrinterSlipArchive.encode(longer), id: longer.id)
        #expect(decoded == longer)
        try longer.append(try PrinterOutput(height: 8, luminance: Data(repeating: 0xAA, count: 160 * 8),
            topMargin: 0, bottomMargin: 3, exposure: 40, followsCopy: true))
        #expect(try PrinterSlipArchive.decode(try PrinterSlipArchive.encode(longer), id: longer.id) == longer)
        let single = PrinterSlip(output: try PrinterOutput(height: 1, luminance: Data(count: 160),
            topMargin: 1, bottomMargin: 3, exposure: 64))
        let rows = Data(count: 160).base64EncodedString()
        #expect(String(decoding: try PrinterSlipArchive.encode(single), as: UTF8.self)
            == #"{"sections":[{"bottomMargin":3,"exposure":64,"height":1,"rows":"\#(rows)","topMargin":1}],"version":1}"#)
        #expect(throws: PrinterSlipArchive.ArchiveError.invalidRows) {
            try PrinterSlipArchive.decode(Data(#"{"version":1,"sections":[{"height":2,"topMargin":0,"bottomMargin":0,"exposure":0,"rows":"AAAA"}]}"#.utf8), id: UUID())
        }
    }

    @Test func morePaperOnTheSamePrintUpdatesItInPlace() throws {
        let library = try RestoreLibrary()
        defer { library.remove() }
        let prints = library.prints()
        var slip = try Self.slip(rows: 16, shade: 0x00, bottomMargin: 0)
        let first = try #require(try prints.save(slip, gameID: library.rom.game.id, buildID: library.rom.build.id, saveProfileID: nil))
        try slip.append(try PrinterOutput(height: 16, luminance: Data(repeating: 0xFF, count: 160 * 16),
            topMargin: 0, bottomMargin: 2, exposure: 0))
        let second = try #require(try prints.save(slip, gameID: library.rom.game.id, buildID: library.rom.build.id, saveProfileID: nil))

        #expect(second.id == first.id && second.assetID == first.assetID && second.createdAt == first.createdAt)
        #expect(second.modifiedAt > first.modifiedAt)
        let kept = try prints.captures(gameID: library.rom.game.id)
        #expect(kept.map(\.id) == [slip.id])
        #expect(try prints.slip(for: kept[0]) == slip)
        let asset = try #require(try library.repos.assets.fetchAsset(id: first.assetID))
        let bytes = try PrinterSlipArchive.encode(slip)
        #expect(asset.kind == .capture && asset.byteLength == Int64(bytes.count))
    }

    @Test func theGameKeepsFiftyUnpinnedPrintsAndPinnedOnesNeverCount() throws {
        let library = try RestoreLibrary()
        defer { library.remove() }
        let prints = library.prints()
        let gameID = library.rom.game.id
        let pinned = try #require(try prints.save(Self.slip(rows: 8), gameID: gameID, buildID: nil, saveProfileID: nil))
        try prints.setPinned(true, captureID: pinned.id)
        var saved: [Capture] = []
        for _ in 0..<51 {
            saved.append(try #require(try prints.save(Self.slip(rows: 8), gameID: gameID, buildID: nil, saveProfileID: nil)))
        }

        let kept = try prints.captures(gameID: gameID)
        #expect(kept.count == 51)
        #expect(kept.contains { $0.id == pinned.id })
        #expect(!kept.contains { $0.id == saved[0].id })
        let cleaned = try #require(try library.deletion(prints: true).recentlyDeleted().first)
        #expect(cleaned.kind == .capture && cleaned.title == "Cleaned-up Prints")
        #expect(cleaned.records == LibraryRecordSet(captureIDs: [saved[0].id]))

        // Unpinning the old one puts the Game past the cap, but removes nothing by itself.
        try prints.setPinned(false, captureID: pinned.id)
        #expect(try prints.captures(gameID: gameID).count == 51)
        #expect(try prints.captures(gameID: gameID).contains { $0.id == pinned.id })

        // The next print moves the oldest unpinned prints past the cap to Recently Deleted.
        _ = try #require(try prints.save(Self.slip(rows: 8), gameID: gameID, buildID: nil, saveProfileID: nil))
        #expect(try prints.captures(gameID: gameID).count == 50)
        #expect(!(try prints.captures(gameID: gameID)).contains { $0.id == pinned.id })
    }

    @Test func withoutPrintHistoryAGameKeepsItsLatestTenAndTheRestCanBeRestored() throws {
        let library = try RestoreLibrary()
        defer { library.remove() }
        let prints = library.prints(history: PrintHistorySwitch(false))
        let deletion = library.deletion(prints: true)
        let gameID = library.rom.game.id
        let pinned = try #require(try prints.save(Self.slip(rows: 8), gameID: gameID, buildID: nil, saveProfileID: nil))
        try prints.setPinned(true, captureID: pinned.id)
        var saved: [Capture] = []
        for _ in 0..<12 {
            saved.append(try #require(try prints.save(Self.slip(rows: 8), gameID: gameID, buildID: nil, saveProfileID: nil)))
        }

        let kept = try prints.captures(gameID: gameID)
        #expect(kept.filter { !$0.isPinned }.map(\.id) == saved.suffix(10).reversed().map(\.id))
        #expect(kept.contains { $0.id == pinned.id })
        let cleaned = try deletion.recentlyDeleted()
        #expect(cleaned.allSatisfy { $0.kind == .capture && $0.title == "Cleaned-up Prints" })
        #expect(Set(cleaned.flatMap(\.records.captureIDs)) == Set(saved.prefix(2).map(\.id)))

        try deletion.restore(deletionID: try #require(cleaned.first).id)
        #expect(try prints.captures(gameID: gameID).count == 12, "a restored print stays until the next print")
    }

    @Test(arguments: KeepPrints.allCases)
    func withPrintHistoryAGameKeepsTheChosenNumber(keep: KeepPrints) throws {
        let library = try RestoreLibrary()
        defer { library.remove() }
        try library.repos.settings.set(keep, key: SettingKey.keepPrints.rawValue, scope: .app)
        let prints = library.prints()
        let gameID = library.rom.game.id
        #expect(prints.keptPrints() == keep.rawValue)
        for _ in 0..<(keep.rawValue + 2) {
            try prints.save(Self.slip(rows: 8), gameID: gameID, buildID: nil, saveProfileID: nil)
        }
        #expect(try prints.captures(gameID: gameID).count == keep.rawValue)
    }

    @Test func losingPrintHistoryRemovesNothingUntilTheNextPrintAndKeepsTheChoice() throws {
        let library = try RestoreLibrary()
        defer { library.remove() }
        try library.repos.settings.set(KeepPrints.oneHundred, key: SettingKey.keepPrints.rawValue, scope: .app)
        let history = PrintHistorySwitch(true)
        let prints = library.prints(history: history)
        let deletion = library.deletion(prints: true)
        let gameID = library.rom.game.id
        var saved: [Capture] = []
        for _ in 0..<12 {
            saved.append(try #require(try prints.save(Self.slip(rows: 8), gameID: gameID, buildID: nil, saveProfileID: nil)))
        }
        try prints.setPinned(true, captureID: saved[0].id)

        history.set(false)
        #expect(prints.keptPrints() == KeepPrints.withoutHistory)
        #expect(try prints.captures(gameID: gameID).count == 12, "losing print history removes nothing by itself")
        #expect(try deletion.recentlyDeleted().isEmpty)

        let newest = try #require(try prints.save(Self.slip(rows: 8), gameID: gameID, buildID: nil, saveProfileID: nil))
        let unpinned = try prints.captures(gameID: gameID).filter { !$0.isPinned }
        #expect(unpinned.count == 10 && unpinned.first?.id == newest.id)
        #expect(try prints.captures(gameID: gameID).contains { $0.id == saved[0].id }, "pinned prints stay")
        let cleaned = try deletion.recentlyDeleted()
        #expect(cleaned.count == 1 && cleaned.first?.title == "Cleaned-up Prints")
        #expect(Set(cleaned.first?.records.captureIDs ?? []) == Set([saved[1].id, saved[2].id]))
        #expect(try SettingsResolver(store: library.repos.settings).appValue(KeepPrints.self, key: .keepPrints) == .oneHundred,
            "the stored choice is kept")

        history.set(true)
        #expect(prints.keptPrints() == 100)
        try deletion.restore(deletionID: try #require(cleaned.first).id)
        try prints.save(Self.slip(rows: 8), gameID: gameID, buildID: nil, saveProfileID: nil)
        #expect(try prints.captures(gameID: gameID).filter { !$0.isPinned }.count == 13)
    }

    @Test func anUnreadableKeepPrintsSettingKeepsEveryPrint() throws {
        let library = try RestoreLibrary()
        defer { library.remove() }
        try library.repos.settings.setValueJSON("invalid", key: SettingKey.keepPrints.rawValue, scope: .app)
        let prints = library.prints()
        let gameID = library.rom.game.id
        #expect(prints.keptPrints() == nil)
        for _ in 0..<(KeepPrints.defaultValue.rawValue + 1) {
            try prints.save(Self.slip(rows: 8), gameID: gameID, buildID: nil, saveProfileID: nil)
        }
        #expect(try prints.captures(gameID: gameID).count == KeepPrints.defaultValue.rawValue + 1)
        #expect(library.prints(history: PrintHistorySwitch(false)).keptPrints() == KeepPrints.withoutHistory)
    }

    @Test func aDeletedPrintComesBackOrIsPurgedWithItsFile() throws {
        let library = try RestoreLibrary()
        defer { library.remove() }
        let prints = library.prints()
        let deletion = library.deletion(prints: true)
        let slip = try Self.slip(rows: 8)
        let capture = try #require(try prints.save(slip, gameID: library.rom.game.id, buildID: nil, saveProfileID: nil))
        let url = library.store.captureURL(captureID: capture.id)

        let deleted = try deletion.delete(deletion.planCaptureDeletion(captureIDs: [capture.id]))
        #expect(deleted.title == "Print")
        #expect(try prints.captures(gameID: library.rom.game.id).isEmpty)
        #expect(try prints.save(slip, gameID: library.rom.game.id, buildID: nil, saveProfileID: nil) == nil,
            "more paper on a deleted print doesn't bring it back")
        try deletion.restore(deletionID: deleted.id)
        #expect(try prints.captures(gameID: library.rom.game.id).map(\.id) == [capture.id])

        let again = try deletion.delete(deletion.planCaptureDeletion(captureIDs: [capture.id]))
        try deletion.purge(deletionID: again.id)
        #expect(try library.repos.assets.fetchAsset(id: capture.assetID) == nil)
        #expect(!library.store.fileExists(at: url))
        #expect(try library.repos.deletions.fetchTombstones().contains { $0.recordID == capture.id && $0.kind == .capture })
    }

    @Test func aDiscardedPrintGoesToRecentlyDeletedAndAnUnsavedOneIsIgnored() throws {
        let library = try RestoreLibrary()
        defer { library.remove() }
        let prints = library.prints()
        let slip = try Self.slip(rows: 8)
        try prints.save(slip, gameID: library.rom.game.id, buildID: nil, saveProfileID: nil)

        try prints.delete(captureID: slip.id)
        #expect(try prints.captures(gameID: library.rom.game.id).isEmpty)
        #expect(try library.deletion(prints: true).recentlyDeleted().map(\.title) == ["Print"])
        #expect(try prints.save(slip, gameID: library.rom.game.id, buildID: nil, saveProfileID: nil) == nil)
        try prints.delete(captureID: UUID())
    }

    @Test func aGameTakesItsPrintsAndAPrintDeletedOnItsOwnGoesWhenTheGameIsPurged() throws {
        let library = try RestoreLibrary()
        defer { library.remove() }
        let prints = library.prints()
        let deletion = library.deletion(prints: true)
        let gameID = library.rom.game.id
        let live = try #require(try prints.save(Self.slip(rows: 8), gameID: gameID, buildID: library.rom.build.id, saveProfileID: nil))
        let alone = try #require(try prints.save(Self.slip(rows: 8), gameID: gameID, buildID: nil, saveProfileID: nil))
        let aloneDeletion = try deletion.delete(deletion.planCaptureDeletion(captureIDs: [alone.id]))

        let plan = try deletion.planGameDeletion(gameID: gameID)
        #expect(plan.records.captureIDs == [live.id])
        let gameDeletion = try deletion.delete(plan)
        try deletion.purge(deletionID: gameDeletion.id)

        #expect(try deletion.recentlyDeleted().isEmpty, "the lone print's deletion went with its Game")
        #expect(!(try deletion.recentlyDeleted()).contains { $0.id == aloneDeletion.id })
        for capture in [live, alone] {
            #expect(try library.repos.assets.fetchAsset(id: capture.assetID) == nil)
            #expect(!library.store.fileExists(at: library.store.captureURL(captureID: capture.id)))
        }
        #expect(try library.db.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM captures") } == 0)
    }

    @Test func printsTravelInABackupAndAGamePackage() throws {
        let library = try RestoreLibrary()
        defer { library.remove() }
        let prints = library.prints()
        let slip = try Self.slip(rows: 16, shade: 0xAA)
        let capture = try #require(try prints.save(slip, gameID: library.rom.game.id, buildID: library.rom.build.id, saveProfileID: nil))
        try prints.setPinned(true, captureID: capture.id)
        let other = try library.importGame(TestROM.make(title: "OTHER", payloadByte: 2), title: "Other")
        _ = try prints.save(Self.slip(rows: 8), gameID: other.game.id, buildID: nil, saveProfileID: nil)

        let destination = try RestoreLibrary(root: library.root, name: "Destination", rom: TestROM.make(title: "ELSEWHERE"))
        let package = try library.service.export(to: library.root.appendingPathComponent("Package"), displayName: "Moon Garden",
            appVersion: "1", appBuild: "1", includeROMs: true, gameID: library.rom.game.id)
        let prepared = try destination.service.prepare(from: package)
        #expect(prepared.manifest.recordCounts["captures"] == 1)
        let review = try destination.service.review(prepared)
        #expect(review.conflicts.isEmpty)
        _ = try destination.service.restore(prepared, review: review, choices: [:])

        let restored = try destination.prints().captures(gameID: library.rom.game.id)
        #expect(restored.map(\.id) == [capture.id])
        #expect(restored.first?.isPinned == true)
        #expect(try destination.prints().slip(for: restored[0]) == slip)
        #expect(try destination.prints().captures(gameID: other.game.id).isEmpty)

        // The same package again changes nothing.
        let again = try destination.service.review(destination.service.prepare(from: package))
        #expect(again.added == 0 && again.conflicts.isEmpty)
    }

    @Test func quickPlayPrintsMoveToTheGameWhenItIsAddedToTheLibrary() throws {
        let library = try RestoreLibrary()
        defer { library.remove() }
        let workspace = QuickPlayWorkspace(profiles: library.repos.saveProfiles, assets: library.repos.assets, assetStore: library.store)
        let picked = library.root.appendingPathComponent("Quick.gb")
        try TestROM.make(title: "QUICKIE", payloadByte: 3).write(to: picked)
        let session = try workspace.start(romURL: picked)
        let sessionPrints = QuickPlayPrints(session: session, files: library.store)
        var first = try Self.slip(rows: 8, bottomMargin: 0)
        try sessionPrints.save(first)
        try first.append(try PrinterOutput(height: 8, luminance: Data(repeating: 0xFF, count: 160 * 8),
            topMargin: 0, bottomMargin: 3, exposure: 64))
        try sessionPrints.save(first)
        let second = try Self.slip(rows: 16, shade: 0x55)
        try sessionPrints.save(second)
        #expect(try sessionPrints.slips().map(\.slip) == [first, second])
        let discarded = try Self.slip(rows: 8, shade: 0xAA)
        try sessionPrints.save(discarded)
        try sessionPrints.discard(id: discarded.id)
        #expect(try sessionPrints.slips().map(\.slip) == [first, second])

        let analyzer = ROMImportAnalyzer(builds: library.repos.builds, games: library.repos.games,
            fingerprints: library.repos.fingerprints, toolchainReports: library.repos.toolchainReports, assetStore: library.store)
        let committer = ImportCommitter(games: library.repos.games, builds: library.repos.builds, assets: library.repos.assets,
            toolchainReports: library.repos.toolchainReports, fingerprints: library.repos.fingerprints,
            assetStore: library.store, transactions: library.repos.transactions)
        let promoter = PromoteQuickPlay(analyzer: analyzer, committer: committer, workspace: workspace,
            builds: library.repos.builds, profiles: library.repos.saveProfiles, states: library.repos.saveStates,
            assets: library.repos.assets, assetStore: library.store, prints: library.prints())
        let plan = ROMImportPlan(analysis: try promoter.analyze(session, targetGameID: nil),
            disposition: .createGame(title: "Quickie"), buildDisplayName: "Base", markAsBase: true)
        let result = try promoter.promote(session: session, plan: plan, saveDisposition: .keepExisting)

        #expect(result.shortfalls.isEmpty)
        let kept = try library.prints().captures(gameID: result.importResult.game.id)
        #expect(Set(kept.map(\.id)) == [first.id, second.id])
        #expect(kept.allSatisfy { $0.buildID == result.build.id && $0.saveProfileID == nil })
        #expect(try library.prints().slip(for: try #require(kept.first { $0.id == first.id })) == first)
        #expect(!library.store.fileExists(at: session.rootURL), "the session goes once its prints are in")
    }

    static func slip(rows: Int, shade: UInt8 = 0x00, bottomMargin: Int = 3) throws -> PrinterSlip {
        PrinterSlip(output: try PrinterOutput(height: rows, luminance: Data(repeating: shade, count: 160 * rows),
            topMargin: 1, bottomMargin: bottomMargin, exposure: 64))
    }
}

/// Whole seconds, one apart, so the database's millisecond dates order every print.
final class SteppingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var seconds: TimeInterval = 1_700_000_000

    func next() -> Date { lock.withLock { seconds += 1; return Date(timeIntervalSince1970: seconds) } }
}

/// Whether a Game keeps print history, changed between prints as an entitlement would be.
final class PrintHistorySwitch: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool

    init(_ isOn: Bool) { value = isOn }

    var isOn: Bool { lock.withLock { value } }
    func set(_ isOn: Bool) { lock.withLock { value = isOn } }
}

extension RestoreLibrary {
    func deletion(prints: Bool) -> LibraryDeletionOperations {
        LibraryDeletionOperations(games: repos.games, builds: repos.builds, profiles: repos.saveProfiles,
            states: repos.saveStates, captures: prints ? repos.captures : nil, recipes: repos.patchRecipes,
            deletions: repos.deletions, assetStore: store, transactions: repos.transactions)
    }

    func prints(clock: SteppingClock = SteppingClock(), history: PrintHistorySwitch = PrintHistorySwitch(true)) -> PrintCaptures {
        PrintCaptures(captures: repos.captures, assets: repos.assets, assetStore: store,
            transactions: repos.transactions, deletion: deletion(prints: true),
            settings: SettingsResolver(store: repos.settings), keepsPrintHistory: { history.isOn }, now: clock.next)
    }
}

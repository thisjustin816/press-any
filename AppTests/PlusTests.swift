import EmulatorApplication
import EmulatorDomain
import Importing
import XCTest
@testable import PressAny

/// Plus gating without StoreKit: what's locked, what plays, and that stored choices survive.
@MainActor
final class PlusTests: XCTestCase {
    func testRoadmapListsWhatPlusHoldsAndWhatsComing() {
        XCTAssertFalse(PlusRoadmap.upcoming.isEmpty)
        XCTAssertEqual(PlusRoadmap.includedToday.map(\.title), ["LCD Filters"])
        let items = PlusRoadmap.includedToday + PlusRoadmap.upcoming
        XCTAssertEqual(Set(items.map(\.id)).count, items.count, "titles are unique")
        for item in items {
            XCTAssertFalse(item.detail.isEmpty, "\(item.title) has a description")
        }
    }

    func testStoredLCDFilterPlaysAsOffWithoutPlusAndIsKept() throws {
        let fixture = try LCDFixture(plus: .fixed(ownsPlus: false))
        defer { fixture.remove() }
        XCTAssertEqual(fixture.container.lcdFilter(for: fixture.context), .off)
        XCTAssertEqual(fixture.container.lcdFilter(system: .gameBoy), .off)
        XCTAssertEqual(try fixture.storedFilter(), .lcd1x, "the stored choice isn't deleted")

        let owner = try AppContainer(rootURL: fixture.root, plus: .fixed(ownsPlus: true))
        XCTAssertEqual(owner.lcdFilter(for: fixture.context), .lcd1x, "Plus brings the stored filter back")
    }

    func testLockedOptionsAreMarkedAndOffStaysFree() {
        let locked = PlusGate(isUnlocked: false)
        XCTAssertTrue(locked.isLocked(LCDFilter.lcd1x.needsPlus))
        XCTAssertTrue(locked.isLocked(LCDFilter.lcd3x.needsPlus))
        XCTAssertFalse(locked.isLocked(LCDFilter.off.needsPlus))
        XCTAssertEqual(locked.label("LCD 1×", needsPlus: true), "LCD 1× (Plus)")
        XCTAssertEqual(locked.label("Off", needsPlus: false), "Off")

        let unlocked = PlusGate(isUnlocked: true)
        XCTAssertFalse(unlocked.isLocked(LCDFilter.lcd3x.needsPlus))
        XCTAssertEqual(unlocked.label("LCD 1×", needsPlus: true), "LCD 1×")
        XCTAssertEqual(PlusStore.fixed(ownsPlus: false).effective(.lcd3x), .off)
        XCTAssertEqual(PlusStore.fixed(ownsPlus: true).effective(.lcd3x), .lcd3x)
        XCTAssertTrue(DisplaySettingsPage.effectsFooter(locked).contains("a filter you already chose is kept"))
        XCTAssertFalse(DisplaySettingsPage.effectsFooter(PlusGate(isUnlocked: true)).contains("Plus"))
    }
}

/// A library with one Game Boy Build and LCD 1× chosen in App Settings.
@MainActor
struct LCDFixture {
    let root: URL
    let container: AppContainer
    let context: LaunchContext

    init(plus: PlusStore) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        container = try AppContainer(rootURL: root, plus: plus)
        let file = root.appendingPathComponent("Plus Fixture.gb")
        try Data(repeating: 0, count: 0x8000).write(to: file)
        let analysis = try container.importAnalyzer.analyzeROM(at: file, targetGameID: nil)
        let result = try container.importCommitter.commit(ROMImportPlan(
            analysis: analysis, disposition: .createGame(title: "Plus Fixture"),
            buildDisplayName: "Original", markAsBase: true
        ))
        context = LaunchContext(gameID: result.build.gameID, buildID: result.build.id, saveProfileID: UUID())
        try container.repositories.settings.set(LCDFilter.lcd1x, key: SettingKey.lcdFilter.rawValue, scope: .app)
    }

    func storedFilter() throws -> LCDFilter? {
        try SettingsResolver(store: container.repositories.settings).appValue(LCDFilter.self, key: .lcdFilter)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

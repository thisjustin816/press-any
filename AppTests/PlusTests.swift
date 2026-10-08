import EmulatorApplication
import EmulatorDomain
import Importing
import UIKit
import XCTest
@testable import PressAny

/// Plus gating without StoreKit: what's locked, what plays, and that stored choices survive.
@MainActor
final class PlusTests: XCTestCase {
    func testRoadmapListsWhatPlusHoldsAndWhatsComing() {
        XCTAssertFalse(PlusRoadmap.upcoming.isEmpty)
        XCTAssertEqual(PlusRoadmap.includedToday.map(\.title), ["LCD Filters", "App Icons", "Auto State History"])
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

    func testKeepAutoStatesIsLockedToTheNewestWithoutPlus() {
        let locked = PlusGate(isUnlocked: false)
        for choice in KeepAutoStates.allCases {
            XCTAssertTrue(locked.isLocked(choice.needsPlus), "\(choice) opens the Plus screen")
            XCTAssertEqual(locked.keptAutoStates(choice), 1)
            XCTAssertEqual(PlusGate(isUnlocked: true).keptAutoStates(choice), choice.rawValue)
        }
        XCTAssertEqual(locked.label(KeepAutoStates.ten.displayName, needsPlus: true), "10 (Plus)")
        XCTAssertTrue(PlayingSettingsPage.saveStatesFooter(locked)
            .hasPrefix("Without Plus, \(AppBrand.displayName) keeps your latest Auto State."))
        XCTAssertFalse(PlayingSettingsPage.saveStatesFooter(PlusGate(isUnlocked: true)).contains("Without Plus"))
    }

    func testGameSessionsReadOwnershipOffTheMainActor() async {
        let owned = PlusStore.fixed(ownsPlus: true).ownership
        let notOwned = PlusStore.fixed(ownsPlus: false).ownership
        let answers = await Task.detached { (owned.isOwned, notOwned.isOwned) }.value
        XCTAssertTrue(answers.0)
        XCTAssertFalse(answers.1)
    }

    func testAppIconsNeedPlusExceptTheDefaultAndAreBundled() throws {
        XCTAssertFalse(AppIconChoice.standard.needsPlus)
        XCTAssertNil(AppIconChoice.standard.iconName)
        XCTAssertEqual(AppIconChoice(iconName: nil), .standard)
        XCTAssertEqual(AppIconChoice(iconName: "AppIcon-Unknown"), .standard)

        let infoIcons = (Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons")
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons~iphone")) as? [String: Any]
        let alternates = try XCTUnwrap(infoIcons?["CFBundleAlternateIcons"] as? [String: Any],
            "project.yml includes every app icon set")
        for choice in AppIconChoice.allCases {
            XCTAssertNotNil(UIImage(named: choice.previewName), "\(choice.title) has a preview")
            guard let name = choice.iconName else { continue }
            XCTAssertTrue(choice.needsPlus)
            XCTAssertEqual(AppIconChoice(iconName: name), choice)
            XCTAssertNotNil(alternates[name], "\(name) is an alternate icon")
        }
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

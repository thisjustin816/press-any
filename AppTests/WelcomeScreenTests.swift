import Foundation
import XCTest
@testable import PressAny

final class WelcomeScreenTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        suiteName = "WelcomeScreenTests-\(UUID())"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testItShowsOnceUntilItsContentChanges() {
        XCTAssertTrue(WelcomeScreen.showsAtLaunch(defaults: defaults, environment: [:]))
        WelcomeScreen.markShown(defaults: defaults)
        XCTAssertFalse(WelcomeScreen.showsAtLaunch(defaults: defaults, environment: [:]))

        defaults.set(WelcomeScreen.contentVersion - 1, forKey: WelcomeScreen.shownVersionKey)
        XCTAssertTrue(WelcomeScreen.showsAtLaunch(defaults: defaults, environment: [:]), "new content shows again")
    }

    func testAutomatedRunsNeverSeeItAndLaterLaunchesDont() {
        XCTAssertFalse(WelcomeScreen.showsAtLaunch(defaults: defaults, environment: ["XCTestConfigurationFilePath": "/tmp/x"]))
        XCTAssertFalse(WelcomeScreen.showsAtLaunch(defaults: defaults, environment: [:]), "the system relaunching a test's app")

        let uiTest = UserDefaults(suiteName: "\(suiteName!)-ui")!
        defer { uiTest.removePersistentDomain(forName: "\(suiteName!)-ui") }
        uiTest.set(UUID().uuidString, forKey: "UITestLibrary")
        XCTAssertFalse(WelcomeScreen.showsAtLaunch(defaults: uiTest, environment: [:]))
    }
}

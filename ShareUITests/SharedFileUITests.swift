import XCTest

@MainActor
final class SharedFileUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.thisjustin816.PressAny")
    private let sender = XCUIApplication(bundleIdentifier: "com.thisjustin816.ShareTestSender")
    private let baseROM = "gbdk450-rev-v1.0.gb"
    private let colorROM = "gbdk450-dual.gbc"
    private let gameTitle = "Shared Test Game"

    private func start() {
        continueAfterFailure = false
        app.launchArguments = ["-UITestLibrary", UUID().uuidString]
        app.launch()
        XCTAssertTrue(app.staticTexts["No Games"].waitForExistence(timeout: 15))
        sender.launch()
    }

    func testSharedGBReviewCancellationAndImport() {
        start()
        share(baseROM)
        expect(app.navigationBars["Open ROM"])
        expect(app.staticTexts[baseROM])
        app.buttons["Import to Library"].tap()
        expect(app.navigationBars["Import Review"])
        app.buttons["Cancel"].tap()
        expect(app.staticTexts["No Games"])

        importBaseROM()
        openGameDetails()
        expect(app.staticTexts["Original"])
    }

    func testSharedGBCQuickPlayQueuesROMUntilSessionCloses() {
        start()
        share(colorROM)
        expect(app.navigationBars["Open ROM"])
        app.buttons["Quick Play"].tap()
        expect(app.buttons["Game Menu"])

        share(baseROM)
        expect(app.buttons["Game Menu"])
        XCTAssertFalse(app.navigationBars["Open ROM"].exists, "sharing must not replace active gameplay")
        closeGameplay()
        expect(app.buttons["Keep for Later"])
        XCTAssertFalse(app.navigationBars["Open ROM"].exists, "the queued ROM waits for the session sheet too")
        app.buttons["Keep for Later"].tap()
        expect(app.navigationBars["Open ROM"])
        expect(app.staticTexts[baseROM])
        app.buttons["Cancel"].tap()
        expect(app.staticTexts["No Games"])
    }

    func testSharedIPSRefreshesOpenGameDetails() {
        start()
        importBaseROM()
        openGameDetails()
        sharePatchAndApply("ips", name: "Shared IPS Build")
        expect(app.navigationBars[gameTitle])
        expect(app.staticTexts["Shared IPS Build"], message: "the new Build appears without leaving Game Details")
        expect(app.staticTexts["Original"])
        expect(app.staticTexts["Patched from Original"])
    }

    func testSharedBPSRefreshesOpenGameDetails() {
        start()
        importBaseROM()
        openGameDetails()
        sharePatchAndApply("bps", name: "Shared BPS Build")
        expect(app.navigationBars[gameTitle])
        expect(app.staticTexts["Shared BPS Build"], message: "the new Build appears without leaving Game Details")
        expect(app.staticTexts["Original"])
    }

    func testPatchWaitsForLibraryGameplayToClose() {
        start()
        importBaseROM()
        openGameDetails()
        app.buttons["Play"].firstMatch.tap()
        expect(app.buttons["Game Menu"])
        share("gbdk450-rev-v1.0-to-v1.1.ips")
        expect(app.buttons["Game Menu"])
        XCTAssertFalse(app.navigationBars["Open Patch"].exists)
        closeGameplay()
        expect(app.navigationBars["Open Patch"])
        applyPatch(name: "Queued Patch Build")
        expect(app.navigationBars[gameTitle])
        expect(app.staticTexts["Queued Patch Build"])
    }

    func testSharedPatchCancellationKeepsOriginalBuild() {
        start()
        importBaseROM()
        openGameDetails()
        share("gbdk450-rev-v1.0-to-v1.1.bps")
        expect(app.navigationBars["Open Patch"])
        XCTAssertFalse(app.buttons["Apply Patch"].isEnabled, "a base must be selected explicitly")
        app.buttons["Cancel"].tap()
        expect(app.navigationBars[gameTitle])
        expect(app.staticTexts["Original"])
        XCTAssertFalse(app.staticTexts["gbdk450-rev-v1.0-to-v1.1"].exists)
    }

    private func sharePatchAndApply(_ suffix: String, name: String) {
        share("gbdk450-rev-v1.0-to-v1.1.\(suffix)")
        expect(app.navigationBars["Open Patch"])
        applyPatch(name: name)
    }

    private func applyPatch(name: String) {
        app.buttons["Game"].tap()
        app.buttons[gameTitle].firstMatch.tap()
        app.buttons["Base Build"].tap()
        app.buttons["Original"].firstMatch.tap()
        replace(app.textFields["New Build name"], with: name)
        app.buttons["Apply Patch"].tap()
        expect(app.alerts["Build Created"])
        app.alerts.buttons["Done"].tap()
    }

    private func importBaseROM() {
        share(baseROM)
        expect(app.navigationBars["Open ROM"])
        app.buttons["Import to Library"].tap()
        expect(app.navigationBars["Import Review"])
        replace(app.textFields["Game Title"], with: gameTitle)
        app.navigationBars.buttons["Import"].tap()
        expect(app.buttons[gameTitle])
    }

    private func openGameDetails() {
        app.buttons[gameTitle].tap()
        expect(app.navigationBars[gameTitle])
        expect(app.staticTexts["Original"])
    }

    private func closeGameplay() {
        app.buttons["Game Menu"].tap()
        expect(app.buttons["Close Game"])
        app.buttons["Close Game"].tap()
    }

    private func share(_ filename: String) {
        sender.activate()
        let fixture = sender.buttons[filename]
        expect(fixture)
        fixture.tap()
        let recipient = sender.descendants(matching: .any).matching(NSPredicate(
            format: "label IN %@", ["Press Any", "Open in Press Any", "Copy to Press Any"]
        )).firstMatch
        if !recipient.waitForExistence(timeout: 5) {
            let more = sender.buttons.matching(NSPredicate(format: "label BEGINSWITH 'More'")).firstMatch
            expect(more, message: "the system share sheet offers more destinations")
            more.tap()
        }
        expect(recipient, message: "Press Any is a system share destination for \(filename)")
        recipient.tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "iOS hands the file to Press Any")
    }

    private func replace(_ field: XCUIElement, with value: String) {
        expect(field)
        field.tap()
        let previous = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + value + "\n")
    }

    private func expect(_ element: XCUIElement, message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        let exists = element.waitForExistence(timeout: 10)
        if !exists {
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertTrue(exists, message.isEmpty ? "Expected \(element)" : message, file: file, line: line)
    }
}

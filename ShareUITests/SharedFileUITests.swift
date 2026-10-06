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
        expect(app.navigationBars["Open ROM"], timeout: 45)
        expect(app.staticTexts[baseROM])
        app.buttons["Import to Library"].tap()
        expect(app.navigationBars["Import Review"])
        app.buttons["Cancel"].tap()
        expect(app.staticTexts["No Games"])

        importBaseROM()
        openGameDetails()
        expect(app.staticTexts["Original"])
    }

    func testSharedROMOpensOverQuickPlayAndPausesIt() {
        start()
        share(colorROM)
        expect(app.navigationBars["Open ROM"], timeout: 45)
        app.buttons["Quick Play"].tap()
        expect(app.buttons["Game Menu"])

        app.buttons["Game Menu"].tap()
        expect(app.buttons["Resume"], message: "opening the game menu pauses the game")
        XCTAssertFalse(app.buttons["Pause"].exists)
        app.buttons["Resume"].tap()
        expect(app.buttons["Game Menu"])

        share(baseROM)
        expect(app.navigationBars["Open ROM"], message: "a file shared mid-game opens over the game", timeout: 45)
        expect(app.staticTexts[baseROM])
        app.buttons["Cancel"].tap()
        expect(app.buttons["Resume Game"], message: "the game stays paused after the shared file closes")

        share(baseROM)
        expect(app.navigationBars["Open ROM"], timeout: 45)
        app.buttons["Close Game and Quick Play"].tap()
        expect(app.buttons["Keep for Later"], message: "the running Quick Play closes the normal way first")
        app.buttons["Keep for Later"].tap()
        expect(app.buttons["Game Menu"], message: "the shared ROM starts once the earlier game has closed")
        closeGameplay()
        expect(app.buttons["Keep for Later"])
        app.buttons["Keep for Later"].tap()
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

    func testSharedPatchOpensOverLibraryGameplay() {
        start()
        importBaseROM()
        openGameDetails()
        app.buttons["game.play"].tap()
        expect(app.buttons["Game Menu"])
        share("gbdk450-rev-v1.0-to-v1.1.ips")
        expect(app.navigationBars["Open Patch"], message: "a patch shared mid-game opens over the game", timeout: 45)
        applyPatch(name: "Mid-Game Patch Build")
        expect(app.buttons["Resume Game"], message: "the game stays paused after the patch is applied")
        closeGameplay()
        expect(app.navigationBars[gameTitle])
        expect(app.staticTexts["Mid-Game Patch Build"])
    }

    func testSharedPatchCancellationKeepsOriginalBuild() {
        start()
        importBaseROM()
        openGameDetails()
        share("gbdk450-rev-v1.0-to-v1.1.bps")
        expect(app.navigationBars["Open Patch"], timeout: 45)
        XCTAssertFalse(app.buttons["Apply Patch"].isEnabled, "a base must be selected explicitly")
        app.buttons["Cancel"].tap()
        expect(app.navigationBars[gameTitle])
        expect(app.staticTexts["Original"])
        XCTAssertFalse(app.staticTexts["gbdk450-rev-v1.0-to-v1.1"].exists)
    }

    private func sharePatchAndApply(_ suffix: String, name: String) {
        share("gbdk450-rev-v1.0-to-v1.1.\(suffix)")
        expect(app.navigationBars["Open Patch"], timeout: 45)
        applyPatch(name: name)
    }

    private func applyPatch(name: String) {
        app.buttons["sharedPatch.gamePicker"].tap()
        app.buttons[gameTitle].firstMatch.tap()
        app.buttons["sharedPatch.baseBuildPicker"].tap()
        app.buttons["Original"].firstMatch.tap()
        replace(app.textFields["New Build name"], with: name)
        app.buttons["Apply Patch"].tap()
        expect(app.alerts["Build Created"])
        app.alerts.buttons["Done"].tap()
    }

    private func importBaseROM() {
        share(baseROM)
        expect(app.navigationBars["Open ROM"], timeout: 45)
        app.buttons["Import to Library"].tap()
        expect(app.navigationBars["Import Review"])
        replace(app.textFields["Game Title"], with: gameTitle)
        app.navigationBars.buttons["Import"].tap()
        expect(gameTile)
    }

    private func openGameDetails() {
        gameTile.tap()
        expect(app.navigationBars[gameTitle])
        expect(app.staticTexts["Original"])
    }

    private func closeGameplay() {
        app.buttons["Game Menu"].tap()
        expect(app.buttons["Close Game"])
        app.buttons["Close Game"].tap()
    }

    private var gameTile: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", gameTitle)).firstMatch
    }

    private func share(_ filename: String) {
        sender.activate()
        let fixture = sender.buttons[filename]
        expect(fixture)
        fixture.tap()
        let recipient = sender.descendants(matching: .any).matching(NSPredicate(
            format: "label IN %@", ["Press Any", "Open in Press Any", "Copy to Press Any"]
        )).firstMatch
        if !recipient.waitForExistence(timeout: 30) {
            let more = sender.descendants(matching: .any)
                .matching(NSPredicate(format: "label BEGINSWITH 'More'")).firstMatch
            expect(more, message: "the system share sheet offers more destinations", timeout: 30)
            if !recipient.exists { more.tap() }
        }
        expect(recipient, message: "Press Any is a system share destination for \(filename)", timeout: 30)
        recipient.tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "iOS hands the file to Press Any")
    }

    private func replace(_ field: XCUIElement, with value: String) {
        expect(field)
        // The edit menu doesn't appear for trailing-aligned fields inside LabeledContent, so clear
        // with the keyboard. Tapping the trailing edge puts the caret after the text in either alignment.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        let existing = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count) + value + "\n")
        XCTAssertEqual(field.value as? String, value, "the edited name replaces the whole previous value")
    }

    private func expect(_ element: XCUIElement, message: String = "", timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let exists = element.waitForExistence(timeout: timeout)
        if !exists {
            print(app.debugDescription)
            print(sender.debugDescription)
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertTrue(exists, message.isEmpty ? "Expected \(element)" : message, file: file, line: line)
    }
}

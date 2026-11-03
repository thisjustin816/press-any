import XCTest

/// Without Plus, every Gameplay preset is free, and changing a preset setting by hand opens the
/// Plus screen and saves nothing.
@MainActor
final class GameplayPresetUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.thisjustin816.PressAny")

    func testALockedCustomEditOpensPlusAndChangesNothing() {
        continueAfterFailure = false
        app.launchArguments = ["-UITestLibrary", UUID().uuidString]
        app.launch()
        expect(app.staticTexts["No Games"], timeout: 15)

        app.buttons["Settings"].firstMatch.tap()
        expect(app.navigationBars["Settings"])
        app.buttons["Game Boy Color"].firstMatch.tap()
        expect(app.navigationBars["Game Boy Color Settings"])

        let preset = app.descendants(matching: .any)["Gameplay Preset"].firstMatch
        expect(preset)
        XCTAssertTrue(presetValue(preset).hasPrefix("Nostalgic"), "an untouched system shows the standard preset, not Custom")

        app.buttons["Customize"].firstMatch.tap()
        expect(app.navigationBars["Customize"])
        let blending = app.descendants(matching: .any)["Frame Blending"].firstMatch
        expect(blending)
        let before = blending.value as? String ?? ""
        XCTAssertTrue(before.hasPrefix("Blend"), "the standard preset blends frames, not \(before)")

        blending.tap()
        let ghosting = app.buttons["LCD Ghosting (Plus)"].firstMatch
        expect(ghosting, message: "a preset setting is marked Plus")
        ghosting.tap()
        expect(app.navigationBars["Press Any Plus"], message: "the locked edit opens the Plus screen")
        app.navigationBars["Press Any Plus"].buttons["Done"].tap()

        expect(app.navigationBars["Customize"])
        XCTAssertEqual(blending.value as? String, before, "nothing was saved")
        app.navigationBars["Customize"].buttons.firstMatch.tap()
        expect(app.navigationBars["Game Boy Color Settings"])
        XCTAssertTrue(presetValue(preset).hasPrefix("Nostalgic"), "the preset is unchanged")

        // Choosing another preset is free and needs no Plus screen.
        preset.tap()
        app.buttons["Accurate"].firstMatch.tap()
        XCTAssertFalse(app.navigationBars["Press Any Plus"].waitForExistence(timeout: 2))
        XCTAssertTrue(presetValue(preset).hasPrefix("Accurate"))
    }

    private func presetValue(_ element: XCUIElement) -> String {
        element.value as? String ?? ""
    }

    private func expect(_ element: XCUIElement, message: String = "", timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let exists = element.waitForExistence(timeout: timeout)
        if !exists {
            print(app.debugDescription)
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertTrue(exists, message.isEmpty ? "Expected \(element)" : message, file: file, line: line)
    }
}

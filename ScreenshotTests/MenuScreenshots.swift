import XCTest

/// Opens the app's pop-up menus, which only a tap can open, and saves a screenshot of each for
/// `Scripts/take-screenshots.sh`, which runs these through the PressAnyScreenshots scheme. The
/// script passes `SCREENSHOT_ROMS` (the fixture folder the app seeds its library from),
/// `SCREENSHOT_OUTPUT`, `SCREENSHOT_GAME_ROM` and `SCREENSHOT_PLAY_ROM`; without them the tests skip.
/// Each test fails when its menu doesn't open, after saving what the screen showed instead.
@MainActor
final class MenuScreenshots: XCTestCase {
    private struct Settings {
        let roms: String
        let output: URL
        let gameROM: String
        let playROM: String
    }

    func test1AddMenu() throws {
        let app = try launch("library")
        app.buttons["library.addMenu"].tap()
        try expect(app.buttons["Import ROM"], then: "menu-add")
    }

    func test2LibraryViewMenu() throws {
        let app = try launch("library")
        app.buttons["library.viewMenu"].tap()
        try expect(app.buttons["List"], then: "menu-library-view")
    }

    func test3GameMenu() throws {
        let settings = try settings()
        let app = try launch("game:\(settings.gameROM)")
        app.buttons["game.moreMenu"].tap()
        try expect(app.buttons["Game Settings…"], then: "menu-game")
    }

    func test4BuildMenu() throws {
        let settings = try settings()
        let app = try launch("game:\(settings.gameROM)")
        app.staticTexts["Original"].firstMatch.press(forDuration: 1)
        try expect(app.buttons["Technical Info…"], then: "menu-build")
    }

    func test5SaveProfileMenu() throws {
        let settings = try settings()
        let app = try launch("game:\(settings.gameROM)")
        // A seeded Game has no profile until one is played or made, so make one.
        let newSave = app.buttons["New Blank Save"]
        scrollTo(newSave, in: app)
        newSave.tap()
        let create = app.alerts.buttons["Create"]
        XCTAssertTrue(create.waitForExistence(timeout: 5), "the New Save Profile alert opens")
        create.tap()
        let profile = app.staticTexts["New Save"]
        XCTAssertTrue(profile.waitForExistence(timeout: 5), "the new profile is listed")
        scrollTo(profile, in: app)
        profile.press(forDuration: 1)
        try expect(app.buttons["Duplicate"], then: "menu-save-profile")
    }

    func test6GameplayMenu() throws {
        try openGameplayMenu(then: "menu-gameplay")
    }

    func test7GameplayMenuWithController() throws {
        try openGameplayMenu(arguments: ["-ScreenshotGamepad", "YES"], then: "menu-gameplay-gamepad")
    }

    func test8QuickPlayMenu() throws {
        try openGameplayMenu(scene: "quick-play", expecting: "Add to Library…", then: "menu-quick-play")
    }

    /// Taps the logo, which opens the same menu with or without a controller connected.
    private func openGameplayMenu(
        scene: String = "play",
        arguments: [String] = [],
        expecting item: String = "Close Game",
        then name: String
    ) throws {
        let settings = try settings()
        let app = try launch("\(scene):\(settings.playROM)", arguments: arguments)
        let menu = app.buttons["Game Menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "the logo is a menu button")
        // Past the boot logo, so the menu opens over the game's own picture.
        sleep(4)
        menu.tap()
        try expect(app.buttons[item], then: name)
    }

    /// At large text sizes the save profiles start below the screen, and the list doesn't create
    /// a row until it scrolls into view, so the row may not exist until after a swipe.
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        _ = element.waitForExistence(timeout: 5)
        for _ in 0..<6 where !(element.exists && element.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, "\(element) is on screen")
    }

    private func settings() throws -> Settings {
        let environment = ProcessInfo.processInfo.environment
        guard let roms = environment["SCREENSHOT_ROMS"],
              let output = environment["SCREENSHOT_OUTPUT"],
              let gameROM = environment["SCREENSHOT_GAME_ROM"],
              let playROM = environment["SCREENSHOT_PLAY_ROM"] else {
            throw XCTSkip("Run by Scripts/take-screenshots.sh, which sets the SCREENSHOT_ variables.")
        }
        return Settings(roms: roms, output: URL(fileURLWithPath: output, isDirectory: true), gameROM: gameROM, playROM: playROM)
    }

    private func launch(_ scene: String, arguments: [String] = []) throws -> XCUIApplication {
        let settings = try settings()
        let app = XCUIApplication()
        app.launchArguments = ["-ScreenshotScene", scene, "-ScreenshotROMs", settings.roms] + arguments
        app.launch()
        return app
    }

    /// Waits for an item of the menu just opened, then saves the screen as `<name>.png`.
    private func expect(_ item: XCUIElement, then name: String) throws {
        let opened = item.waitForExistence(timeout: 5)
        let output = try settings().output
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: output.appendingPathComponent("\(name).png"))
        XCTAssertTrue(opened, "\(name) opens")
    }
}

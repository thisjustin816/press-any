import UIKit
import XCTest

/// Opens the app's pop-up menus, which only a tap can open, and saves a screenshot of each for
/// `Scripts/take-screenshots.sh`, which runs these through the PressAnyScreenshots scheme. The
/// script passes `SCREENSHOT_ROMS` (the fixture folder the app seeds its library from),
/// `SCREENSHOT_OUTPUT`, `SCREENSHOT_GAME_ROM` and `SCREENSHOT_PLAY_ROM`; without them the tests skip.
/// It can also pass `SCREENSHOT_INPUT`, a button script the landscape gameplay shots play before
/// their wait, and `SCREENSHOT_WAITS`, those waits in seconds as `<shot>=<seconds>` pairs.
/// Each test fails when its menu doesn't open, after saving what the screen showed instead.
@MainActor
final class MenuScreenshots: XCTestCase {
    private struct Settings {
        let roms: String
        let output: URL
        let gameROM: String
        let playROM: String
        let input: String?
        let waits: [String: Double]

        /// The launch arguments that play the button script, if there is one.
        var inputArguments: [String] {
            input.map { ["-ScreenshotInput", $0] } ?? []
        }
    }

    func test1AddMenu() throws {
        let app = try launch("library")
        app.buttons["library.addMenu"].tap()
        try expect(app.buttons["Import Files…"], then: "menu-add")
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
        try expect(app.buttons["Game Settings"], then: "menu-game")
    }

    func test4BuildMenu() throws {
        let settings = try settings()
        let app = try launch("game:\(settings.gameROM)")
        app.staticTexts["Original"].firstMatch.press(forDuration: 1)
        try expect(app.buttons["Build Info"], then: "menu-build")
    }

    func test5SaveProfileMenu() throws {
        let settings = try settings()
        let app = try launch("game:\(settings.gameROM)")
        // A seeded Game has no profile until one is played or made, so make one.
        let newSave = app.buttons["New Blank Save…"]
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

    func test9LandscapeGameplayAndClosingReturnsToPortrait() throws {
        defer { XCUIDevice.shared.orientation = .portrait }
        let settings = try settings()
        let app = try launch("play:\(settings.playROM)", arguments: settings.inputArguments)
        let menu = app.buttons["Game Menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForOrientation(in: app, landscape: true)
        try waitForPlay(menu, before: "play-landscape")
        try expect(menu, then: "play-landscape")
        menu.tap()
        let resume = app.buttons["Resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        try expect(app.buttons["Close Game"], then: "menu-gameplay-landscape")
        app.buttons["Close Game"].tap()
        XCTAssertTrue(app.buttons["library.addMenu"].waitForExistence(timeout: 10))
        waitForOrientation(in: app, landscape: false)
    }

    func testLandscapeQuickPlayWithController() throws {
        defer { XCUIDevice.shared.orientation = .portrait }
        let settings = try settings()
        let app = try launch(
            "quick-play:\(settings.playROM)", arguments: ["-ScreenshotGamepad", "YES"] + settings.inputArguments
        )
        let menu = app.buttons["Game Menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = .landscapeRight
        waitForOrientation(in: app, landscape: true)
        try waitForPlay(menu, before: "play-landscape-gamepad")
        try expect(menu, then: "play-landscape-gamepad")
        menu.tap()
        try expect(app.buttons["Add to Library…"], then: "menu-quick-play-landscape")
    }

    func testPlaytilesStaysPortrait() throws {
        defer { XCUIDevice.shared.orientation = .portrait }
        let settings = try settings()
        let app = try launch("play:\(settings.playROM)", arguments: ["-ScreenshotLayout", "playtiles"])
        XCTAssertTrue(app.buttons["Game Menu"].waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        XCTAssertLessThan(app.frame.width, app.frame.height)
    }

    func testSettingsOverLandscapeGameplayStaysPortrait() throws {
        defer { XCUIDevice.shared.orientation = .portrait }
        let settings = try settings()
        let app = try launch("play:\(settings.playROM)")
        let menu = app.buttons["Game Menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForOrientation(in: app, landscape: true)
        menu.tap()
        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()
        waitForOrientation(in: app, landscape: false)
        try expect(app.navigationBars["Game Settings"], then: "settings-over-game-portrait")
    }

    private func waitForOrientation(in app: XCUIApplication, landscape: Bool) {
        let deadline = Date().addingTimeInterval(10)
        while (app.frame.width > app.frame.height) != landscape, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertEqual(app.frame.width > app.frame.height, landscape)
    }

    /// Lets gameplay get past the boot logo or, with a button script, waits until the app reports
    /// the script played (in the menu button's accessibility value, as `ScreenshotScene.readyMessage`
    /// spells it) and then for the shot's wait, so the shot shows the game being played.
    private func waitForPlay(_ menu: XCUIElement, before shot: String) throws {
        let settings = try settings()
        guard settings.input != nil else {
            sleep(4)
            return
        }
        let played = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Screenshot scene ready"), object: menu
        )
        XCTAssertEqual(XCTWaiter().wait(for: [played], timeout: 180), .completed, "the button script plays")
        Thread.sleep(forTimeInterval: settings.waits[shot] ?? 1)
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
        XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 10), "opening the game menu pauses the game")
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
        var waits: [String: Double] = [:]
        for pair in (environment["SCREENSHOT_WAITS"] ?? "").split(separator: " ") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2, let seconds = Double(parts[1]) { waits[String(parts[0])] = seconds }
        }
        let input = environment["SCREENSHOT_INPUT"].flatMap { $0.isEmpty ? nil : $0 }
        return Settings(
            roms: roms, output: URL(fileURLWithPath: output, isDirectory: true), gameROM: gameROM, playROM: playROM,
            input: input, waits: waits
        )
    }

    private func launch(_ scene: String, arguments: [String] = []) throws -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
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
        try upright(XCUIScreen.main.screenshot()).write(to: output.appendingPathComponent("\(name).png"))
        XCTAssertTrue(opened, "\(name) opens")
    }

    /// XCTest captures a landscape screen as the portrait display holds it, on its side. App Store
    /// Connect takes a landscape screenshot as a landscape image, so this turns it upright: a
    /// quarter turn counterclockwise when the device's right side is up (landscape left), clockwise
    /// when its left side is.
    private func upright(_ screenshot: XCUIScreenshot) -> Data {
        let turn: CGFloat
        switch XCUIDevice.shared.orientation {
        case .landscapeLeft: turn = .pi / 2
        case .landscapeRight: turn = -.pi / 2
        default: return screenshot.pngRepresentation
        }
        // Core Graphics' y axis points up, so a positive angle turns counterclockwise. Drawn
        // without alpha, since App Store Connect refuses screenshots with transparency.
        guard let image = screenshot.image.cgImage, image.width < image.height,
              let space = image.colorSpace?.model == .rgb ? image.colorSpace : CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: image.height, height: image.width, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else { return screenshot.pngRepresentation }
        context.translateBy(x: turn > 0 ? CGFloat(image.height) : 0, y: turn > 0 ? 0 : CGFloat(image.width))
        context.rotate(by: turn)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let rotated = context.makeImage(), let png = UIImage(cgImage: rotated).pngData() else {
            return screenshot.pngRepresentation
        }
        return png
    }
}

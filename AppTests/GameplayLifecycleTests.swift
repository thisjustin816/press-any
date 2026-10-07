import EmulationCore
import EmulatorDomain
import GameplayInput
import UIKit
import XCTest
@testable import PressAny

/// The game pauses whenever its scene isn't active, and a trip to the background brings it back
/// only as Resume Games says.
@MainActor
final class GameplayLifecycleTests: XCTestCase {
    private func makeGameplay(
        policy: AutoResumePolicy = .always
    ) -> (GameplayViewController, LifecycleRuntime, PhysicalControllerMonitor) {
        let runtime = LifecycleRuntime()
        let monitor = PhysicalControllerMonitor()
        let gameplay = GameplayViewController(runtime: runtime, autoResumePolicy: policy, controllerMonitor: monitor)
        gameplay.loadViewIfNeeded()
        return (gameplay, runtime, monitor)
    }

    func testDisplaySettingsReachTheOpenGameWhileItStaysPaused() {
        let (gameplay, runtime, _) = makeGameplay()
        XCTAssertEqual(runtime.displaySettings?.correction, .balanced)
        XCTAssertEqual(runtime.displaySettings?.palette, .grey)
        gameplay.setCoveredBySheet(true)
        let frames = runtime.frames
        gameplay.applyDisplaySettings(
            controlStyle: .gameBoy, screenScaling: .integer, lcdFilter: .off,
            colorCorrection: .accurate, dmgPalette: .dmgGreen, frameBlending: .off
        )
        XCTAssertEqual(runtime.displaySettings?.correction, .accurate)
        XCTAssertEqual(runtime.displaySettings?.palette, .dmgGreen)
        gameplay.applyDisplaySettings(
            controlStyle: .gameBoy, screenScaling: .integer, lcdFilter: .off,
            colorCorrection: .off, dmgPalette: .pocket, frameBlending: .off
        )
        XCTAssertEqual(runtime.displaySettings?.correction, .off)
        XCTAssertEqual(runtime.displaySettings?.palette, .pocket)
        XCTAssertFalse(gameplay.isRunningFrames)
        XCTAssertEqual(runtime.frames, frames)
    }

    func testOnlyGameBoyGameplayAllowsBothLandscapeOrientations() {
        let gameplayMask: UIInterfaceOrientationMask = [.portrait, .landscapeLeft, .landscapeRight]
        XCTAssertEqual(GameplayOrientation.mask(style: .gameBoy, coveredBySheet: false), gameplayMask)
        XCTAssertEqual(GameplayOrientation.mask(style: .playtiles, coveredBySheet: false), .portrait)
        XCTAssertEqual(GameplayOrientation.mask(style: nil, coveredBySheet: false), .portrait, "the library")
        XCTAssertEqual(GameplayOrientation.mask(style: .gameBoy, coveredBySheet: true), .portrait)
        XCTAssertEqual(GameplayOrientation.mask(style: .gameBoy, orientation: .portrait, coveredBySheet: false), .portrait)
        XCTAssertEqual(GameplayOrientation.mask(style: .gameBoy, orientation: .landscape, coveredBySheet: false), .landscape)
        XCTAssertEqual(
            GameplayOrientation.mask(style: .playtiles, orientation: .landscape, coveredBySheet: false), .portrait,
            "Playtiles fits a portrait phone whatever the setting says"
        )
        XCTAssertEqual(
            GameplayOrientation.mask(style: .gameBoy, orientation: .landscape, coveredBySheet: true), .portrait,
            "sheets stay portrait"
        )

        defer { GameplayOrientation.update(.portrait) }
        let delegate = AppDelegate()
        for mask in [gameplayMask, .portrait] {
            GameplayOrientation.update(mask)
            XCTAssertEqual(delegate.application(.shared, supportedInterfaceOrientationsFor: nil), mask)
        }
    }

    func testGameplayControllerFollowsLayoutAndSheetOrientationRestrictions() {
        let (gameplay, _, _) = makeGameplay()
        XCTAssertTrue(gameplay.supportedInterfaceOrientations.contains(.landscapeLeft))
        XCTAssertTrue(gameplay.supportedInterfaceOrientations.contains(.landscapeRight))
        gameplay.setCoveredBySheet(true)
        XCTAssertEqual(gameplay.supportedInterfaceOrientations, .portrait)
        gameplay.setCoveredBySheet(false)
        gameplay.applyDisplaySettings(controlStyle: .gameBoy, orientation: .landscape, screenScaling: .integer, lcdFilter: .off, frameBlending: .off)
        XCTAssertEqual(gameplay.supportedInterfaceOrientations, .landscape, "Orientation set to Landscape applies at once")
        gameplay.applyDisplaySettings(controlStyle: .gameBoy, orientation: .portrait, screenScaling: .integer, lcdFilter: .off, frameBlending: .off)
        XCTAssertEqual(gameplay.supportedInterfaceOrientations, .portrait)
        gameplay.applyDisplaySettings(controlStyle: .playtiles, screenScaling: .integer, lcdFilter: .off, frameBlending: .off)
        XCTAssertEqual(gameplay.supportedInterfaceOrientations, .portrait)
    }

    func testResizingKeepsRunningOrPausedAndCentersResumeOnTheNewPicture() {
        let (gameplay, runtime, _) = makeGameplay()
        for paused in [false, true] {
            if paused { _ = gameplay.prepareGameMenu() }
            for size in [CGSize(width: 393, height: 852), CGSize(width: 852, height: 393)] {
                gameplay.view.frame = CGRect(origin: .zero, size: size)
                gameplay.view.setNeedsLayout()
                gameplay.view.layoutIfNeeded()
                gameplay.view.layoutIfNeeded()
                XCTAssertEqual(gameplay.isRunningFrames, !paused)
                XCTAssertEqual(gameplay.isShowingPaused, paused)
                let picture = gameplay.gamePictureFrame
                let overlay = gameplay.pausedOverlayFrame
                XCTAssertEqual(overlay.midX, picture.midX, accuracy: 0.5)
                XCTAssertEqual(overlay.midY, picture.midY, accuracy: 0.5)
                XCTAssertTrue(picture.contains(overlay))
            }
        }
        XCTAssertFalse(runtime.failedFrame)
    }

    func testResizingTouchControlsPublishesReleasedInput() {
        let controls = TouchControllerView(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        var published: [EmulatorInputState] = []
        controls.onInputChanged = { published.append($0) }
        controls.layoutIfNeeded()
        published.removeAll()
        controls.frame.size = CGSize(width: 852, height: 393)
        controls.setNeedsLayout()
        controls.layoutIfNeeded()
        XCTAssertEqual(published, [EmulatorInputState()])
    }

    func testAnOverlayPausesTheGameAndItPicksUpAfterward() {
        let (gameplay, runtime, _) = makeGameplay(policy: .never)
        XCTAssertTrue(gameplay.isRunningFrames)

        gameplay.sceneWillDeactivate()
        XCTAssertFalse(gameplay.isRunningFrames, "Control Center covers the game")
        XCTAssertFalse(gameplay.isShowingPaused, "nothing for the player to tap")

        gameplay.sceneDidActivate()
        XCTAssertTrue(gameplay.isRunningFrames, "an overlay isn't leaving the app, so even Never resumes")
        XCTAssertEqual(runtime.foregrounds, 0)
        XCTAssertFalse(runtime.failedFrame)
    }

    func testAfterTheBackgroundAlwaysResumesOnlyOnceActive() {
        let (gameplay, runtime, _) = makeGameplay(policy: .always)
        gameplay.sceneWillDeactivate()
        gameplay.sceneDidEnterBackground()
        XCTAssertEqual(runtime.backgrounds, 1, "saved on the way out")
        XCTAssertFalse(gameplay.isRunningFrames)

        gameplay.sceneDidActivate()
        XCTAssertEqual(runtime.foregrounds, 1)
        XCTAssertTrue(gameplay.isRunningFrames)
        XCTAssertFalse(runtime.failedFrame, "no frame ran while the session was paused")
    }

    func testNeverStaysPausedUntilThePlayerResumes() {
        let (gameplay, runtime, _) = makeGameplay(policy: .never)
        gameplay.sceneWillDeactivate()
        gameplay.sceneDidEnterBackground()
        gameplay.sceneDidActivate()

        XCTAssertFalse(gameplay.isRunningFrames)
        XCTAssertTrue(gameplay.isShowingPaused)
        gameplay.sceneWillDeactivate()
        gameplay.sceneDidActivate()
        XCTAssertFalse(gameplay.isRunningFrames, "a later overlay doesn't resume it either")
        XCTAssertFalse(runtime.failedFrame)
    }

    func testRepeatedNotificationsDoTheWorkOnce() {
        let (gameplay, runtime, _) = makeGameplay(policy: .always)
        gameplay.sceneWillDeactivate()
        gameplay.sceneWillDeactivate()
        gameplay.sceneDidEnterBackground()
        gameplay.sceneDidEnterBackground()
        XCTAssertEqual(runtime.backgrounds, 1)
        gameplay.sceneDidActivate()
        gameplay.sceneDidActivate()
        XCTAssertEqual(runtime.foregrounds, 1)
        XCTAssertTrue(gameplay.isRunningFrames)
    }

    func testAGamePausedByThePlayerStaysPausedThroughEveryInterruption() {
        let (gameplay, runtime, monitor) = makeGameplay(policy: .always)
        monitor.onUnexpectedDisconnect?()
        XCTAssertFalse(gameplay.isRunningFrames)

        gameplay.sceneWillDeactivate()
        gameplay.sceneDidActivate()
        XCTAssertFalse(gameplay.isRunningFrames)
        gameplay.sceneWillDeactivate()
        gameplay.sceneDidEnterBackground()
        gameplay.sceneDidActivate()
        XCTAssertFalse(gameplay.isRunningFrames)
        XCTAssertTrue(gameplay.isShowingPaused)
        XCTAssertEqual(runtime.foregrounds, 0, "Resume Games doesn't apply to a game the player paused")
        XCTAssertFalse(runtime.failedFrame)
    }

    func testDeactivatingLetsGoOfHeldButtons() {
        let (gameplay, _, monitor) = makeGameplay()
        monitor.onInputChanged?(EmulatorInputState(a: true, start: true))
        XCTAssertTrue(gameplay.heldInput.a)

        gameplay.sceneWillDeactivate()
        XCTAssertEqual(gameplay.heldInput, EmulatorInputState())
    }

    func testOpeningGameMenuStopsFramesAndReleasesHeldButtons() {
        let (gameplay, runtime, monitor) = makeGameplay()
        let deadline = Date().addingTimeInterval(2)
        while runtime.frames == 0, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertGreaterThan(runtime.frames, 0, "the test starts with a running game")
        monitor.onInputChanged?(EmulatorInputState(a: true, start: true))

        let items = gameplay.prepareGameMenu()
        XCTAssertFalse(gameplay.isRunningFrames)
        XCTAssertTrue(gameplay.isShowingPaused)
        XCTAssertEqual(gameplay.heldInput, EmulatorInputState())
        XCTAssertTrue(items.contains { ($0 as? UIAction)?.title == "Resume" })
        XCTAssertFalse(items.contains { ($0 as? UIAction)?.title == "Pause" })
        let frozen = runtime.frames
        RunLoop.current.run(until: Date().addingTimeInterval(0.06))
        XCTAssertEqual(runtime.frames, frozen, "the game does not advance behind its menu")
        XCTAssertFalse(runtime.failedFrame)
    }

    func testMenuSettingsOpenOverThePausedGameAndApplyLive() throws {
        let (gameplay, runtime, _) = makeGameplay()
        XCTAssertFalse(
            gameplay.prepareGameMenu().contains { ($0 as? UIAction)?.title == "Settings…" },
            "without a place to save settings the menu leaves them out"
        )
        var opened = 0
        gameplay.onOpenSettings = { opened += 1 }
        let settings = try XCTUnwrap(gameplay.prepareGameMenu().compactMap { $0 as? UIAction }.first { $0.title == "Settings…" })
        let button = UIButton(type: .system)
        button.addAction(settings, for: .touchUpInside)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(opened, 1)

        gameplay.setCoveredBySheet(true)
        gameplay.applyDisplaySettings(controlStyle: .playtiles, screenScaling: .fill, lcdFilter: .lcd1x, frameBlending: .blend)
        XCTAssertEqual(gameplay.touchControlStyle, .playtiles)
        let frozen = runtime.frames
        RunLoop.current.run(until: Date().addingTimeInterval(0.06))
        XCTAssertEqual(runtime.frames, frozen, "changing settings leaves the game paused")
        gameplay.setCoveredBySheet(false)
        XCTAssertFalse(gameplay.isRunningFrames, "the player resumes when ready")
        XCTAssertTrue(gameplay.isShowingPaused)
    }

    func testResumeSitsOnTheGamePictureOnBothLayouts() {
        for style in [TouchControlStyle.gameBoy, .playtiles] {
            let (gameplay, _, _) = makeGameplay(policy: .never)
            gameplay.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
            gameplay.applyDisplaySettings(controlStyle: style, screenScaling: .integer, lcdFilter: .off, frameBlending: .off)
            // The first pass lays out the controls, whose new layout moves the overlay.
            gameplay.view.layoutIfNeeded()
            gameplay.view.layoutIfNeeded()

            let picture = gameplay.gamePictureFrame
            let overlay = gameplay.pausedOverlayFrame
            XCTAssertGreaterThan(picture.width, 0, "\(style)")
            XCTAssertEqual(overlay.midX, picture.midX, accuracy: 0.5, "\(style)")
            XCTAssertEqual(overlay.midY, picture.midY, accuracy: 0.5, "\(style)")
            XCTAssertTrue(picture.contains(overlay), "\(style): Resume stays clear of the controls")
        }
    }

    func testMenuPauseSurvivesSceneChangesUntilResume() throws {
        let (gameplay, runtime, _) = makeGameplay(policy: .always)
        let items = gameplay.prepareGameMenu()
        gameplay.sceneWillDeactivate()
        gameplay.sceneDidActivate()
        gameplay.sceneWillDeactivate()
        gameplay.sceneDidEnterBackground()
        gameplay.sceneDidActivate()
        XCTAssertFalse(gameplay.isRunningFrames)
        XCTAssertTrue(gameplay.isShowingPaused)
        XCTAssertEqual(runtime.foregrounds, 0)

        let resume = try XCTUnwrap(items.compactMap { $0 as? UIAction }.first { $0.title == "Resume" })
        let button = UIButton(type: .system)
        button.addAction(resume, for: .touchUpInside)
        let frozen = runtime.frames
        button.sendActions(for: .touchUpInside)
        XCTAssertTrue(gameplay.isRunningFrames)
        XCTAssertFalse(gameplay.isShowingPaused)
        let deadline = Date().addingTimeInterval(2)
        while runtime.frames == frozen, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertGreaterThan(runtime.frames, frozen, "Resume advances frames again")
        XCTAssertFalse(runtime.failedFrame)
    }
}

final class GameplayPauseReasonsTests: XCTestCase {
    func testFramesRunOnlyWithNoReason() {
        var reasons = GameplayPauseReasons()
        XCTAssertTrue(reasons.shouldRun)
        reasons.inactive = true
        XCTAssertFalse(reasons.shouldRun)
        reasons.byPlayer = true
        reasons.inactive = false
        XCTAssertFalse(reasons.shouldRun, "becoming active doesn't undo the player's pause")
        XCTAssertTrue(reasons.showsPausedOverlay)
    }

    func testHoldsReleaseOnlyTheirOwn() {
        var reasons = GameplayPauseReasons()
        reasons.holds += 1
        reasons.holds += 1
        reasons.holds -= 1
        XCTAssertFalse(reasons.shouldRun, "one hold is still in place")
        XCTAssertFalse(reasons.showsPausedOverlay, "a hold is brief and needs no overlay")
        reasons.holds -= 1
        XCTAssertTrue(reasons.shouldRun)
    }
}

/// Throws on a frame while paused, as the real sessions do, and counts lifecycle calls.
private final class LifecycleRuntime: GameplayRuntime, @unchecked Sendable {
    private let lock = NSLock()
    private var paused = false
    private var backgroundCount = 0
    private var foregroundCount = 0
    private var failed = false
    private var frameCount = 0
    private var displayOptions: (correction: ColorCorrection, palette: DMGPalette)?
    var displaySettings: (correction: ColorCorrection, palette: DMGPalette)? { lock.withLock { displayOptions } }
    struct NotRunning: Error {}

    var backgrounds: Int { lock.withLock { backgroundCount } }
    var foregrounds: Int { lock.withLock { foregroundCount } }
    var failedFrame: Bool { lock.withLock { failed } }
    var frames: Int { lock.withLock { frameCount } }
    var currentFrame: EmulatorVideoFrame? { nil }
    var playtimeSeconds: Double { 0 }

    func stepFrame(input: EmulatorInputState) throws -> EmulatorVideoFrame {
        try lock.withLock {
            if paused {
                failed = true
                throw NotRunning()
            }
            frameCount += 1
        }
        return EmulatorVideoFrame(width: 160, height: 144, bgra8888: Data(count: 160 * 144 * 4), emulatedNanoseconds: 16_742_706)
    }

    func drainAudio(maxFrames: Int) throws -> [StereoSample] { [] }
    func setSpeed(_ speed: EmulationSpeed) throws {}
    func setDisplaySettings(colorCorrection: ColorCorrection, dmgPalette: DMGPalette) throws -> EmulatorVideoFrame? {
        lock.withLock { displayOptions = (colorCorrection, dmgPalette) }
        return nil
    }
    func consumeRumbleAmplitude() throws -> Double { 0 }
    func pause() throws { lock.withLock { paused = true } }
    func resume() throws { lock.withLock { paused = false } }
    func background() throws {
        lock.withLock {
            paused = true
            backgroundCount += 1
        }
    }
    func foreground(policy: AutoResumePolicy) throws -> Bool {
        lock.withLock {
            foregroundCount += 1
            if policy == .always { paused = false }
        }
        return policy == .always
    }
    func stop(createAutoState: Bool) throws {}
    func stop(createAutoState: Bool, discardUnsaved: Bool) throws {}
    func flushBatteryIfChanged() throws -> Bool { false }
}

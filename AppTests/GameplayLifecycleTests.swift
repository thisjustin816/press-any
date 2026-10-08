import EmulationCore
import EmulatorDomain
import GameplayInput
import AVFoundation
import GameController
import UIKit
import XCTest
@testable import PressAny

/// The game pauses whenever its scene isn't active, and a trip to the background brings it back
/// only as Resume Games says.
@MainActor
final class GameplayLifecycleTests: XCTestCase {
    func testSlotsMenuIsOptInAndEmptyLoadIsDisabled() throws {
        let runtime = StateMenuRuntime()
        let gameplay = GameplayViewController(runtime: runtime, autoResumePolicy: .always)
        var items = gameplay.prepareGameMenu()
        XCTAssertFalse(items.allMenus.contains { $0.title == "Slots" })
        gameplay.saveStateSlots = .three
        items = gameplay.prepareGameMenu()
        let slots = try XCTUnwrap(items.allMenus.first { $0.title == "Slots" })
        XCTAssertEqual(slots.children.map(\.title), ["Slot 1", "Slot 2", "Slot 3"])
        let empty = try XCTUnwrap(slots.children.first as? UIMenu)
        XCTAssertEqual(empty.subtitle, "Empty")
        XCTAssertFalse(try XCTUnwrap(empty.children.allActions.first { $0.title == "Save to Slot 1" }).attributes.contains(.disabled))
        XCTAssertTrue(try XCTUnwrap(empty.children.allActions.first { $0.title == "Load Slot 1" }).attributes.contains(.disabled))
        let occupied = try XCTUnwrap(slots.children[1] as? UIMenu)
        XCTAssertNotEqual(occupied.subtitle, "Empty")
        XCTAssertFalse(try XCTUnwrap(occupied.children.allActions.first { $0.title == "Load Slot 2" }).attributes.contains(.disabled))
        XCTAssertNotNil(occupied.image)
        XCTAssertFalse(items.allActions.contains { $0.title == "Slot 2" }, "a configured slot does not repeat below the submenu")
        XCTAssertTrue(items.allActions.contains { $0.title == "Slot 5" }, "slots above the count remain loadable")
        let states = try XCTUnwrap(items.allMenus.first { $0.title == "States" })
        let saves = try XCTUnwrap(states.children.first as? UIMenu)
        XCTAssertEqual(saves.children.map(\.title), ["Save New State", "Slots"])
        gameplay.saveStateSlots = .five
        XCTAssertFalse(gameplay.prepareGameMenu().allActions.contains { $0.title == "Slot 5" })
        gameplay.saveStateSlots = .off
        XCTAssertTrue(gameplay.prepareGameMenu().allActions.contains { $0.title == "Slot 2" })
        let pinned = try XCTUnwrap(gameplay.prepareGameMenu().allActions.first { $0.title == "Pinned manual" })
        XCTAssertTrue(pinned.subtitle?.hasPrefix("Pinned · ") == true)
    }

    func testQuickPlayShowsDisabledSlotsWhenEnabled() throws {
        let gameplay = GameplayViewController(runtime: LifecycleRuntime(), autoResumePolicy: .always, saveStateSlots: .three)
        let items = gameplay.prepareGameMenu()
        XCTAssertEqual(items.allMenus.first { $0.title == "States" }?.subtitle, "Add to Library to save states")
        let slots = try XCTUnwrap(items.allMenus.first { $0.title == "Slots" })
        XCTAssertEqual(slots.children.count, 3)
        XCTAssertEqual(slots.children.allActions.count, 6)
        XCTAssertTrue(slots.children.allActions.allSatisfy { $0.attributes.contains(.disabled) })
    }

    func testGameMenuOffersRestartBesideCloseGame() throws {
        let (gameplay, _, _) = makeGameplay()
        let group = try XCTUnwrap(gameplay.prepareGameMenu().last as? UIMenu)
        XCTAssertEqual(group.children.compactMap { ($0 as? UIAction)?.title }, ["Restart", "Close Game"])
    }

    func testGameMenuOpensWithAnIconRowThenStates() throws {
        let (gameplay, _, _) = makeGameplay()
        let items = gameplay.prepareGameMenu()
        let row = try XCTUnwrap(items.first as? UIMenu)
        XCTAssertEqual(row.preferredElementSize, .small)
        XCTAssertEqual(row.children.compactMap { ($0 as? UIAction)?.title }, ["Resume", "Fast Forward", "Quick Save", "Quick Load"])
        for title in ["Quick Save", "Quick Load"] {
            let action = try XCTUnwrap(items.allActions.first { $0.title == title })
            XCTAssertTrue(action.attributes.contains(.disabled), "\(title) needs a library game")
        }
        let states = try XCTUnwrap(items.dropFirst().first as? UIAction)
        XCTAssertEqual(states.title, "States")
        XCTAssertTrue(states.attributes.contains(.disabled))
        XCTAssertEqual(states.subtitle, "Add to Library to save states")
    }

    private func makeGameplay(
        policy: AutoResumePolicy = .always
    ) -> (GameplayViewController, LifecycleRuntime, PhysicalControllerMonitor) {
        let runtime = LifecycleRuntime()
        let monitor = PhysicalControllerMonitor(connectedControllers: { [] })
        let gameplay = GameplayViewController(runtime: runtime, autoResumePolicy: policy, controllerMonitor: monitor)
        gameplay.loadViewIfNeeded()
        return (gameplay, runtime, monitor)
    }

    func testDisplaySettingsReachTheOpenGameWhileItStaysPaused() {
        let (gameplay, runtime, _) = makeGameplay()
        XCTAssertEqual(runtime.displaySettings?.correction, .balanced)
        XCTAssertEqual(runtime.displaySettings?.palette, .dmgGreen)
        gameplay.setCoveredBySheet(true)
        let frames = runtime.frames
        gameplay.applyDisplaySettings(
            controlStyle: .gameBoy, screenScaling: .integer, lcdFilter: .off,
            colorCorrection: .accurate, dmgPalette: .light, frameBlending: .off
        )
        XCTAssertEqual(runtime.displaySettings?.correction, .accurate)
        XCTAssertEqual(runtime.displaySettings?.palette, .light)
        gameplay.applyDisplaySettings(
            controlStyle: .gameBoy, screenScaling: .integer, lcdFilter: .off,
            colorCorrection: .off, dmgPalette: .pocket, frameBlending: .off
        )
        XCTAssertEqual(runtime.displaySettings?.correction, .off)
        XCTAssertEqual(runtime.displaySettings?.palette, .pocket)
        XCTAssertFalse(gameplay.isRunningFrames)
        XCTAssertEqual(runtime.frames, frames)
    }

    func testControllerMenuOpensAndClosesWithTouchControlsHidden() throws {
        let (gameplay, runtime, monitor) = makeGameplay()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = gameplay
        window.makeKeyAndVisible()
        gameplay.view.layoutIfNeeded()
        defer {
            gameplay.sceneWillDeactivate()
            window.isHidden = true
        }
        monitor.selectPlayerOne(GCController.withExtendedGamepad())
        XCTAssertFalse(gameplay.showsTouchControls)
        monitor.onMenuChanged?(true)
        let openDeadline = Date().addingTimeInterval(3)
        while !gameplay.isGameMenuOpen, Date() < openDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(gameplay.isGameMenuOpen)
        XCTAssertTrue(gameplay.isShowingPaused)
        XCTAssertFalse(gameplay.isRunningFrames)
        XCTAssertFalse(gameplay.heldInput.start)
        monitor.onMenuChanged?(false)
        monitor.onMenuChanged?(true)
        let closeDeadline = Date().addingTimeInterval(3)
        while gameplay.isGameMenuOpen || !gameplay.isRunningFrames, Date() < closeDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertFalse(gameplay.isGameMenuOpen)
        XCTAssertTrue(gameplay.isRunningFrames)
        XCTAssertFalse(gameplay.isShowingPaused)
        XCTAssertFalse(gameplay.heldInput.start)
        XCTAssertFalse(runtime.failedFrame)
    }

    func testTheGameMenuChangesSoundWhileTheGameStaysPaused() throws {
        let (gameplay, _, _) = makeGameplay()
        var saved: [SoundMode] = []
        gameplay.onSoundModeChange = { saved.append($0) }
        func soundMenu() throws -> UIMenu {
            try XCTUnwrap(gameplay.prepareGameMenu().compactMap { $0 as? UIMenu }.first { $0.title == "Sound" })
        }
        func selected(_ menu: UIMenu) -> [String] {
            menu.children.compactMap { $0 as? UIAction }.filter { $0.state == .on }.map(\.title)
        }
        let menu = try soundMenu()
        XCTAssertEqual(menu.children.map(\.title), ["Follow Silent Switch", "Always On", "Always Off"])
        XCTAssertEqual(selected(menu), ["Follow Silent Switch"])
        gameplay.setSoundMode(.alwaysOff)
        gameplay.setSoundMode(.alwaysOff)
        XCTAssertEqual(saved, [.alwaysOff], "choosing the current mode again saves nothing")
        XCTAssertEqual(selected(try soundMenu()), ["Always Off"])
        XCTAssertFalse(gameplay.isRunningFrames)
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
        XCTAssertEqual(
            GameplayOrientation.mask(style: .playtiles, controllerConnected: true, coveredBySheet: false), gameplayMask
        )
        XCTAssertEqual(
            GameplayOrientation.mask(style: nil, controllerConnected: true, coveredBySheet: false), .portrait,
            "the library stays portrait with a controller"
        )
        XCTAssertEqual(
            GameplayOrientation.mask(style: .playtiles, orientation: .landscape, controllerConnected: true, coveredBySheet: true),
            .portrait, "sheets stay portrait with a controller"
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

    func testAControllerOverridesPlaytilesAndFollowsOrientationWithoutInterruptingPlay() {
        for orientation in ScreenOrientation.allCases {
            let (gameplay, runtime, monitor) = makeGameplay()
            gameplay.applyDisplaySettings(
                controlStyle: .playtiles, orientation: orientation, screenScaling: .integer,
                lcdFilter: .off, frameBlending: .off
            )
            XCTAssertEqual(gameplay.touchControlStyle, .playtiles)
            XCTAssertEqual(gameplay.supportedInterfaceOrientations, .portrait)
            monitor.selectPlayerOne(GCController.withExtendedGamepad())

            XCTAssertEqual(gameplay.touchControlStyle, .gameBoy)
            XCTAssertEqual(
                gameplay.supportedInterfaceOrientations,
                GameplayOrientation.mask(style: .gameBoy, orientation: orientation, coveredBySheet: false)
            )
            XCTAssertTrue(gameplay.isRunningFrames)
            XCTAssertFalse(gameplay.isShowingPaused)
            gameplay.setCoveredBySheet(true)
            XCTAssertEqual(gameplay.supportedInterfaceOrientations, .portrait)
            gameplay.applyDisplaySettings(
                controlStyle: .playtiles, orientation: orientation, screenScaling: .fill,
                lcdFilter: .off, frameBlending: .off
            )
            XCTAssertEqual(gameplay.touchControlStyle, .gameBoy)
            gameplay.setCoveredBySheet(false)
            XCTAssertFalse(gameplay.isRunningFrames)
            XCTAssertTrue(gameplay.isShowingPaused)
            XCTAssertFalse(runtime.failedFrame)
        }
    }

    func testDisconnectRestoresTheLayoutLastChosenWhileConnected() {
        let (gameplay, _, monitor) = makeGameplay()
        let controller = GCController.withExtendedGamepad()
        monitor.selectPlayerOne(controller)
        gameplay.applyDisplaySettings(
            controlStyle: .playtiles, screenScaling: .integer, lcdFilter: .off, frameBlending: .off
        )
        XCTAssertEqual(gameplay.touchControlStyle, .gameBoy)

        NotificationCenter.default.post(name: .GCControllerDidDisconnect, object: controller)

        XCTAssertEqual(gameplay.touchControlStyle, .playtiles)
        XCTAssertFalse(gameplay.isRunningFrames, "losing the controller pauses the game")
        XCTAssertTrue(gameplay.isShowingPaused)
    }

    func testAControllerConnectedBeforeLaunchOverridesPlaytilesEvenWithTouchControlsShown() {
        let monitor = PhysicalControllerMonitor(connectedControllers: { [] })
        monitor.selectPlayerOne(GCController.withExtendedGamepad())
        let gameplay = GameplayViewController(
            runtime: LifecycleRuntime(), autoResumePolicy: .always, controlStyle: .playtiles,
            orientation: .landscape, hidesTouchControlsWithController: false, controllerMonitor: monitor
        )
        gameplay.loadViewIfNeeded()
        XCTAssertEqual(gameplay.touchControlStyle, .gameBoy)
        XCTAssertEqual(gameplay.supportedInterfaceOrientations, .landscape)
        XCTAssertTrue(gameplay.showsTouchControls)
        XCTAssertTrue(gameplay.isRunningFrames)
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
        let (gameplay, runtime, _) = makeGameplay(policy: .always)
        _ = gameplay.prepareGameMenu()
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

    /// Posts what iOS posts for an audio interruption or route change, then lets the main queue
    /// deliver it: until `arrived` holds, or for a fixed wait when nothing is expected to change.
    private func postAudioNotification(
        _ name: Notification.Name,
        _ userInfo: [AnyHashable: Any],
        until arrived: @autoclosure () -> Bool = false
    ) {
        NotificationCenter.default.post(name: name, object: nil, userInfo: userInfo)
        let deadline = Date().addingTimeInterval(arrived() ? 0 : 0.2)
        while !arrived(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }

    func testAnAudioInterruptionPausesTheGameUntilThePlayerResumes() {
        let (gameplay, runtime, monitor) = makeGameplay(policy: .always)
        monitor.onInputChanged?(EmulatorInputState(start: true))
        XCTAssertTrue(gameplay.isRunningFrames)

        postAudioNotification(AVAudioSession.interruptionNotification, [
            AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue,
        ], until: !gameplay.isRunningFrames)
        XCTAssertFalse(gameplay.isRunningFrames, "the scene is still active, but the sound is gone")
        XCTAssertTrue(gameplay.isShowingPaused)
        XCTAssertFalse(gameplay.heldInput.start)

        postAudioNotification(AVAudioSession.interruptionNotification, [
            AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
            AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue,
        ])
        XCTAssertFalse(gameplay.isRunningFrames, "the player resumes, even when iOS says it may")
        XCTAssertTrue(gameplay.isShowingPaused)
        XCTAssertFalse(runtime.failedFrame)
    }

    func testHeadphonesComingOutPauseButOtherRouteChangesDoNot() {
        let (gameplay, runtime, _) = makeGameplay(policy: .always)
        postAudioNotification(AVAudioSession.routeChangeNotification, [
            AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue,
        ])
        XCTAssertTrue(gameplay.isRunningFrames, "a device arriving doesn't interrupt play")

        postAudioNotification(AVAudioSession.routeChangeNotification, [
            AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue,
        ], until: !gameplay.isRunningFrames)
        XCTAssertFalse(gameplay.isRunningFrames)
        XCTAssertTrue(gameplay.isShowingPaused)
        XCTAssertFalse(runtime.failedFrame)
    }

    func testAnInterruptionReportedForAnEndedSuspensionDoesNotPause() {
        let (gameplay, _, _) = makeGameplay(policy: .always)
        postAudioNotification(AVAudioSession.interruptionNotification, [
            AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue,
            AVAudioSessionInterruptionReasonKey: AVAudioSession.InterruptionReason.appWasSuspended.rawValue,
        ])
        XCTAssertTrue(gameplay.isRunningFrames)
        XCTAssertFalse(gameplay.isShowingPaused)
    }

    func testAnInterruptionInTheBackgroundLeavesResumeGamesInCharge() {
        let (gameplay, runtime, _) = makeGameplay(policy: .always)
        gameplay.sceneWillDeactivate()
        gameplay.sceneDidEnterBackground()
        postAudioNotification(AVAudioSession.interruptionNotification, [
            AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue,
        ])
        gameplay.sceneDidActivate()
        XCTAssertEqual(runtime.foregrounds, 1)
        XCTAssertTrue(gameplay.isRunningFrames, "a call that sent the app away doesn't also pause it")
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
        XCTAssertTrue(items.allActions.contains { $0.title == "Resume" })
        XCTAssertFalse(items.allActions.contains { $0.title == "Pause" })
        let frozen = runtime.frames
        RunLoop.current.run(until: Date().addingTimeInterval(0.06))
        XCTAssertEqual(runtime.frames, frozen, "the game does not advance behind its menu")
        XCTAssertFalse(runtime.failedFrame)
    }

    func testMenuSettingsOpenOverThePausedGameAndApplyLive() throws {
        let (gameplay, runtime, _) = makeGameplay()
        XCTAssertFalse(
            gameplay.prepareGameMenu().contains { ($0 as? UIAction)?.title == "Settings" },
            "without a place to save settings the menu leaves them out"
        )
        var opened = 0
        gameplay.onOpenSettings = { opened += 1 }
        let settings = try XCTUnwrap(gameplay.prepareGameMenu().compactMap { $0 as? UIAction }.first { $0.title == "Settings" })
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

        let resume = try XCTUnwrap(items.allActions.first { $0.title == "Resume" })
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
private class LifecycleRuntime: GameplayRuntime, @unchecked Sendable {
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
    func restart() throws {}
}

private final class StateMenuRuntime: LifecycleRuntime, SaveStateRuntime, @unchecked Sendable {
    private let saved: [SaveState] = [
        SaveState(id: UUID(), buildID: UUID(), saveProfileID: UUID(), core: .init(identifier: "test", version: "1"),
            stateSerializationVersion: "1", stateAssetID: UUID(), kind: .slot, slot: 2, isPinned: true, playtimeSeconds: 0, createdAt: Date()),
        SaveState(id: UUID(), buildID: UUID(), saveProfileID: UUID(), core: .init(identifier: "test", version: "1"),
            stateSerializationVersion: "1", stateAssetID: UUID(), kind: .slot, slot: 5, playtimeSeconds: 0, createdAt: Date()),
        SaveState(id: UUID(), buildID: UUID(), saveProfileID: UUID(), core: .init(identifier: "test", version: "1"),
            stateSerializationVersion: "1", stateAssetID: UUID(), kind: .manual, isPinned: true, label: "Pinned manual", playtimeSeconds: 0, createdAt: Date()),
    ]
    func saveCrashRecoveryIfDue() throws -> Bool { false }
    func saveManualState(label: String?) throws -> SaveState { throw NotRunning() }
    func saveQuickState() throws -> SaveState { throw NotRunning() }
    func saveSlotState(slot: Int) throws -> SaveState { throw NotRunning() }
    func saveStates() throws -> [SaveState] { saved }
    func loadState(_ saveState: SaveState) throws {}
    func loadingWouldRollBackSave(_ saveState: SaveState) throws -> Bool { false }
    func loadStateKeepingCopy(_ saveState: SaveState) throws -> SaveProfile { throw NotRunning() }
    func thumbnailData(for state: SaveState) -> Data? { nil }
}

private extension Array where Element == UIMenuElement {
    var allMenus: [UIMenu] {
        flatMap { element -> [UIMenu] in
            guard let menu = element as? UIMenu else { return [] }
            return [menu] + menu.children.allMenus
        }
    }

    /// Every action in the menu, including those in inline groups and submenus.
    var allActions: [UIAction] {
        flatMap { element -> [UIAction] in
            if let menu = element as? UIMenu { return menu.children.allActions }
            return (element as? UIAction).map { [$0] } ?? []
        }
    }
}

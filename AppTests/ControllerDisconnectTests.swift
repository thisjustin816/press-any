import EmulationCore
import EmulatorDomain
import GameController
import GameplayInput
import XCTest
@testable import PressAny

@MainActor
final class ControllerDisconnectTests: XCTestCase {
    func testDisconnectingRestoresPlaytilesAndReleasesInputWithoutPausing() {
        let runtime = FakeRuntime()
        let monitor = PhysicalControllerMonitor(connectedControllers: { [] })
        let gameplay = GameplayViewController(
            runtime: runtime, autoResumePolicy: .always, controlStyle: .playtiles,
            orientation: .landscape, controllerMonitor: monitor
        )
        gameplay.loadViewIfNeeded()

        let controller = GCController.withExtendedGamepad()
        monitor.selectPlayerOne(controller)
        XCTAssertFalse(gameplay.showsTouchControls, "a connected controller hides the touch controls")
        XCTAssertEqual(gameplay.touchControlStyle, .gameBoy)
        XCTAssertEqual(gameplay.supportedInterfaceOrientations, .landscape)
        monitor.onInputChanged?(.init(right: true, a: true))
        XCTAssertTrue(gameplay.heldInput.a)
        let pauses = runtime.pauseCount

        NotificationCenter.default.post(name: .GCControllerDidDisconnect, object: controller)
        // The monitor observes on the main queue; let it deliver if it didn't run inline.
        let deadline = Date().addingTimeInterval(2)
        while monitor.isConnected, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }

        XCTAssertFalse(monitor.isConnected)
        XCTAssertFalse(gameplay.isShowingPaused)
        XCTAssertTrue(gameplay.isRunningFrames)
        XCTAssertEqual(runtime.pauseCount, pauses)
        XCTAssertEqual(runtime.stopCount, 0)
        XCTAssertEqual(gameplay.heldInput, .init())
        XCTAssertEqual(gameplay.touchControlStyle, .playtiles)
        XCTAssertEqual(gameplay.supportedInterfaceOrientations, .portrait)
        XCTAssertTrue(gameplay.showsTouchControls)
    }

    func testDisconnectingKeepsAnAlreadyPausedGamePaused() {
        let runtime = FakeRuntime()
        let monitor = PhysicalControllerMonitor(connectedControllers: { [] })
        let gameplay = GameplayViewController(
            runtime: runtime, autoResumePolicy: .always, controlStyle: .playtiles,
            controllerMonitor: monitor
        )
        gameplay.loadViewIfNeeded()
        let controller = GCController.withExtendedGamepad()
        monitor.selectPlayerOne(controller)
        _ = gameplay.prepareGameMenu()
        let pauses = runtime.pauseCount

        NotificationCenter.default.post(name: .GCControllerDidDisconnect, object: controller)

        XCTAssertFalse(monitor.isConnected)
        XCTAssertTrue(gameplay.isShowingPaused)
        XCTAssertFalse(gameplay.isRunningFrames)
        XCTAssertEqual(runtime.pauseCount, pauses)
        XCTAssertEqual(runtime.stopCount, 0)
        XCTAssertEqual(gameplay.touchControlStyle, .playtiles)
        XCTAssertTrue(gameplay.showsTouchControls)
    }
}

/// A touch brings the hidden touch controls back until the controller's next button press,
/// and Settings can keep them showing.
@MainActor
final class TouchControlRevealTests: XCTestCase {
    func testATouchRevealsTheControlsUntilTheControllerIsUsed() {
        let monitor = PhysicalControllerMonitor(connectedControllers: { [] })
        let gameplay = GameplayViewController(runtime: FakeRuntime(), autoResumePolicy: .always, controllerMonitor: monitor)
        gameplay.loadViewIfNeeded()
        monitor.selectPlayerOne(GCController.withExtendedGamepad())
        XCTAssertFalse(gameplay.showsTouchControls, "a connected controller hides the touch controls")

        gameplay.touchesBegan([], with: nil)
        XCTAssertTrue(gameplay.showsTouchControls, "a touch brings them back")

        monitor.onInputChanged?(EmulatorInputState())
        XCTAssertTrue(gameplay.showsTouchControls, "a release with nothing pressed keeps them")

        monitor.onInputChanged?(EmulatorInputState(a: true))
        XCTAssertFalse(gameplay.showsTouchControls, "a controller press hides them again")
    }

    func testTheSettingKeepsTheControlsWithAController() {
        let monitor = PhysicalControllerMonitor(connectedControllers: { [] })
        let gameplay = GameplayViewController(
            runtime: FakeRuntime(),
            autoResumePolicy: .always,
            hidesTouchControlsWithController: false,
            controllerMonitor: monitor
        )
        gameplay.loadViewIfNeeded()
        monitor.selectPlayerOne(GCController.withExtendedGamepad())
        XCTAssertTrue(gameplay.showsTouchControls)
    }
}

private final class FakeRuntime: GameplayRuntime, @unchecked Sendable {
    private let lock = NSLock()
    private var pauses = 0
    private var stops = 0

    var pauseCount: Int { lock.withLock { pauses } }
    var stopCount: Int { lock.withLock { stops } }
    var currentFrame: EmulatorVideoFrame? { nil }
    var playtimeSeconds: Double { 0 }

    func stepFrame(input: EmulatorInputState) throws -> EmulatorVideoFrame {
        EmulatorVideoFrame(width: 160, height: 144, bgra8888: Data(count: 160 * 144 * 4), emulatedNanoseconds: 16_742_706)
    }

    func drainAudio(maxFrames: Int) throws -> [StereoSample] { [] }
    func setSpeed(_ speed: EmulationSpeed) throws {}
    func setDisplaySettings(colorCorrection: ColorCorrection, dmgPalette: DMGPalette) throws -> EmulatorVideoFrame? { nil }
    func consumeRumbleAmplitude() throws -> Double { 0 }
    func pause() throws { lock.withLock { pauses += 1 } }
    func resume() throws {}
    func background() throws {}
    func foreground(policy: AutoResumePolicy) throws -> Bool { true }
    func stop(createAutoState: Bool) throws { lock.withLock { stops += 1 } }
    func stop(createAutoState: Bool, discardUnsaved: Bool) throws { lock.withLock { stops += 1 } }
    func flushBatteryIfChanged() throws -> Bool { false }
}

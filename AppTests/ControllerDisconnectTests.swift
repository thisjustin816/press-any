import EmulationCore
import EmulatorDomain
import GameController
import XCTest
@testable import PressAny

/// MVP test 14: losing the controller mid-game pauses it and brings the touch controls back.
@MainActor
final class ControllerDisconnectTests: XCTestCase {
    func testDisconnectingTheControllerPausesAndShowsTouchControls() throws {
        let runtime = FakeRuntime()
        let monitor = PhysicalControllerMonitor()
        let gameplay = GameplayViewController(runtime: runtime, autoResumePolicy: .always, controllerMonitor: monitor)
        gameplay.loadViewIfNeeded()

        let controller = GCController.withExtendedGamepad()
        monitor.selectPlayerOne(controller)
        XCTAssertFalse(gameplay.showsTouchControls, "a connected controller hides the touch controls")

        NotificationCenter.default.post(name: .GCControllerDidDisconnect, object: controller)
        // The monitor observes on the main queue; let it deliver if it didn't run inline.
        let deadline = Date().addingTimeInterval(2)
        while !gameplay.isShowingPaused, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }

        XCTAssertTrue(gameplay.isShowingPaused)
        XCTAssertTrue(runtime.pauseCount > 0, "the emulator itself is paused")
        XCTAssertTrue(gameplay.showsTouchControls)
    }
}

/// A touch brings the hidden touch controls back until the controller's next button press,
/// and Settings can keep them showing.
@MainActor
final class TouchControlRevealTests: XCTestCase {
    func testATouchRevealsTheControlsUntilTheControllerIsUsed() {
        let monitor = PhysicalControllerMonitor()
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
        let monitor = PhysicalControllerMonitor()
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

    var pauseCount: Int { lock.withLock { pauses } }
    var currentFrame: EmulatorVideoFrame? { nil }
    var playtimeSeconds: Double { 0 }

    func stepFrame(input: EmulatorInputState) throws -> EmulatorVideoFrame {
        EmulatorVideoFrame(width: 160, height: 144, bgra8888: Data(count: 160 * 144 * 4), emulatedNanoseconds: 16_742_706)
    }

    func drainAudio(maxFrames: Int) throws -> [StereoSample] { [] }
    func setSpeed(_ speed: EmulationSpeed) throws {}
    func consumeRumbleAmplitude() throws -> Double { 0 }
    func pause() throws { lock.withLock { pauses += 1 } }
    func resume() throws {}
    func background() throws {}
    func foreground(policy: AutoResumePolicy) throws -> Bool { true }
    func stop(createAutoState: Bool) throws {}
    func stop(createAutoState: Bool, discardUnsaved: Bool) throws {}
    func flushBatteryIfChanged() throws -> Bool { false }
}

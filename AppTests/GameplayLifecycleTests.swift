import EmulationCore
import EmulatorDomain
import XCTest
@testable import PressAny

/// The game pauses whenever its scene isn't active, and a trip to the background brings it back
/// only as Resume Games says (docs/decisions.md "Pause when the app goes inactive").
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
    struct NotRunning: Error {}

    var backgrounds: Int { lock.withLock { backgroundCount } }
    var foregrounds: Int { lock.withLock { foregroundCount } }
    var failedFrame: Bool { lock.withLock { failed } }
    var currentFrame: EmulatorVideoFrame? { nil }
    var playtimeSeconds: Double { 0 }

    func stepFrame(input: EmulatorInputState) throws -> EmulatorVideoFrame {
        try lock.withLock {
            if paused {
                failed = true
                throw NotRunning()
            }
        }
        return EmulatorVideoFrame(width: 160, height: 144, bgra8888: Data(count: 160 * 144 * 4), emulatedNanoseconds: 16_742_706)
    }

    func drainAudio(maxFrames: Int) throws -> [StereoSample] { [] }
    func setSpeed(_ speed: EmulationSpeed) throws {}
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

import EmulationCore
import EmulatorDomain
import Foundation
import XCTest
@testable import PressAny

final class GameplayDriverTests: XCTestCase {
    func testPeriodicSaveDoesNotBlockFramePacing() throws {
        let runtime = BlockingSaveRuntime()
        let driver = GameplayDriver(
            runtime: runtime,
            input: GameplayInputAccumulator(),
            savePollNanoseconds: 1
        )
        driver.start()
        // A busy simulator can take seconds to deliver the first display refresh, so the waits
        // allow for that. What the test checks is that frames keep coming while the save is held.
        XCTAssertEqual(runtime.saveStarted.wait(timeout: .now() + 10), .success)
        let framesBeforeWait = runtime.frameCount

        let deadline = Date().addingTimeInterval(10)
        while runtime.frameCount <= framesBeforeWait, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        XCTAssertGreaterThan(runtime.frameCount, framesBeforeWait)

        runtime.allowSaveToFinish.signal()
        driver.stop()
    }
}

private final class BlockingSaveRuntime: GameplayRuntime, @unchecked Sendable {
    let saveStarted = DispatchSemaphore(value: 0)
    let allowSaveToFinish = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var frames = 0
    private var hasBlockedSave = false

    var currentFrame: EmulatorVideoFrame?
    var playtimeSeconds: Double { 0 }
    var frameCount: Int { lock.withLock { frames } }

    func stepFrame(input: EmulatorInputState) throws -> EmulatorVideoFrame {
        lock.withLock { frames += 1 }
        return EmulatorVideoFrame(width: 1, height: 1, bgra8888: Data(repeating: 0, count: 4), emulatedNanoseconds: 1)
    }

    func drainAudio(maxFrames: Int) throws -> [StereoSample] { [] }
    func setSpeed(_ speed: EmulationSpeed) throws {}
    func setDisplaySettings(colorCorrection: ColorCorrection, dmgPalette: DMGPalette) throws -> EmulatorVideoFrame? { nil }
    func consumeRumbleAmplitude() throws -> Double { 0 }
    func pause() throws {}
    func resume() throws {}
    func background() throws {}
    func foreground(policy: AutoResumePolicy) throws -> Bool { true }
    func stop(createAutoState: Bool) throws {}
    func stop(createAutoState: Bool, discardUnsaved: Bool) throws {}

    func flushBatteryIfChanged() throws -> Bool {
        let shouldBlock = lock.withLock {
            guard !hasBlockedSave else { return false }
            hasBlockedSave = true
            return true
        }
        if shouldBlock {
            saveStarted.signal()
            allowSaveToFinish.wait()
        }
        return true
    }
}

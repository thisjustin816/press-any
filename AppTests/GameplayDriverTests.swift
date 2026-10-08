import EmulationCore
import EmulatorDomain
import Foundation
import XCTest
@testable import PressAny

final class GameplayDriverTests: XCTestCase {
    func testPeriodicSaveDoesNotBlockFramePacing() throws {
        let runtime = BlockingSaveRuntime()
        let refreshes = ManualRefreshes()
        let driver = GameplayDriver(
            runtime: runtime,
            input: GameplayInputAccumulator(),
            savePollNanoseconds: 1,
            makeRefreshes: { refreshes.attach($0) }
        )
        driver.start()
        defer {
            runtime.allowSaveToFinish.signal()
            driver.stop()
        }
        // The test sends its own refreshes, so it doesn't depend on when a busy simulator's display
        // link starts. What it checks is that frames keep coming while the save is held.
        XCTAssertTrue(refreshes.send(until: { runtime.saveStarted.wait(timeout: .now()) == .success }))
        let framesBeforeWait = runtime.frameCount
        XCTAssertTrue(refreshes.send(until: { runtime.frameCount > framesBeforeWait }))
    }
}

/// Stands in for the display link: each `send` reports one 60 Hz refresh.
private final class ManualRefreshes: DisplayRefreshSource, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: DisplayRefreshHandler?
    private var cancelled = false

    func attach(_ handler: @escaping DisplayRefreshHandler) -> any DisplayRefreshSource {
        lock.withLock { self.handler = handler }
        return self
    }

    func start() {}

    func cancel() {
        lock.withLock { cancelled = true }
    }

    /// Sends refreshes until `condition` holds, for up to 10 seconds, and returns whether it did.
    func send(until condition: () -> Bool) -> Bool {
        let interval: UInt64 = 16_742_706
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if condition() { return true }
            lock.withLock { if !cancelled { handler?(interval, interval) } }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return condition()
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

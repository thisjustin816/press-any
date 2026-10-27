import EmulationCore
import EmulatorDomain
import EmulatorApplication
import Foundation
import XCTest
@testable import PressAny

final class GameplayDriverTests: XCTestCase {
    func testPrinterFailureReportsAnErrorAndFramesContinueToDeliverTheNextPrint() throws {
        let runtime = PrinterTestRuntime()
        let recorder = PrinterRecorder()
        let refreshes = ManualRefreshes()
        let driver = GameplayDriver(runtime: runtime, input: GameplayInputAccumulator(),
            makeRefreshes: { refreshes.attach($0) })
        driver.onPrinterOutput = { recorder.record($0) }
        driver.onPrinterError = { _ in recorder.recordError() }
        driver.start()
        defer { runtime.allowSaveToFinish.signal(); driver.stop() }
        XCTAssertTrue(refreshes.send(until: { recorder.receivedPrint }))
        XCTAssertEqual(recorder.errors, 1)
        XCTAssertTrue(driver.isRunning)
    }

    func testCameraSensorUpdatesLeaveAHeldCaptureUntilExplicitlyCleared() throws {
        let runtime = BlockingSaveRuntime()
        let refreshes = ManualRefreshes()
        let driver = GameplayDriver(runtime: runtime, input: GameplayInputAccumulator(),
            makeRefreshes: { refreshes.attach($0) })
        let buffer = CameraFrameBuffer()
        let generation = buffer.begin()
        let frame = try CameraFrame(luminance: Data(repeating: 76, count: 128 * 112))
        buffer.store(frame, generation: generation)
        driver.cameraFrames = buffer
        driver.start()
        defer {
            runtime.allowSaveToFinish.signal()
            driver.stop()
        }
        XCTAssertTrue(refreshes.send(until: { runtime.sensorAtLastFrame == frame }))
        let before = runtime.frameCount
        buffer.clear()
        XCTAssertTrue(refreshes.send(until: { runtime.frameCount > before }))
        XCTAssertEqual(runtime.sensorAtLastFrame, frame, "a pause must not replace an RGB sequence's frozen source")
        try driver.clearCameraFrame()
        let clearedAt = runtime.frameCount
        XCTAssertTrue(refreshes.send(until: { runtime.frameCount > clearedAt && runtime.sensorAtLastFrame == nil }))
    }

    func testTimedStateUsesSaveQueueAndFramesContinueDuringTheWrite() throws {
        let runtime = BlockingTimedStateRuntime()
        let refreshes = ManualRefreshes()
        let driver = GameplayDriver(runtime: runtime, input: GameplayInputAccumulator(), savePollNanoseconds: 1,
            makeRefreshes: { refreshes.attach($0) })
        driver.start()
        defer {
            runtime.allowSaveToFinish.signal()
            driver.stop()
        }
        XCTAssertEqual(runtime.intervalResets, 1)
        XCTAssertTrue(refreshes.send(until: { runtime.saveStarted.wait(timeout: .now()) == .success }))
        XCTAssertFalse(runtime.timedWriteOnMainThread)
        let before = runtime.frameCount
        XCTAssertTrue(refreshes.send(until: { runtime.frameCount > before }))
        runtime.allowSaveToFinish.signal()
        driver.stop()
        driver.start()
        XCTAssertEqual(runtime.intervalResets, 2, "a menu or sheet restarts the interval")
    }

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
        lock.withLock {
            self.handler = handler
            cancelled = false
        }
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

private class BlockingSaveRuntime: GameplayRuntime, @unchecked Sendable {
    let saveStarted = DispatchSemaphore(value: 0)
    let allowSaveToFinish = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var frames = 0
    private var hasBlockedSave = false
    private var sensor: CameraFrame?
    private var frameSensor: CameraFrame?
    var sensorAtLastFrame: CameraFrame? { lock.withLock { frameSensor } }

    func setCameraFrame(_ frame: CameraFrame?) throws { lock.withLock { sensor = frame } }

    var currentFrame: EmulatorVideoFrame?
    var playtimeSeconds: Double { 0 }
    var frameCount: Int { lock.withLock { frames } }

    func stepFrame(input: EmulatorInputState) throws -> EmulatorVideoFrame {
        lock.withLock {
            frames += 1
            frameSensor = sensor
        }
        return EmulatorVideoFrame(width: 1, height: 1, bgra8888: Data(repeating: 0, count: 4), emulatedNanoseconds: 1)
    }

    func drainAudio(maxFrames: Int) throws -> [StereoSample] { [] }
    func setSpeed(_ speed: EmulationSpeed) throws {}
    func setDisplaySettings(
        colorCorrection: ColorCorrection,
        dmgPalette: DMGPalette,
        advanceColors: AdvanceColors
    ) throws -> EmulatorVideoFrame? { nil }
    func drainPrinterOutput() throws -> [PrinterOutput] { [] }
    func consumeRumbleAmplitude() throws -> Double { 0 }
    func pause() throws {}
    func resume() throws {}
    func background() throws {}
    func foreground(policy: AutoResumePolicy) throws -> Bool { true }
    func stop(createAutoState: Bool) throws {}
    func stop(createAutoState: Bool, discardUnsaved: Bool) throws {}
    func restart() throws {}

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

private final class BlockingTimedStateRuntime: BlockingSaveRuntime, SaveStateRuntime, @unchecked Sendable {
    private let timedLock = NSLock()
    private var resets = 0
    private var wroteOnMain = false
    var intervalResets: Int { timedLock.withLock { resets } }
    var timedWriteOnMainThread: Bool { timedLock.withLock { wroteOnMain } }

    func resetTimedStateInterval() { timedLock.withLock { resets += 1 } }
    func saveTimedStateIfDue() throws -> Bool {
        timedLock.withLock { wroteOnMain = Thread.isMainThread }
        return try super.flushBatteryIfChanged()
    }
    override func flushBatteryIfChanged() throws -> Bool { false }
    func saveCrashRecoveryIfDue() throws -> Bool { false }
    func saveStates() throws -> [SaveState] { [] }
    func saveManualState(label: String?) throws -> SaveState { throw NotSupported() }
    func saveQuickState() throws -> SaveState { throw NotSupported() }
    func saveSlotState(slot: Int) throws -> SaveState { throw NotSupported() }
    func loadState(_ saveState: SaveState) throws {}
    func loadingWouldRollBackSave(_ saveState: SaveState) throws -> Bool { false }
    func loadStateKeepingCopy(_ saveState: SaveState) throws -> SaveProfile { throw NotSupported() }
    func thumbnailData(for state: SaveState) -> Data? { nil }
    private struct NotSupported: Error {}
}

private final class PrinterTestRuntime: BlockingSaveRuntime, @unchecked Sendable {
    private var calls = 0
    override func drainPrinterOutput() throws -> [PrinterOutput] {
        calls += 1
        if calls == 1 { throw TestError.queueFull }
        if calls == 2 {
            return [try PrinterOutput(height: 1, luminance: Data(count: 160), topMargin: 1, bottomMargin: 3, exposure: 64)]
        }
        return []
    }
    private enum TestError: Error { case queueFull }
}

private final class PrinterRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var prints: [PrinterOutput] = []
    private var errorCount = 0
    var receivedPrint: Bool { lock.withLock { !prints.isEmpty } }
    var errors: Int { lock.withLock { errorCount } }
    func record(_ output: [PrinterOutput]) { lock.withLock { prints += output } }
    func recordError() { lock.withLock { errorCount += 1 } }
}

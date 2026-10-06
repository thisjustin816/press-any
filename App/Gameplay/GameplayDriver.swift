import EmulationCore
import Foundation

/// Owns the emulation frame loop. Core work never runs on the main/UI thread.
final class GameplayDriver: @unchecked Sendable {
    typealias FrameHandler = @Sendable (EmulatorVideoFrame) -> Void
    typealias AudioHandler = @Sendable ([StereoSample]) -> Void
    typealias RumbleHandler = @Sendable (Double) -> Void
    typealias ErrorHandler = @Sendable (Error) -> Void

    private let runtime: any GameplayRuntime
    private let input: GameplayInputAccumulator
    private let queue = DispatchQueue(label: "Gameplay.Driver", qos: .userInteractive)
    private let saveQueue = DispatchQueue(label: "Gameplay.Save", qos: .utility)
    private let stateLock = NSLock()
    private let saveStateLock = NSLock()
    private let savePollNanoseconds: UInt64

    private var running = false
    private var requestedSpeed: EmulationSpeed = .normal
    /// Read and written only on the save queue.
    private var lastSaveFailed = false
    private var saveCheckInFlight = false

    var onFrame: FrameHandler?
    var onAudio: AudioHandler?
    var onRumble: RumbleHandler?
    var onError: ErrorHandler?
    /// A periodic game save failed after the last one succeeded. Play continues, and the next
    /// check tries again.
    var onSaveError: ErrorHandler?

    init(
        runtime: any GameplayRuntime,
        input: GameplayInputAccumulator,
        savePollNanoseconds: UInt64 = 1_000_000_000
    ) {
        self.runtime = runtime
        self.input = input
        self.savePollNanoseconds = savePollNanoseconds
    }

    /// Whether the frame loop is running. It stops on its own when a frame fails.
    var isRunning: Bool { stateLock.withLock { running } }

    func start() {
        let shouldStart = stateLock.withLock { () -> Bool in
            guard !running else { return false }
            running = true
            return true
        }
        guard shouldStart else { return }
        queue.async { [weak self] in self?.runLoop() }
    }

    /// Returns once the loop has exited, so the caller can pause or stop the runtime without a
    /// frame still in flight. A frame stepped after the pause would fail and end the game.
    /// Never call this from the driver's own queue.
    func stop() {
        stateLock.withLock { running = false }
        queue.sync {}
        saveQueue.sync {}
    }

    func setSpeed(_ speed: EmulationSpeed) {
        stateLock.withLock { requestedSpeed = speed }
        queue.async { [weak self] in
            guard let self else { return }
            do { try self.runtime.setSpeed(speed) }
            catch { self.onError?(error) }
        }
    }

    private func runLoop() {
        var pacer = FramePacer(start: DispatchTime.now().uptimeNanoseconds)
        var emulatedNanosecondsSinceSavePoll: UInt64 = 0
        while stateLock.withLock({ running }) {
            do {
                let frame = try runtime.stepFrame(input: input.current())
                emulatedNanosecondsSinceSavePoll &+= frame.emulatedNanoseconds
                if emulatedNanosecondsSinceSavePoll >= savePollNanoseconds {
                    emulatedNanosecondsSinceSavePoll = 0
                    scheduleGameSave()
                }
                let samples = try runtime.drainAudio(maxFrames: 4096)
                let rumble = try runtime.consumeRumbleAmplitude()

                onFrame?(frame)
                if !samples.isEmpty { onAudio?(samples) }
                if rumble > 0 { onRumble?(rumble) }

                pace(frameDuration: frame.emulatedNanoseconds, with: &pacer)
            } catch {
                stateLock.withLock { running = false }
                onError?(error)
            }
        }
    }

    /// Persistence can touch the filesystem and database. Keep it off the frame-pacing queue so a
    /// game that updates SRAM during play cannot hitch every time its periodic save is written.
    private func scheduleGameSave() {
        let shouldSchedule = saveStateLock.withLock { () -> Bool in
            guard !saveCheckInFlight else { return false }
            saveCheckInFlight = true
            return true
        }
        guard shouldSchedule else { return }
        saveQueue.async { [weak self] in
            guard let self else { return }
            defer { self.saveStateLock.withLock { self.saveCheckInFlight = false } }
            do {
                if try self.runtime.flushBatteryIfChanged() { self.lastSaveFailed = false }
            } catch {
                if !self.lastSaveFailed { self.onSaveError?(error) }
                self.lastSaveFailed = true
            }
        }
    }

    private func pace(frameDuration: UInt64, with pacer: inout FramePacer) {
        let speed = stateLock.withLock { requestedSpeed }
        let targetNanoseconds: UInt64
        switch speed {
        case .normal:
            targetNanoseconds = frameDuration
        case .multiplier(let value):
            targetNanoseconds = value > 0 ? UInt64(Double(frameDuration) / value) : 0
        case .unlimited:
            targetNanoseconds = 0
        }

        let delay = pacer.delay(afterFrameLasting: targetNanoseconds, now: DispatchTime.now().uptimeNanoseconds)
        if delay > 0 { Thread.sleep(forTimeInterval: Double(delay) / 1_000_000_000) }
    }
}

/// Schedules frames against fixed deadlines, so time lost oversleeping one frame is made up on the
/// next. Sleeping a frame's full length after each frame instead would run the game slightly slow,
/// and its sound would fall behind the audio output.
struct FramePacer {
    /// Frames this far behind, after a stall, are dropped from the schedule rather than run back to
    /// back to catch up.
    static let maximumLagFrames: UInt64 = 4

    private var deadline: UInt64

    /// `start` is when the first frame began.
    init(start: UInt64) {
        deadline = start
    }

    /// Returns how long to wait before the next frame, given how long the frame just run should
    /// last. A length of 0, for unlimited speed, never waits.
    mutating func delay(afterFrameLasting duration: UInt64, now: UInt64) -> UInt64 {
        guard duration > 0 else {
            deadline = now
            return 0
        }
        let next = deadline &+ duration
        if next > now {
            deadline = next
            return next - now
        }
        deadline = now - next > duration * Self.maximumLagFrames ? now : next
        return 0
    }
}

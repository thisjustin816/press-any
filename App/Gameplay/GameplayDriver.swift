import EmulationCore
import EmulationSession
import Foundation
import QuartzCore

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
    private var refreshes: DisplayRefreshThread?
    /// Refresh time not yet handed to the driver queue. Refreshes that arrive while the queue is
    /// busy merge into one, so a stall reaches the scheduler as a single long refresh and its lag
    /// limit applies.
    private var pendingRefresh: (elapsed: UInt64, interval: UInt64)?
    /// Read and written only on the driver queue.
    private var scheduler = FrameScheduler()
    private var emulatedNanosecondsSinceSavePoll: UInt64 = 0
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
        savePollNanoseconds: UInt64 = 250_000_000
    ) {
        self.runtime = runtime
        self.input = input
        self.savePollNanoseconds = savePollNanoseconds
    }

    /// Whether the frame loop is running. It stops on its own when a frame fails.
    var isRunning: Bool { stateLock.withLock { running } }

    func start() {
        let (shouldStart, stale) = stateLock.withLock { () -> (Bool, DisplayRefreshThread?) in
            guard !running else { return (false, nil) }
            running = true
            pendingRefresh = nil
            defer { self.refreshes = nil }
            return (true, self.refreshes)
        }
        // However the loop last stopped, its display link goes before a new one starts.
        stale?.cancel()
        guard shouldStart else { return }
        queue.async { [weak self] in
            self?.scheduler = FrameScheduler()
        }
        let refreshes = DisplayRefreshThread { [weak self] elapsed, interval in
            guard let self else { return }
            let isFirst = self.stateLock.withLock { () -> Bool in
                let pending = self.pendingRefresh
                self.pendingRefresh = ((pending.map { $0.elapsed } ?? 0) + elapsed, interval)
                return pending == nil
            }
            guard isFirst else { return }
            self.queue.async {
                guard let refresh = self.stateLock.withLock({ () -> (elapsed: UInt64, interval: UInt64)? in
                    defer { self.pendingRefresh = nil }
                    return self.pendingRefresh
                }) else { return }
                self.refresh(elapsed: refresh.elapsed, interval: refresh.interval)
            }
        }
        stateLock.withLock { self.refreshes = refreshes }
        refreshes.start()
    }

    /// Returns once the loop has exited, so the caller can pause or stop the runtime without a
    /// frame still in flight. A frame stepped after the pause would fail and end the game.
    /// Never call this from the driver's own queue.
    func stop() {
        let refreshes = stateLock.withLock { () -> DisplayRefreshThread? in
            running = false
            defer { self.refreshes = nil }
            return self.refreshes
        }
        refreshes?.cancel()
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

    /// Runs the frames due since the last display refresh, then shows the newest, so every frame is
    /// presented on a refresh.
    private func refresh(elapsed: UInt64, interval: UInt64) {
        guard stateLock.withLock({ running }) else { return }
        let speed = stateLock.withLock { requestedSpeed }
        var latest: EmulatorVideoFrame?
        do {
            switch speed {
            case .normal:
                scheduler.addRefresh(lasting: elapsed)
            case .multiplier(let value):
                scheduler.addRefresh(lasting: elapsed, speed: max(0, value))
            case .unlimited:
                break
            }
            if case .unlimited = speed {
                // As many frames as fit in most of a refresh, leaving time to present.
                let deadline = DispatchTime.now().uptimeNanoseconds &+ interval * 3 / 4
                repeat {
                    latest = try runFrame()
                } while DispatchTime.now().uptimeNanoseconds < deadline && stateLock.withLock({ running })
            } else {
                while scheduler.isFrameDue, stateLock.withLock({ running }) {
                    let frame = try runFrame()
                    scheduler.ranFrame(lasting: frame.emulatedNanoseconds)
                    latest = frame
                }
            }
        } catch {
            let refreshes = stateLock.withLock { () -> DisplayRefreshThread? in
                running = false
                defer { self.refreshes = nil }
                return self.refreshes
            }
            refreshes?.cancel()
            onError?(error)
        }
        if let latest { onFrame?(latest) }
    }

    private func runFrame() throws -> EmulatorVideoFrame {
        let frame = try runtime.stepFrame(input: input.current())
        emulatedNanosecondsSinceSavePoll &+= frame.emulatedNanoseconds
        if emulatedNanosecondsSinceSavePoll >= savePollNanoseconds {
            emulatedNanosecondsSinceSavePoll = 0
            scheduleGameSave()
        }
        let samples = try runtime.drainAudio(maxFrames: 4096)
        let rumble = try runtime.consumeRumbleAmplitude()
        if !samples.isEmpty { onAudio?(samples) }
        if rumble > 0 { onRumble?(rumble) }
        return frame
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
                var wroteSave = false
                try SessionSaveError.attempting([
                    {
                        if let states = self.runtime as? any SaveStateRuntime {
                            wroteSave = try states.saveCrashRecoveryIfDue()
                        }
                    },
                    { wroteSave = try self.runtime.flushBatteryIfChanged() || wroteSave },
                ])
                if wroteSave { self.lastSaveFailed = false }
            } catch {
                if !self.lastSaveFailed { self.onSaveError?(error) }
                self.lastSaveFailed = true
            }
        }
    }

}

/// Turns display refreshes into emulated frames at the game's own rate. Each refresh adds the real
/// time since the last one to what the game is owed, and frames run while at least one is owed. On a
/// 60 Hz screen a 59.73 Hz Game Boy shows each frame for one refresh and repeats one about every
/// four seconds.
struct FrameScheduler {
    /// After a stall, a refresh longer than this many frames counts as one frame, so the game
    /// doesn't race to catch up.
    static let maximumLagFrames: UInt64 = 4

    private(set) var owedNanoseconds: UInt64 = 0
    /// The last frame's length. Until a frame has run, its length is unknown and one frame is due.
    private var frameNanoseconds: UInt64?

    var isFrameDue: Bool {
        guard let frameNanoseconds else { return true }
        return owedNanoseconds >= frameNanoseconds
    }

    /// Adds a refresh's real time, scaled by the play speed.
    mutating func addRefresh(lasting elapsed: UInt64, speed: Double = 1) {
        guard let frameNanoseconds else { return }
        let wall = elapsed > frameNanoseconds * Self.maximumLagFrames ? frameNanoseconds : elapsed
        owedNanoseconds &+= UInt64(Double(wall) * speed)
    }

    mutating func ranFrame(lasting duration: UInt64) {
        let duration = max(duration, 1)
        if frameNanoseconds == nil {
            frameNanoseconds = duration
            return
        }
        frameNanoseconds = duration
        owedNanoseconds -= min(owedNanoseconds, duration)
    }
}

/// Reports each display refresh from its own thread, with the time since the previous refresh and
/// the length of the next one, both from the display's clock. A busy main thread can't delay it.
/// Allows up to 120 Hz on ProMotion screens, where a repeated frame lasts half as long.
final class DisplayRefreshThread: NSObject, @unchecked Sendable {
    typealias Handler = @Sendable (_ elapsed: UInt64, _ interval: UInt64) -> Void

    private let handler: Handler
    private let lock = NSLock()
    private var cancelled = false
    private var link: CADisplayLink?
    private var runLoop: CFRunLoop?
    private var lastTimestamp: CFTimeInterval?

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func start() {
        let thread = Thread { [self] in run() }
        thread.name = "Gameplay.DisplayRefresh"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// Safe from any thread. No refresh is reported after it returns.
    func cancel() {
        let (link, runLoop) = lock.withLock { () -> (CADisplayLink?, CFRunLoop?) in
            cancelled = true
            return (self.link, self.runLoop)
        }
        link?.invalidate()
        // Removing the link doesn't wake a run loop waiting on another thread, so stop it too.
        if let runLoop { CFRunLoopStop(runLoop) }
    }

    private func run() {
        let link = CADisplayLink(target: self, selector: #selector(refreshed(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        let started = lock.withLock { () -> Bool in
            guard !cancelled else { return false }
            self.link = link
            runLoop = CFRunLoopGetCurrent()
            return true
        }
        guard started else { return }
        link.add(to: .current, forMode: .common)
        while !lock.withLock({ cancelled }) {
            RunLoop.current.run(mode: .default, before: .distantFuture)
        }
    }

    /// Reports under the lock, so `cancel()` waits out a report in progress. The handler must not
    /// call `cancel()`.
    @objc private func refreshed(_ link: CADisplayLink) {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { return }
        let elapsed = lastTimestamp.map { max(0, link.timestamp - $0) } ?? 0
        lastTimestamp = link.timestamp
        let interval = max(0, link.targetTimestamp - link.timestamp)
        handler(UInt64(elapsed * 1_000_000_000), UInt64(interval * 1_000_000_000))
    }
}

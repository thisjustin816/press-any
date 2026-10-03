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
    private let stateLock = NSLock()

    private var running = false
    private var requestedSpeed: EmulationSpeed = .normal

    var onFrame: FrameHandler?
    var onAudio: AudioHandler?
    var onRumble: RumbleHandler?
    var onError: ErrorHandler?

    init(runtime: any GameplayRuntime, input: GameplayInputAccumulator) {
        self.runtime = runtime
        self.input = input
    }

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
        while stateLock.withLock({ running }) {
            let started = DispatchTime.now().uptimeNanoseconds
            do {
                let frame = try runtime.stepFrame(input: input.current())
                let samples = try runtime.drainAudio(maxFrames: 4096)
                let rumble = try runtime.consumeRumbleAmplitude()

                onFrame?(frame)
                if !samples.isEmpty { onAudio?(samples) }
                if rumble > 0 { onRumble?(rumble) }

                pace(frameDuration: frame.emulatedNanoseconds, startedAt: started)
            } catch {
                stateLock.withLock { running = false }
                onError?(error)
            }
        }
    }

    private func pace(frameDuration: UInt64, startedAt: UInt64) {
        let speed = stateLock.withLock { requestedSpeed }
        let targetNanoseconds: UInt64
        switch speed {
        case .normal:
            targetNanoseconds = frameDuration
        case .multiplier(let value):
            guard value > 0 else { return }
            targetNanoseconds = UInt64(Double(frameDuration) / value)
        case .unlimited:
            return
        }

        let elapsed = DispatchTime.now().uptimeNanoseconds &- startedAt
        guard elapsed < targetNanoseconds else { return }
        let remaining = targetNanoseconds - elapsed
        Thread.sleep(forTimeInterval: Double(remaining) / 1_000_000_000)
    }
}

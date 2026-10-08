import AVFoundation
import EmulationCore
import EmulatorDomain
import Foundation
import GameplayAudio

/// Feeds game sound to an AVAudioSourceNode at SameBoy's configured 48 kHz, through a small
/// buffer that grows when the device can't keep up (`AdaptiveAudioBuffer`).
final class AudioOutputEngine: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var buffer = AdaptiveAudioBuffer()
    private var sourceNode: AVAudioSourceNode?
    /// Plays the game's sound faster along with the game, with the pitch rising with it.
    private let varispeed = AVAudioUnitVarispeed()
    /// Whether sound is dropped instead of played, as while Fast Forward is muted. Guarded by `lock`.
    private var discardsSound = false
    /// Whether gameplay wants sound. A route change or an interruption stops the engine on its own,
    /// and this decides whether to start it again. Touched only on the main queue.
    private var wantsRunning = false
    private var observers: [NSObjectProtocol] = []
    /// Called on the main queue when sound is cut off in a way the player should notice: another
    /// app's audio interrupted the game, or the output device went away, as when headphones come
    /// out. The owner pauses the game, and pausing keeps the engine from starting itself again.
    /// Set and called on the main queue.
    var onDisturbance: (@MainActor () -> Void)?

    /// Sets how game sound relates to the silent switch and other apps' audio. Call before start.
    func apply(_ mode: SoundMode) {
        let session = AVAudioSession.sharedInstance()
        switch mode {
        case .followSilentSwitch:
            // Silenced by the switch, and stops other apps' audio while a game plays.
            try? session.setCategory(.soloAmbient)
        case .alwaysOn:
            try? session.setCategory(.playback)
        case .alwaysOff:
            // Ambient mixes with other apps, so their audio keeps playing; the game is muted.
            try? session.setCategory(.ambient)
        }
        // Ask for short hardware buffers, about 10 ms, to keep latency low.
        try? session.setPreferredIOBufferDuration(0.01)
        engine.mainMixerNode.outputVolume = mode == .alwaysOff ? 0 : 1
    }

    func start() throws {
        wantsRunning = true
        observeSystemChanges()
        guard !engine.isRunning else { return }
        guard sourceNode == nil else {
            try engine.start()
            return
        }
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let source = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard buffers.count >= 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }

            self.lock.lock()
            defer { self.lock.unlock() }
            self.buffer.read(frameCount: Int(frameCount), left: left, right: right)
            return noErr
        }

        sourceNode = source
        engine.attach(source)
        engine.attach(varispeed)
        engine.connect(source, to: varispeed, format: format)
        engine.connect(varispeed, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()
    }

    func enqueue(_ newSamples: [StereoSample]) {
        guard !newSamples.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        guard !discardsSound else { return }
        buffer.write(newSamples)
    }

    /// Matches the sound to the game's speed. Accelerated sound plays at the game's speed, which
    /// the varispeed unit can do from 0.25× to 4×. At other speeds, and when muted, the sound is
    /// dropped so none builds up to play late.
    func setSpeed(_ speed: EmulationSpeed, fastForwardAudio: FastForwardAudio) {
        var rate: Float = 1
        var discards = false
        switch speed {
        case .normal:
            break
        case .multiplier(let multiplier):
            if fastForwardAudio == .accelerated, (0.25...4).contains(multiplier) {
                rate = Float(multiplier)
            } else {
                discards = true
            }
        case .unlimited:
            discards = true
        }
        varispeed.rate = rate
        lock.lock()
        discardsSound = discards
        // Sound buffered at the old speed would play late at the new one.
        buffer.removeAll()
        lock.unlock()
    }

    /// Drops the buffered sound too, so resuming waits for the buffer to fill again rather than
    /// playing what's left and counting the wait for new sound as the device falling behind.
    func pause() {
        wantsRunning = false
        engine.pause()
        lock.lock()
        buffer.removeAll()
        lock.unlock()
    }

    func resume() throws {
        wantsRunning = true
        if !engine.isRunning { try engine.start() }
    }

    func stop() {
        wantsRunning = false
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        engine.stop()
        lock.lock()
        buffer.removeAll()
        lock.unlock()
    }

    /// Headphones, Bluetooth and other route changes reconfigure the engine and stop it, and a call
    /// or Siri interrupts it. Either way it stays silent until started again, unless the game is
    /// still meant to run, as when the scene alone was covered. An interruption that begins or an
    /// output device that goes away also tells the owner, which pauses the game.
    private func observeSystemChanges() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            self?.restartIfWanted()
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            switch raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) {
            case .began:
                // iOS reports a suspension that already ended as an interruption when the app
                // returns. The scene events and Resume Games handled that one.
                let reason = (notification.userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt)
                    .flatMap(AVAudioSession.InterruptionReason.init(rawValue:))
                if reason != .appWasSuspended { self?.notifyDisturbance() }
            case .ended: self?.restartIfWanted()
            default: break
            }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if raw.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:)) == .oldDeviceUnavailable {
                self?.notifyDisturbance()
            }
        })
    }

    /// Runs on the main queue, which the observers above ask for.
    private func notifyDisturbance() {
        MainActor.assumeIsolated { onDisturbance?() }
    }

    private func restartIfWanted() {
        guard wantsRunning, !engine.isRunning else { return }
        try? engine.start()
    }
}

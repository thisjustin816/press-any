import AVFoundation
import EmulationCore
import Foundation

/// Small lock-protected PCM queue feeding an AVAudioSourceNode at SameBoy's configured 48 kHz.
final class AudioOutputEngine: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [StereoSample] = []
    private var readIndex = 0
    private var sourceNode: AVAudioSourceNode?
    private let maximumQueuedFrames = 48_000 / 4 // ~250 ms hard ceiling
    /// Whether gameplay wants sound. A route change or an interruption stops the engine on its own,
    /// and this decides whether to start it again. Touched only on the main queue.
    private var wantsRunning = false
    private var observers: [NSObjectProtocol] = []

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
            for frame in 0..<Int(frameCount) {
                if self.readIndex < self.samples.count {
                    let sample = self.samples[self.readIndex]
                    left[frame] = Float(sample.left) / Float(Int16.max)
                    right[frame] = Float(sample.right) / Float(Int16.max)
                    self.readIndex += 1
                } else {
                    left[frame] = 0
                    right[frame] = 0
                }
            }
            self.compactIfNeededLocked()
            return noErr
        }

        sourceNode = source
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()
    }

    func enqueue(_ newSamples: [StereoSample]) {
        guard !newSamples.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        samples.append(contentsOf: newSamples)
        let unread = samples.count - readIndex
        if unread > maximumQueuedFrames {
            readIndex += unread - maximumQueuedFrames
        }
        compactIfNeededLocked()
    }

    func pause() {
        wantsRunning = false
        engine.pause()
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
        samples.removeAll(keepingCapacity: false)
        readIndex = 0
        lock.unlock()
    }

    /// Headphones, Bluetooth and other route changes reconfigure the engine and stop it, and a call
    /// or Siri interrupts it. Either way it stays silent until started again.
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
            if raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .ended {
                self?.restartIfWanted()
            }
        })
    }

    private func restartIfWanted() {
        guard wantsRunning, !engine.isRunning else { return }
        try? engine.start()
    }

    private func compactIfNeededLocked() {
        guard readIndex > 4096 || readIndex == samples.count else { return }
        samples.removeFirst(readIndex)
        readIndex = 0
    }
}

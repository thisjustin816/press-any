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

    func start() throws {
        guard !engine.isRunning else { return }
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
        engine.pause()
    }

    func resume() throws {
        if !engine.isRunning { try engine.start() }
    }

    func stop() {
        engine.stop()
        lock.lock()
        samples.removeAll(keepingCapacity: false)
        readIndex = 0
        lock.unlock()
    }

    private func compactIfNeededLocked() {
        guard readIndex > 4096 || readIndex == samples.count else { return }
        samples.removeFirst(readIndex)
        readIndex = 0
    }
}

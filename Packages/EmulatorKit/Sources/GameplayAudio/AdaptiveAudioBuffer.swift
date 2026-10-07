import EmulationCore

/// Queues game sound for the audio output, keeping a small buffer that grows when playback runs dry.
///
/// The buffer starts at a low target for responsive play and grows a step each time playback runs
/// out of sound, up to a ceiling, then shrinks a step after a long stretch with no shortfall
/// The game's speed never changes for the sound. Playback waits for the target to fill before it starts, and again after a shortfall, so
/// a device under load gets one short gap instead of a crackle.
///
/// The emulator's clock sets the game's speed, and the output's clock drifts from it. To hold the
/// buffer near its target anyway, playback runs up to half a percent faster or slower, which
/// nobody can hear. The game itself never speeds up or slows down for the sound.
///
/// Not thread-safe: the audio output guards it with a lock. `read` never allocates, so it can run
/// on the real-time audio thread.
public struct AdaptiveAudioBuffer {
    public struct Configuration: Equatable, Sendable {
        public var sampleRate: Int
        /// The starting target, and the lowest it shrinks to, in seconds.
        public var minimumTarget: Double
        public var maximumTarget: Double
        public var targetStep: Double
        /// Seconds of playback with no shortfall before the target shrinks a step.
        public var settleTime: Double
        /// Sound held at most, in seconds. Beyond it the oldest sound is dropped.
        public var capacity: Double
        /// The most playback speeds up or slows down to hold the target, as a fraction.
        public var maximumRateAdjustment: Double

        public init(
            sampleRate: Int = 48_000,
            minimumTarget: Double = 0.040,
            maximumTarget: Double = 0.160,
            targetStep: Double = 0.020,
            settleTime: Double = 30,
            capacity: Double = 0.5,
            maximumRateAdjustment: Double = 0.005
        ) {
            self.sampleRate = sampleRate
            self.minimumTarget = minimumTarget
            self.maximumTarget = maximumTarget
            self.targetStep = targetStep
            self.settleTime = settleTime
            self.capacity = capacity
            self.maximumRateAdjustment = maximumRateAdjustment
        }

        func frames(_ seconds: Double) -> Int { max(1, Int((seconds * Double(sampleRate)).rounded())) }
    }

    private let minimumTargetFrames: Int
    private let maximumTargetFrames: Int
    private let targetStepFrames: Int
    private let settleFrames: Int
    private let maximumRateAdjustment: Double

    private var storage: [StereoSample]
    private var head = 0
    /// How far playback is between the frame at `head` and the next one.
    private var phase = 0.0
    private var playing = false
    private var framesSinceShortfall = 0

    /// Sound waiting to play, in frames.
    public private(set) var bufferedFrames = 0
    /// How much sound playback keeps buffered, in frames.
    public private(set) var targetFrames: Int
    /// How many times playback has run out of sound.
    public private(set) var shortfalls = 0

    public init(configuration: Configuration = .init()) {
        minimumTargetFrames = configuration.frames(configuration.minimumTarget)
        maximumTargetFrames = max(minimumTargetFrames, configuration.frames(configuration.maximumTarget))
        targetStepFrames = configuration.frames(configuration.targetStep)
        settleFrames = configuration.frames(configuration.settleTime)
        maximumRateAdjustment = configuration.maximumRateAdjustment
        targetFrames = minimumTargetFrames
        // Room for three times the largest target, so a burst can be trimmed rather than lost.
        let capacity = max(configuration.frames(configuration.capacity), maximumTargetFrames * 3 + 1)
        storage = Array(repeating: StereoSample(left: 0, right: 0), count: capacity)
    }

    /// Whether playback has filled its target and is playing sound rather than silence.
    public var isPlaying: Bool { playing }

    public mutating func write(_ samples: [StereoSample]) {
        let capacity = storage.count
        for sample in samples {
            if bufferedFrames == capacity { advance(by: 1) }
            storage[(head + bufferedFrames) % capacity] = sample
            bufferedFrames += 1
        }
        // A burst after a stall would only make the sound late. Skip to the newest sound instead.
        if bufferedFrames > targetFrames * 3 {
            advance(by: bufferedFrames - targetFrames)
            phase = 0
        }
    }

    /// Fills `frameCount` frames of each channel with sound scaled to -1...1, or silence while the
    /// buffer fills.
    public mutating func read(frameCount: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        if !playing, bufferedFrames >= targetFrames { playing = true }
        guard playing else {
            silence(left: left, right: right, from: 0, to: frameCount)
            return
        }

        let rate = playbackRate
        let capacity = storage.count
        let scale = Float(Int16.max)
        for frame in 0..<frameCount {
            // Interpolating needs the next frame too.
            guard bufferedFrames >= 2 else {
                runDry()
                silence(left: left, right: right, from: frame, to: frameCount)
                return
            }
            let current = storage[head]
            let next = storage[(head + 1) % capacity]
            let t = Float(phase)
            left[frame] = (Float(current.left) + (Float(next.left) - Float(current.left)) * t) / scale
            right[frame] = (Float(current.right) + (Float(next.right) - Float(current.right)) * t) / scale
            phase += rate
            if phase >= 1 {
                let whole = Int(phase)
                advance(by: whole)
                phase -= Double(whole)
            }
        }

        framesSinceShortfall += frameCount
        if framesSinceShortfall >= settleFrames, targetFrames > minimumTargetFrames {
            targetFrames = max(minimumTargetFrames, targetFrames - targetStepFrames)
            framesSinceShortfall = 0
        }
    }

    /// Drops all buffered sound. The target stays where it grew to.
    public mutating func removeAll() {
        head = 0
        bufferedFrames = 0
        phase = 0
        playing = false
    }

    /// Faster when more than the target is buffered, slower when less, reaching the most it
    /// adjusts at half the target or one and a half times it.
    private var playbackRate: Double {
        let error = Double(bufferedFrames - targetFrames) / Double(targetFrames)
        return 1 + min(maximumRateAdjustment, max(-maximumRateAdjustment, 2 * error * maximumRateAdjustment))
    }

    private mutating func runDry() {
        shortfalls += 1
        playing = false
        framesSinceShortfall = 0
        targetFrames = min(maximumTargetFrames, targetFrames + targetStepFrames)
    }

    private mutating func advance(by frames: Int) {
        let frames = min(frames, bufferedFrames)
        head = (head + frames) % storage.count
        bufferedFrames -= frames
    }

    private func silence(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, from start: Int, to end: Int) {
        guard start < end else { return }
        (left + start).update(repeating: 0, count: end - start)
        (right + start).update(repeating: 0, count: end - start)
    }
}

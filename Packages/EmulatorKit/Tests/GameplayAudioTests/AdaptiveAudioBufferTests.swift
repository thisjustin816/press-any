import EmulationCore
import GameplayAudio
import XCTest

final class AdaptiveAudioBufferTests: XCTestCase {
    /// 1 kHz keeps the frame counts small: the target starts at 40 frames and grows by 20. With no
    /// ramp, sound starts and stops at once, so these tests read exact sample values.
    private let configuration = AdaptiveAudioBuffer.Configuration(
        sampleRate: 1_000,
        minimumTarget: 0.040,
        maximumTarget: 0.100,
        targetStep: 0.020,
        settleTime: 1,
        capacity: 0.5,
        maximumRateAdjustment: 0.005,
        rampTime: 0
    )

    /// The same with a 10-frame ramp.
    private var ramped: AdaptiveAudioBuffer.Configuration {
        var ramped = configuration
        ramped.rampTime = 0.010
        return ramped
    }

    /// A level well above silence: about half of full scale.
    private let level: Int16 = 16_000
    /// The most one ramp frame moves `level`, with a little room for rounding.
    private var rampStep: Float { Float(level) / Float(Int16.max) / 10 + 0.001 }

    private func largestStep(_ output: [Float], after previous: Float? = nil) -> Float {
        let values = (previous.map { [$0] } ?? []) + output
        return zip(values, values.dropFirst()).map { abs($1 - $0) }.max() ?? 0
    }

    func testRunningDryFadesOutInsteadOfDroppingToSilence() {
        var buffer = AdaptiveAudioBuffer(configuration: ramped)
        buffer.write(samples(40, value: level))
        let output = read(&buffer, 60).left
        XCTAssertEqual(buffer.shortfalls, 1)
        XCTAssertLessThanOrEqual(largestStep(output), rampStep, "no step to silence")
        XCTAssertEqual(output.last ?? 1, 0, "silent once the fade ends")
    }

    func testRefillFadesBackIn() {
        var buffer = AdaptiveAudioBuffer(configuration: ramped)
        buffer.write(samples(40, value: level))
        let first = read(&buffer, 60).left
        buffer.write(samples(buffer.targetFrames, value: level))
        let output = read(&buffer, 30).left
        XCTAssertTrue(buffer.isPlaying)
        XCTAssertLessThanOrEqual(largestStep(output, after: first.last), rampStep, "no step back to sound")
        XCTAssertEqual(output.last ?? 0, Float(level) / Float(Int16.max), accuracy: 0.0001, "full level once faded in")
    }

    func testRemoveAllFadesWhatWasPlayingWithoutReplayingIt() {
        var buffer = AdaptiveAudioBuffer(configuration: ramped)
        buffer.write(samples(80, value: level))
        let before = read(&buffer, 20).left
        buffer.removeAll()
        let output = read(&buffer, 20).left
        XCTAssertLessThanOrEqual(largestStep(output, after: before.last), rampStep)
        XCTAssertEqual(output.last ?? 1, 0)
        XCTAssertTrue(zip(output, output.dropFirst()).allSatisfy { $1 <= $0 }, "only fades; no old sound plays again")
    }

    func testRemoveAllWithoutFadeStartsAgainFromSilence() {
        var buffer = AdaptiveAudioBuffer(configuration: ramped)
        buffer.write(samples(80, value: level))
        _ = read(&buffer, 20)
        buffer.removeAll(fadeOut: false)
        XCTAssertEqual(read(&buffer, 5).left, Array(repeating: 0, count: 5))
        buffer.write(samples(buffer.targetFrames, value: level))
        XCTAssertLessThanOrEqual(largestStep(read(&buffer, 20).left, after: 0), rampStep, "fades in from silence")
    }

    func testSkippingAStaleBurstFadesAcrossTheJump() {
        var buffer = AdaptiveAudioBuffer(configuration: ramped)
        buffer.write(samples(40, value: level))
        let before = read(&buffer, 20).left
        // A burst of the opposite level, more than three targets' worth, while playing.
        buffer.write(samples(200, value: -level))
        let output = read(&buffer, 40).left
        XCTAssertLessThanOrEqual(largestStep(output, after: before.last), rampStep, "no jump between the two levels")
        XCTAssertEqual(output.last ?? 0, -Float(level) / Float(Int16.max), accuracy: 0.0001, "the newest sound plays")
    }

    func testStaysSilentUntilTheTargetFills() {
        var buffer = AdaptiveAudioBuffer(configuration: configuration)
        buffer.write(samples(39, value: 1000))
        XCTAssertEqual(read(&buffer, 10).left, Array(repeating: 0, count: 10))
        XCTAssertFalse(buffer.isPlaying)

        buffer.write(samples(1, value: 1000))
        let output = read(&buffer, 10)
        XCTAssertTrue(buffer.isPlaying)
        XCTAssertEqual(output.left.first ?? 0, 1000 / Float(Int16.max), accuracy: 0.0001)
    }

    func testPlaysSamplesInOrderAtTheTarget() {
        var buffer = AdaptiveAudioBuffer(configuration: configuration)
        buffer.write((0..<40).map { StereoSample(left: Int16($0 * 100), right: Int16(-$0 * 100)) })
        let output = read(&buffer, 5)
        // At the target the rate is exactly 1, so each output frame is one input frame.
        for frame in 0..<5 {
            XCTAssertEqual(output.left[frame], Float(frame * 100) / Float(Int16.max), accuracy: 0.0001)
            XCTAssertEqual(output.right[frame], Float(-frame * 100) / Float(Int16.max), accuracy: 0.0001)
        }
        XCTAssertEqual(buffer.bufferedFrames, 35)
    }

    func testRunningDryGrowsTheTargetAndWaitsToRefill() {
        var buffer = AdaptiveAudioBuffer(configuration: configuration)
        buffer.write(samples(40, value: 500))
        let output = read(&buffer, 50)
        XCTAssertEqual(buffer.shortfalls, 1)
        XCTAssertEqual(buffer.targetFrames, 60)
        XCTAssertFalse(buffer.isPlaying)
        XCTAssertEqual(output.left.suffix(11), Array(repeating: 0, count: 11), "silence after the sound runs out")

        // It waits for the new, larger target before playing again.
        buffer.write(samples(50, value: 500))
        _ = read(&buffer, 1)
        XCTAssertFalse(buffer.isPlaying)
        buffer.write(samples(10, value: 500))
        _ = read(&buffer, 1)
        XCTAssertTrue(buffer.isPlaying)
    }

    func testTargetStopsGrowingAtTheMaximum() {
        var buffer = AdaptiveAudioBuffer(configuration: configuration)
        for _ in 0..<10 {
            buffer.write(samples(buffer.targetFrames, value: 1))
            _ = read(&buffer, buffer.targetFrames + 10)
        }
        XCTAssertEqual(buffer.targetFrames, 100)
    }

    func testTargetShrinksAfterSteadyPlayback() {
        var buffer = AdaptiveAudioBuffer(configuration: configuration)
        buffer.write(samples(40, value: 1))
        _ = read(&buffer, 50)
        XCTAssertEqual(buffer.targetFrames, 60)

        // A second of playback with no shortfall, kept fed, shrinks it a step.
        buffer.write(samples(60, value: 1))
        for _ in 0..<100 {
            buffer.write(samples(10, value: 1))
            _ = read(&buffer, 10)
        }
        XCTAssertEqual(buffer.shortfalls, 1)
        XCTAssertEqual(buffer.targetFrames, 40)
    }

    func testPlaysFasterAboveTheTargetAndSlowerBelow() {
        // At 10 kHz the target is 400 frames.
        var finer = configuration
        finer.sampleRate = 10_000

        var above = AdaptiveAudioBuffer(configuration: finer)
        above.write(samples(1000, value: 1))
        _ = read(&above, 600)
        // 600 frames at 0.5% faster play 603 frames of sound, give or take rounding; at the
        // normal rate 400 would be left.
        XCTAssertEqual(above.bufferedFrames, 397, accuracy: 1)

        var below = AdaptiveAudioBuffer(configuration: finer)
        below.write(samples(400, value: 1))
        _ = read(&below, 200)
        XCTAssertEqual(below.bufferedFrames, 200)
        // Half the target left plays 0.5% slower: 150 frames use 149.25 frames of sound.
        _ = read(&below, 150)
        XCTAssertEqual(below.bufferedFrames, 51)
    }

    func testDriftIsAbsorbedWithoutShortfalls() {
        // Three minutes with the emulator 0.3% slower, then 0.3% faster, than the output's clock.
        for drift in [0.997, 1.003] {
            XCTAssertEqual(shortfallsAndDrops(drift: drift, configuration: .init()), 0, "drift \(drift)")
        }
        // Without the rate adjustment the same drift runs dry or overflows.
        var fixedRate = AdaptiveAudioBuffer.Configuration()
        fixedRate.maximumRateAdjustment = 0
        for drift in [0.997, 1.003] {
            XCTAssertGreaterThan(shortfallsAndDrops(drift: drift, configuration: fixedRate), 0, "drift \(drift)")
        }
    }

    /// Plays three minutes of 60 fps game sound, written a video frame at a time and read in
    /// 800-frame callbacks, and counts the shortfalls plus the bursts dropped for running long.
    private func shortfallsAndDrops(drift: Double, configuration: AdaptiveAudioBuffer.Configuration) -> Int {
        var buffer = AdaptiveAudioBuffer(configuration: configuration)
        var produced = 0.0
        buffer.write(samples(buffer.targetFrames, value: 1))
        for _ in 0..<(60 * 60 * 3) {
            produced += 800 * drift
            let whole = Int(produced)
            produced -= Double(whole)
            buffer.write(samples(whole, value: 1))
            _ = read(&buffer, 800)
        }
        return buffer.shortfalls + buffer.skippedBursts
    }

    func testDropsAStaleBurstDownToTheTarget() {
        var buffer = AdaptiveAudioBuffer(configuration: configuration)
        buffer.write((0..<200).map { StereoSample(left: Int16($0), right: 0) })
        XCTAssertEqual(buffer.bufferedFrames, 40)
        let output = read(&buffer, 1)
        XCTAssertEqual(output.left[0], 160 / Float(Int16.max), accuracy: 0.0001, "the newest sound plays")
    }

    func testRemoveAllKeepsTheGrownTarget() {
        var buffer = AdaptiveAudioBuffer(configuration: configuration)
        buffer.write(samples(40, value: 1))
        _ = read(&buffer, 50)
        buffer.write(samples(30, value: 1))
        buffer.removeAll()
        XCTAssertEqual(buffer.bufferedFrames, 0)
        XCTAssertFalse(buffer.isPlaying)
        XCTAssertEqual(buffer.targetFrames, 60)
    }

    private func samples(_ count: Int, value: Int16) -> [StereoSample] {
        Array(repeating: StereoSample(left: value, right: value), count: count)
    }

    private func read(_ buffer: inout AdaptiveAudioBuffer, _ count: Int) -> (left: [Float], right: [Float]) {
        var left = Array(repeating: Float.nan, count: count)
        var right = Array(repeating: Float.nan, count: count)
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                if let lp = l.baseAddress, let rp = r.baseAddress {
                    buffer.read(frameCount: count, left: lp, right: rp)
                }
            }
        }
        return (left, right)
    }
}

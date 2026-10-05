import EmulationCore
import GameplayAudio
import XCTest

final class AdaptiveAudioBufferTests: XCTestCase {
    /// 1 kHz keeps the frame counts small: the target starts at 40 frames and grows by 20.
    private let configuration = AdaptiveAudioBuffer.Configuration(
        sampleRate: 1_000,
        minimumTarget: 0.040,
        maximumTarget: 0.100,
        targetStep: 0.020,
        settleTime: 1,
        capacity: 0.5,
        maximumRateAdjustment: 0.005
    )

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
        var drops = 0
        buffer.write(samples(buffer.targetFrames, value: 1))
        for _ in 0..<(60 * 60 * 3) {
            produced += 800 * drift
            let whole = Int(produced)
            produced -= Double(whole)
            let before = buffer.bufferedFrames
            buffer.write(samples(whole, value: 1))
            if buffer.bufferedFrames < before + whole { drops += 1 }
            _ = read(&buffer, 800)
        }
        return buffer.shortfalls + drops
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

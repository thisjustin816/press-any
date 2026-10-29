import EmulationCore
import EmulationSession
import Foundation
import XCTest

final class PlaytimeClockTests: XCTestCase {
    private let frame: UInt64 = 16_742_706

    func testNormalSpeedCountsTheEmulatedTimeHoweverLateFramesRun() {
        let uptime = FakeUptime()
        var clock = PlaytimeClock(uptime: uptime.read)
        clock.ranFrame(lasting: frame)
        uptime.advance(by: 1_000_000_000)
        clock.ranFrame(lasting: frame)
        XCTAssertEqual(clock.nanoseconds, 2 * frame)
    }

    func testFastForwardCountsRealTimeBetweenFrames() {
        let uptime = FakeUptime()
        var clock = PlaytimeClock(uptime: uptime.read)
        clock.setSpeed(.multiplier(4))
        clock.ranFrame(lasting: frame)
        for _ in 0..<8 {
            uptime.advance(by: frame / 4)
            clock.ranFrame(lasting: frame)
        }
        XCTAssertEqual(clock.nanoseconds, frame + 8 * (frame / 4))
    }

    func testSlowMotionCountsTheLongerRealTimeOfEachFrame() {
        let uptime = FakeUptime()
        var clock = PlaytimeClock(uptime: uptime.read)
        clock.setSpeed(.multiplier(0.5))
        clock.ranFrame(lasting: frame)
        for _ in 0..<4 {
            uptime.advance(by: frame * 2)
            clock.ranFrame(lasting: frame)
        }
        XCTAssertEqual(clock.nanoseconds, frame + 8 * frame)
        uptime.advance(by: 60_000_000_000)
        clock.ranFrame(lasting: frame)
        XCTAssertEqual(clock.nanoseconds, frame + 10 * frame, "a pause adds at most one slowed frame")
    }

    func testUnlimitedCountsRealTimeAndAPauseAddsAtMostOneFrame() {
        let uptime = FakeUptime()
        var clock = PlaytimeClock(uptime: uptime.read)
        clock.setSpeed(.unlimited)
        clock.ranFrame(lasting: frame)
        uptime.advance(by: 1_000_000)
        clock.ranFrame(lasting: frame)
        XCTAssertEqual(clock.nanoseconds, frame + 1_000_000)
        uptime.advance(by: 60_000_000_000)
        clock.ranFrame(lasting: frame)
        XCTAssertEqual(clock.nanoseconds, 2 * frame + 1_000_000, "time paused between frames isn't play")
    }

    func testResetStartsOverAtTheSameSpeed() {
        let uptime = FakeUptime()
        var clock = PlaytimeClock(uptime: uptime.read)
        clock.setSpeed(.unlimited)
        clock.ranFrame(lasting: frame)
        clock.reset()
        XCTAssertEqual(clock.nanoseconds, 0)
        clock.ranFrame(lasting: frame)
        uptime.advance(by: 2_000_000)
        clock.ranFrame(lasting: frame)
        XCTAssertEqual(clock.nanoseconds, frame + 2_000_000)
    }
}

final class FakeUptime: @unchecked Sendable {
    private let lock = NSLock()
    private var nanoseconds: UInt64 = 1_000_000_000

    var read: @Sendable () -> UInt64 { { [self] in lock.withLock { nanoseconds } } }

    func advance(by delta: UInt64) {
        lock.withLock { nanoseconds &+= delta }
    }
}

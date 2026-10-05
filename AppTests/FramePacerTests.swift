import XCTest
@testable import PressAny

final class FramePacerTests: XCTestCase {
    private let frame: UInt64 = 16_000_000

    func testWaitsForTheRestOfTheFrame() {
        var pacer = FramePacer(start: 0)
        XCTAssertEqual(pacer.delay(afterFrameLasting: frame, now: 4_000_000), 12_000_000)
    }

    func testOversleepIsMadeUpOnTheNextFrame() {
        var pacer = FramePacer(start: 0)
        _ = pacer.delay(afterFrameLasting: frame, now: 4_000_000)
        // The sleep ran 1 ms long, and the next frame took 4 ms: it waits only to its own deadline.
        XCTAssertEqual(pacer.delay(afterFrameLasting: frame, now: 21_000_000), 11_000_000)
    }

    func testRunsLateFramesBackToBackToCatchUp() {
        var pacer = FramePacer(start: 0)
        XCTAssertEqual(pacer.delay(afterFrameLasting: frame, now: 20_000_000), 0)
        // The schedule is kept, so the next frame waits only until 32 ms.
        XCTAssertEqual(pacer.delay(afterFrameLasting: frame, now: 25_000_000), 7_000_000)
    }

    func testAStallStartsANewSchedule() {
        var pacer = FramePacer(start: 0)
        // Far more than four frames late: no racing to catch up.
        XCTAssertEqual(pacer.delay(afterFrameLasting: frame, now: 200_000_000), 0)
        XCTAssertEqual(pacer.delay(afterFrameLasting: frame, now: 204_000_000), 12_000_000)
    }

    func testUnlimitedSpeedNeverWaitsAndNormalSpeedResumesFromNow() {
        var pacer = FramePacer(start: 0)
        XCTAssertEqual(pacer.delay(afterFrameLasting: 0, now: 1_000_000), 0)
        XCTAssertEqual(pacer.delay(afterFrameLasting: 0, now: 2_000_000), 0)
        XCTAssertEqual(pacer.delay(afterFrameLasting: frame, now: 3_000_000), 15_000_000)
    }

    func testAverageRateMatchesTheFrameLengthDespiteOversleeping() {
        var pacer = FramePacer(start: 0)
        var now: UInt64 = 0
        for _ in 0..<600 {
            now += 3_000_000 // running the frame
            now += pacer.delay(afterFrameLasting: frame, now: now) + 300_000 // sleeping, 0.3 ms long
        }
        // 600 frames end within one oversleep of 9.6 s, not 180 ms late.
        XCTAssertLessThanOrEqual(now, 600 * frame + 300_000)
    }
}

import XCTest
@testable import PressAny

final class FrameSchedulerTests: XCTestCase {
    /// A Game Boy frame, and a 60 Hz refresh.
    private let frame: UInt64 = 16_742_706
    private let refresh: UInt64 = 16_666_667

    func testTheFirstRefreshShowsAFrame() {
        var scheduler = FrameScheduler()
        XCTAssertTrue(scheduler.isFrameDue)
        scheduler.ranFrame(lasting: frame)
        XCTAssertFalse(scheduler.isFrameDue)
    }

    func testAt60HzEachRefreshShowsOneFrameExceptForAnOccasionalRepeat() {
        var scheduler = FrameScheduler()
        scheduler.ranFrame(lasting: frame)
        var counts: [Int: Int] = [:]
        for _ in 0..<600 {
            scheduler.addRefresh(lasting: refresh)
            var ran = 0
            while scheduler.isFrameDue {
                scheduler.ranFrame(lasting: frame)
                ran += 1
            }
            counts[ran, default: 0] += 1
        }
        // Ten seconds: never two frames in one refresh, and two or three repeated refreshes.
        XCTAssertNil(counts[2])
        XCTAssertEqual(counts[0, default: 0] + counts[1, default: 0], 600)
        XCTAssertTrue((2...3).contains(counts[0, default: 0]), "\(counts)")
    }

    func testTheGameKeepsItsNativeRateOverTime() {
        var scheduler = FrameScheduler()
        scheduler.ranFrame(lasting: frame)
        var frames: UInt64 = 1
        for _ in 0..<7200 {
            scheduler.addRefresh(lasting: refresh / 2) // 120 Hz
            while scheduler.isFrameDue {
                scheduler.ranFrame(lasting: frame)
                frames += 1
            }
        }
        // One minute of refreshes runs a minute of Game Boy frames, give or take one.
        let expected = (7200 * (refresh / 2)) / frame
        XCTAssertLessThanOrEqual(abs(Int64(frames) - Int64(expected) - 1), 1)
    }

    func testFastForwardRunsSeveralFramesPerRefresh() {
        var scheduler = FrameScheduler()
        scheduler.ranFrame(lasting: frame)
        scheduler.addRefresh(lasting: refresh, speed: 3)
        var ran = 0
        while scheduler.isFrameDue {
            scheduler.ranFrame(lasting: frame)
            ran += 1
        }
        XCTAssertEqual(ran, 2) // 3 x 16.67 ms owed is less than three whole frames
    }

    func testAStallCountsAsOneFrameInsteadOfCatchingUp() {
        var scheduler = FrameScheduler()
        scheduler.ranFrame(lasting: frame)
        scheduler.addRefresh(lasting: 500_000_000)
        var ran = 0
        while scheduler.isFrameDue {
            scheduler.ranFrame(lasting: frame)
            ran += 1
        }
        XCTAssertEqual(ran, 1)
    }
}

import EmulationCore
import XCTest
@testable import PressAny

final class ScreenshotInputTests: XCTestCase {
    private let none = EmulatorInputState()

    func testWaitsTapsAndHoldsBecomeFrames() throws {
        let input = try ScreenshotInput("0.5 start a:1 right+b")
        let wait = 30, held = 60, tap = ScreenshotInput.tapFrames, release = ScreenshotInput.releaseFrames
        XCTAssertEqual(input.frames.count, wait + (tap + release) + (held + release) + (tap + release))

        var start = EmulatorInputState()
        start.start = true
        var a = EmulatorInputState()
        a.a = true
        var rightB = EmulatorInputState()
        rightB.right = true
        rightB.b = true
        let expected = Array(repeating: none, count: wait)
            + Array(repeating: start, count: tap) + Array(repeating: none, count: release)
            + Array(repeating: a, count: held) + Array(repeating: none, count: release)
            + Array(repeating: rightB, count: tap) + Array(repeating: none, count: release)
        XCTAssertEqual(input.frames, expected)
    }

    func testSecondsAreGameBoyFrames() throws {
        XCTAssertEqual(try ScreenshotInput("10").frames.count, 597)
        XCTAssertEqual(try ScreenshotInput("  ").frames.count, 0)
        XCTAssertEqual(try ScreenshotInput("UP:0").frames.first?.up, true)
    }

    func testRejectsWhatIsntInTheGrammar() {
        for script in ["jump", "a:", "a:soon", "+a", "a+", "-1", "a:-1", "nan"] {
            XCTAssertThrowsError(try ScreenshotInput("1 \(script) a"), script) { error in
                XCTAssertEqual(error as? ScreenshotInput.ParseError, ScreenshotInput.ParseError(token: script))
            }
        }
    }

    func testPlayerHoldsNothingAfterTheScriptAndReportsTheEndOnce() throws {
        let finished = Counter()
        let player = ScreenshotInputPlayer(try ScreenshotInput("a")) { finished.add() }
        let frames = (0..<20).map { _ in player.advance() }
        XCTAssertTrue(frames[0].a)
        XCTAssertEqual(Array(frames[(ScreenshotInput.tapFrames + ScreenshotInput.releaseFrames)...]),
                       Array(repeating: none, count: 20 - ScreenshotInput.tapFrames - ScreenshotInput.releaseFrames))
        XCTAssertEqual(finished.value, 1)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func add() { lock.withLock { count += 1 } }
}

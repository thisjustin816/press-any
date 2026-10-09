import EmulationCore
import GameplayInput
import XCTest

final class GamepadResumeInputTests: XCTestCase {
    func testEveryGameBoyButtonResumesAndStaysConsumedUntilReleased() {
        for press in [EmulatorInputState(a: true), .init(b: true), .init(start: true), .init(select: true),
                      .init(a: true, b: true, start: true, select: true)] {
            var resume = GamepadResumeInput()
            let result = resume.update(press, canResume: true)
            XCTAssertTrue(result.shouldResume)
            XCTAssertEqual(result.input, .init())
            let held = resume.update(press, canResume: false)
            XCTAssertFalse(held.shouldResume)
            XCTAssertEqual(held.input, .init())
            _ = resume.update(.init(), canResume: false)
            XCTAssertEqual(resume.update(press, canResume: false).input, press)
        }
    }

    func testHoldingAButtonBeforeTheOverlayDoesNotResume() {
        var resume = GamepadResumeInput()
        XCTAssertFalse(resume.update(.init(a: true), canResume: false).shouldResume)
        XCTAssertFalse(resume.update(.init(right: true, a: true), canResume: true).shouldResume)
        _ = resume.update(.init(), canResume: true)
        XCTAssertTrue(resume.update(.init(a: true), canResume: true).shouldResume)
    }

    func testPressingWhileBlockedRequiresReleaseBeforeResume() {
        var resume = GamepadResumeInput()
        XCTAssertFalse(resume.update(.init(start: true), canResume: false).shouldResume)
        XCTAssertFalse(resume.update(.init(start: true), canResume: true).shouldResume)
        _ = resume.update(.init(), canResume: true)
        XCTAssertTrue(resume.update(.init(start: true), canResume: true).shouldResume)
    }

    func testDirectionsDoNotResumeAndPassThrough() {
        var resume = GamepadResumeInput()
        let others = EmulatorInputState(up: true, right: true)
        let result = resume.update(others, canResume: true)
        XCTAssertFalse(result.shouldResume)
        XCTAssertEqual(result.input, others)
        let withA = EmulatorInputState(up: true, right: true, a: true, b: true, select: true)
        let resumed = resume.update(withA, canResume: true)
        XCTAssertTrue(resumed.shouldResume)
        XCTAssertEqual(resumed.input, others)
    }

    func testFreshStartResumesWhileAIsAlreadyHeld() {
        var resume = GamepadResumeInput()
        _ = resume.update(.init(a: true), canResume: false)
        let result = resume.update(.init(a: true, start: true), canResume: true)
        XCTAssertTrue(result.shouldResume)
        XCTAssertEqual(result.input, .init())
    }
}

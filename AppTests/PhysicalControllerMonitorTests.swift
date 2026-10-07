import EmulationCore
import GameController
import XCTest
@testable import PressAny

@MainActor
final class PhysicalControllerMonitorTests: XCTestCase {
    func testTheAppDeclaresExtendedGamepadSupportForSystemCustomizations() throws {
        let bundle = Bundle(for: GameplayViewController.self)
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "GCSupportsControllerUserInteraction") as? Bool, true)
        let profiles = try XCTUnwrap(bundle.object(forInfoDictionaryKey: "GCSupportedGameControllers") as? [[String: String]])
        XCTAssertTrue(profiles.contains { $0["ProfileName"] == "ExtendedGamepad" })
    }

    func testLogicalRightAndBottomButtonsMapToGameBoyAAndB() throws {
        try assertInput(.init(a: true)) { $0.buttonB.setValue(1) }
        try assertInput(.init(b: true)) { $0.buttonA.setValue(1) }
        try assertInput(.init(a: true, b: true)) {
            $0.buttonB.setValue(1)
            $0.buttonA.setValue(1)
        }
    }

    func testTheStickAndDpadBothReachGameplay() throws {
        try assertInput(.init(up: true, right: true)) { $0.leftThumbstick.setValueForXAxis(0.8, yAxis: 0.8) }
        try assertInput(.init(up: true, left: true)) {
            $0.leftThumbstick.setValueForXAxis(-1, yAxis: 0)
            $0.dpad.setValueForXAxis(0, yAxis: 1)
        }
        try assertInput(.init()) { $0.leftThumbstick.setValueForXAxis(0.1, yAxis: 0.1) }
    }

    func testMenuOptionsAndLeftShoulderKeepStartAndSelect() throws {
        try assertInput(.init(start: true)) { $0.buttonMenu.setValue(1) }
        try assertInput(.init(select: true)) { try XCTUnwrap($0.buttonOptions).setValue(1) }
        try assertInput(.init(select: true)) { $0.leftShoulder.setValue(1) }
    }

    func testQueuedInputFromADisconnectedControllerCannotPressAButtonAgain() throws {
        let monitor = PhysicalControllerMonitor(connectedControllers: { [] })
        let controller = GCController.withExtendedGamepad()
        let pad = try XCTUnwrap(controller.extendedGamepad)
        var lastInput: EmulatorInputState?
        var publications = 0
        monitor.onInputChanged = {
            lastInput = $0
            publications += 1
        }
        monitor.selectPlayerOne(controller)
        pad.buttonB.setValue(1)
        try XCTUnwrap(pad.valueChangedHandler)(pad, pad.buttonB)
        NotificationCenter.default.post(name: .GCControllerDidDisconnect, object: controller)
        let releasedPublications = publications

        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertFalse(monitor.isConnected)
        XCTAssertEqual(lastInput, .init())
        XCTAssertEqual(publications, releasedPublications)
    }

    func testDisconnectDoesNotReattachTheControllerStillInTheDiscoveryList() {
        let controller = GCController.withExtendedGamepad()
        let monitor = PhysicalControllerMonitor(connectedControllers: { [controller] })
        XCTAssertTrue(monitor.activeController === controller)

        NotificationCenter.default.post(name: .GCControllerDidDisconnect, object: controller)

        XCTAssertNil(monitor.activeController)
    }

    func testDisconnectUsesAnotherControllerFromTheDiscoveryList() throws {
        let old = GCController.withExtendedGamepad()
        let replacement = GCController.withExtendedGamepad()
        try XCTUnwrap(replacement.extendedGamepad).buttonB.setValue(1)
        let monitor = PhysicalControllerMonitor(connectedControllers: { [old, replacement] })
        var lastInput: EmulatorInputState?
        monitor.onInputChanged = { lastInput = $0 }

        NotificationCenter.default.post(name: .GCControllerDidDisconnect, object: old)

        XCTAssertTrue(monitor.activeController === replacement)
        XCTAssertEqual(lastInput, .init(a: true))
    }

    private func assertInput(
        _ expected: EmulatorInputState,
        file: StaticString = #filePath,
        line: UInt = #line,
        configure: (GCExtendedGamepad) throws -> Void
    ) throws {
        let controller = GCController.withExtendedGamepad()
        try configure(XCTUnwrap(controller.extendedGamepad))
        let monitor = PhysicalControllerMonitor(connectedControllers: { [] })
        var input: EmulatorInputState?
        monitor.onInputChanged = { input = $0 }
        monitor.selectPlayerOne(controller)
        XCTAssertEqual(input, expected, file: file, line: line)
    }
}

import EmulationCore
import Foundation
import XCTest
@testable import PressAny

@MainActor
final class GameplayCameraTests: XCTestCase {
    private func frame(_ byte: UInt8 = 42) throws -> CameraFrame {
        try CameraFrame(luminance: Data(repeating: byte, count: 128 * 112))
    }

    func testCaptureIsOptInAndPausesWithGameplay() async throws {
        let source = CameraSourceDouble()
        let camera = GameplayCamera(source: source)
        camera.setRunning(true, rotationAngle: 90)
        XCTAssertEqual(source.requests, 0)
        XCTAssertTrue(source.starts.isEmpty)
        await camera.select(.rear)?.value
        XCTAssertEqual(source.requests, 1)
        XCTAssertEqual(source.starts, [.rear])
        let oldReceive = try XCTUnwrap(source.receive)
        oldReceive(try frame())
        XCTAssertEqual(camera.frames.current, try frame())
        camera.setRunning(false, rotationAngle: 90)
        XCTAssertNil(camera.frames.current)
        oldReceive(try frame(100))
        XCTAssertNil(camera.frames.current, "a queued sample cannot refill a paused camera")
        camera.setRunning(true, rotationAngle: 90)
        XCTAssertEqual(source.starts, [.rear, .rear])
        XCTAssertEqual(source.requests, 1, "resuming never requests access")
        oldReceive(try frame())
        XCTAssertNil(camera.frames.current, "a previous capture cannot refill a new one")
        camera.select(nil)
        XCTAssertNil(camera.position)
        XCTAssertNil(camera.frames.current)
        XCTAssertEqual(source.stops, 2)
    }

    func testChoosingACameraWhilePausedWaitsForResumeAndCanSwitchOrRotate() async throws {
        let source = CameraSourceDouble()
        let camera = GameplayCamera(source: source)
        await camera.select(.front)?.value
        XCTAssertEqual(camera.position, .front)
        XCTAssertTrue(source.starts.isEmpty)
        camera.setRunning(true, rotationAngle: 90)
        let oldReceive = try XCTUnwrap(source.receive)
        camera.setRunning(true, rotationAngle: 0)
        XCTAssertEqual(source.angles, [90, 0])
        oldReceive(try frame())
        XCTAssertNil(camera.frames.current)
        await camera.select(.rear)?.value
        XCTAssertEqual(source.starts, [.front, .front, .rear])
        camera.close()
        XCTAssertNil(camera.position)
        XCTAssertEqual(source.stops, 3)
    }

    func testDeniedAccessLeavesCameraOffAndExplainsSettings() async {
        let source = CameraSourceDouble()
        source.allowed = false
        let camera = GameplayCamera(source: source)
        var errors: [String] = []
        camera.onError = { errors.append($0) }
        camera.setRunning(true, rotationAngle: 90)
        await camera.select(.rear)?.value
        XCTAssertNil(camera.position)
        XCTAssertTrue(source.starts.isEmpty)
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors[0].contains("Settings"))
    }

    func testLatePermissionReplyCannotReopenAClosedOrTurnedOffCamera() async throws {
        for close in [false, true] {
            let source = CameraSourceDouble()
            source.allowed = nil
            let camera = GameplayCamera(source: source)
            camera.setRunning(true, rotationAngle: 90)
            let selection = try XCTUnwrap(camera.select(.rear))
            await source.waitUntilRequested()
            if close { camera.close() } else { camera.select(nil) }
            source.permissionReply?.resume(returning: true)
            await selection.value
            XCTAssertNil(camera.position)
            XCTAssertTrue(source.starts.isEmpty)
        }
    }

    func testFailureTurnsCaptureOffAndIgnoresFramesStillInFlight() async throws {
        let source = CameraSourceDouble()
        let camera = GameplayCamera(source: source)
        var reports = 0
        camera.onError = { _ in reports += 1 }
        camera.setRunning(true, rotationAngle: 90)
        await camera.select(.rear)?.value
        let receive = try XCTUnwrap(source.receive)
        source.failure?()
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while reports == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertEqual(reports, 1)
        XCTAssertNil(camera.position)
        receive(try frame())
        XCTAssertNil(camera.frames.current)
        XCTAssertEqual(source.stops, 1)
    }
}

@MainActor
private final class CameraSourceDouble: GameplayCameraSource {
    var allowed: Bool? = true
    var requests = 0
    var starts: [GameplayCameraPosition] = []
    var angles: [Double] = []
    var stops = 0
    var receive: (@Sendable (CameraFrame) -> Void)?
    var failure: (@Sendable () -> Void)?
    var permissionReply: CheckedContinuation<Bool, Never>?
    private var requested: CheckedContinuation<Void, Never>?

    func requestAccess() async -> Bool {
        requests += 1
        if let allowed { return allowed }
        return await withCheckedContinuation {
            permissionReply = $0
            requested?.resume()
            requested = nil
        }
    }

    func waitUntilRequested() async {
        if permissionReply != nil { return }
        await withCheckedContinuation { requested = $0 }
    }

    func start(
        position: GameplayCameraPosition, rotationAngle: Double,
        receive: @escaping @Sendable (CameraFrame) -> Void,
        failure: @escaping @Sendable () -> Void
    ) {
        starts.append(position)
        angles.append(rotationAngle)
        self.receive = receive
        self.failure = failure
    }

    func stop() { stops += 1 }
}

final class CameraFrameSamplerTests: XCTestCase {
    func testCenterCropKeepsPixelOrderAndIgnoresRowPadding() throws {
        let stride = 1040
        var bytes = Data(repeating: 255, count: stride * 112)
        for y in 0..<112 {
            for x in 0..<256 {
                let at = y * stride + x * 4
                bytes[at] = 7
                bytes[at + 1] = 128
                bytes[at + 2] = UInt8((x + y) % 256)
                bytes[at + 3] = 0
            }
        }
        let frame = try bytes.withUnsafeBytes {
            try CameraFrameSampler.sampleBGRA($0, width: 256, height: 112, bytesPerRow: stride)
        }
        XCTAssertEqual(frame.rgb888.count, 128 * 112 * 3)
        XCTAssertEqual(Array(frame.rgb888.prefix(3)), [64, 128, 7])
        XCTAssertEqual(frame.rgb888[127 * 3], 191)
        XCTAssertEqual(frame.rgb888[128 * 3], 65)
        XCTAssertEqual(frame.rgb888[(128 * 112 - 1) * 3], UInt8((191 + 111) % 256))
    }

    func testSmallSensorInputScalesUpWithoutChangingLuminance() throws {
        let frame = try Data(repeating: 76, count: 16 * 14 * 4).withUnsafeBytes {
            try CameraFrameSampler.sampleBGRA($0, width: 16, height: 14, bytesPerRow: 16 * 4)
        }
        XCTAssertEqual(frame.rgb888, Data(repeating: 76, count: 128 * 112 * 3))
    }

    func testInvalidDimensionsAndIncompleteBuffersAreRefused() throws {
        for (width, height, stride) in [(0, 112, 512), (128, 0, 512), (128, 112, 0), (128, 112, 511), (128, 113, 512)] {
            try Data(count: 128 * 112 * 4).withUnsafeBytes { bytes in
                XCTAssertThrowsError(try CameraFrameSampler.sampleBGRA(bytes, width: width, height: height, bytesPerRow: stride))
            }
        }
    }
}

import EmulationCore
import EmulatorKitTestSupport
import Foundation
import XCTest
@testable import SameBoyAdapter

final class SameBoyCameraTests: XCTestCase {
    func testSensorFramesRequireExactly128By112LuminanceBytes() throws {
        let bytes = Data(repeating: 128, count: 128 * 112)
        XCTAssertEqual(try CameraFrame(luminance: bytes).rgb888, Data(repeating: 128, count: 128 * 112 * 3))
        for size in [0, 128 * 112 - 1, 128 * 112 + 1] {
            XCTAssertThrowsError(try CameraFrame(luminance: Data(count: size)))
        }
    }

    func testColorSensorFramesPreserveAllThreeChannels() throws {
        let bytes = Data((0..<128 * 112).flatMap { _ in [UInt8(255), 0, 128] })
        XCTAssertEqual(try CameraFrame(rgb888: bytes).rgb888, bytes)
        for size in [0, bytes.count - 1, bytes.count + 1] {
            XCTAssertThrowsError(try CameraFrame(rgb888: Data(count: size)))
        }
    }

    func testCameraAvailabilityFollowsTheLoadedCartridgeAndHardware() throws {
        try SameBoyAdapterTests.requireGeneratedBootROMs()
        let core = SameBoyAdapter()
        let opaque: any EmulatorCore = core
        let camera = try XCTUnwrap(opaque as? any CameraCapability)
        XCTAssertFalse(camera.hasCamera)
        let image = TestROM.make(title: "CAMERA", cartridgeType: 0xfc, ramSizeCode: 4)
        try core.loadImage(image, system: .gameBoy)
        XCTAssertTrue(camera.hasCamera)
        camera.setCameraFrame(try CameraFrame(luminance: Data(repeating: 200, count: 128 * 112)))
        try core.reset()
        XCTAssertTrue(camera.hasCamera)
        try core.setHardwareModel(.gameBoyColor)
        XCTAssertTrue(camera.hasCamera)
        camera.setCameraFrame(nil)
        try core.loadImage(TestROM.make(title: "PLAIN"), system: .gameBoy)
        XCTAssertFalse(camera.hasCamera)
    }
}

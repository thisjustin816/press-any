import EmulationCore
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import XCTest
@testable import SameBoyAdapter

final class SameBoyAdapterTests: XCTestCase {
    func testSameBoyFactoryReportsPinnedDescriptor() {
        let factory = SameBoyCoreFactory()

        XCTAssertEqual(factory.descriptor.identifier, "sameboy")
        XCTAssertEqual(factory.descriptor.version, "1.0.3")
        XCTAssertEqual(factory.supportedSystems, [.gameBoy, .gameBoyColor])
    }

    // These run the real boot ROMs, which `make bootroms` generates. They skip only when the ROMs
    // were never generated; generated ROMs that the bundle can't find are a failure.
    func testSkippingBootReachesTheGameAndFramesKeepRealTime() throws {
        try Self.requireGeneratedBootROMs()
        for system in [GameSystem.gameBoy, .gameBoyColor] {
            let core = SameBoyAdapter()
            try core.loadImage(TestROM.make(title: "BOOTSKIP"), system: system)

            XCTAssertTrue(try core.skipBootAnimation(), "\(system)")
            XCTAssertTrue(core.drainAudio(maxFrames: 64).isEmpty, "the boot chime is dropped")

            // The boot hands off mid-frame, so the first frame is partial. A whole frame is 70224
            // cycles at 4194304 Hz; GameplayDriver paces by this figure.
            _ = try core.runFrame(input: .init())
            let frame = try core.runFrame(input: .init())
            XCTAssertEqual(Double(frame.emulatedNanoseconds), 16_742_706, accuracy: 50_000, "\(system)")
        }
    }

    func testBootIsNotSkippedTwice() throws {
        try Self.requireGeneratedBootROMs()
        let core = SameBoyAdapter()
        try core.loadImage(TestROM.make(title: "BOOTSKIP"), system: .gameBoyColor)
        XCTAssertTrue(try core.skipBootAnimation())
        XCTAssertTrue(try core.skipBootAnimation(), "an already finished boot reports finished")
    }

    private static func requireGeneratedBootROMs() throws {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Sources/SameBoyAdapter/Resources/BootROMs")
        for name in ["dmg_boot.bin", "cgb_boot.bin", "cgb_boot_fast.bin"] {
            let path = directory.appendingPathComponent(name).standardizedFileURL.path
            guard FileManager.default.fileExists(atPath: path) else {
                throw XCTSkip("\(name) is not generated; run make bootroms")
            }
        }
    }

}

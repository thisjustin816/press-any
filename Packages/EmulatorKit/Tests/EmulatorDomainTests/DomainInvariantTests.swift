import XCTest
@testable import EmulatorDomain

final class DomainInvariantTests: XCTestCase {
    func testLaunchContextDistinguishesSameSaveAcrossDifferentBuilds() {
        let game = UUID()
        let save = UUID()
        let a = LaunchContext(gameID: game, buildID: UUID(), saveProfileID: save)
        let b = LaunchContext(gameID: game, buildID: UUID(), saveProfileID: save)
        XCTAssertNotEqual(a, b)
    }

    func testSourceAndCacheStorageClassesAreDistinct() {
        XCTAssertNotEqual(ManagedAssetStorageClass.source, .cache)
    }

    func testToolchainConfidenceCountsTheComponentsOwnSignatures() {
        func component(signatures: Int) -> DetectedToolchainComponent {
            DetectedToolchainComponent(
                kind: .toolchain,
                name: "GBDK",
                version: nil,
                evidence: (0..<signatures).map { ToolchainEvidence(signature: "sig_\($0)", offset: $0) }
            )
        }
        XCTAssertEqual(component(signatures: 0).confidence, .low)
        XCTAssertEqual(component(signatures: 1).confidence, .medium)
        XCTAssertEqual(component(signatures: 3).confidence, .high)
    }

    func testFrameBlendingWeightsSumToOneAndSkipFramesNotYetHeld() {
        XCTAssertEqual(FrameBlending.off.weights(heldFrames: 3), [1, 0, 0])
        XCTAssertEqual(FrameBlending.blend.weights(heldFrames: 3), [0.5, 0.5, 0])
        XCTAssertEqual(FrameBlending.ghosting.weights(heldFrames: 3), [0.5, 0.3, 0.2])
        // Just after a start, only the newest frame is real.
        XCTAssertEqual(FrameBlending.blend.weights(heldFrames: 1), [1, 0, 0])
        XCTAssertEqual(FrameBlending.ghosting.weights(heldFrames: 0), [1, 0, 0])
        let two = FrameBlending.ghosting.weights(heldFrames: 2)
        XCTAssertEqual(two[0], 0.625, accuracy: 1e-9)
        XCTAssertEqual(two[1], 0.375, accuracy: 1e-9)
        XCTAssertEqual(two[2], 0)
        for mode in FrameBlending.allCases {
            for held in 0...4 {
                XCTAssertEqual(mode.weights(heldFrames: held).reduce(0, +), 1, accuracy: 1e-9)
            }
        }
    }
}

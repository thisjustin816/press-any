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
}

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
}

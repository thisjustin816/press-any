import EmulatorDomain
import Foundation
import XCTest
@testable import PressAny

final class GameDetailBuildOrderTests: XCTestCase {
    private func build(_ name: String, version: String? = nil, base: Bool = false, addedDaysAgo: Double = 0) -> Build {
        let added = Date(timeIntervalSince1970: 1_800_000_000 - addedDaysAgo * 86_400)
        return Build(id: UUID(), gameID: UUID(), system: .gameBoy, displayName: name, imageAssetID: UUID(),
            imageSHA256: name, sourceKind: .importedImage, isBase: base, versionString: version,
            versionSortKey: Build.versionSortKey(for: version), createdAt: added, modifiedAt: added)
    }

    func testBuildsListTheBaseThenTheNewestFirst() {
        let builds = [
            build("v0.99.1", version: "0.99.1", addedDaysAgo: 9),
            build("Original", addedDaysAgo: 20),
            build("v0.99.5", version: "0.99.5", addedDaysAgo: 1),
            build("v0.99.14", version: "0.99.14", base: true, addedDaysAgo: 5),
            build("2026-10-06", addedDaysAgo: 2),
            build("v0.99.13", version: "0.99.13", addedDaysAgo: 8),
        ]
        XCTAssertEqual(
            builds.sorted(by: GameDetailViewModel.buildSort).map(\.displayName),
            ["v0.99.14", "v0.99.13", "v0.99.5", "v0.99.1", "2026-10-06", "Original"],
            "versions compare as numbers, not text, and the Base stays first"
        )
    }
}

import Foundation
import XCTest
@testable import AssetStorage

final class ApplicationDataLocationTests: XCTestCase {
    /// The directory name is stored data: changing it would strand every existing library.
    func testRootIsTheBrandFreeAppDataDirectory() {
        let support = URL(fileURLWithPath: "/tmp/Application Support", isDirectory: true)

        let root = ApplicationDataLocation.root(in: support)

        XCTAssertEqual(root.lastPathComponent, "AppData")
        XCTAssertEqual(root.deletingLastPathComponent().standardizedFileURL, support.standardizedFileURL)
    }
}

import EmulatorDomain
import Foundation
import SwiftUI
import XCTest
@testable import PressAny

@MainActor
final class UIHapticsTests: XCTestCase {
    func testTapsFollowTouchHapticsAsItChanges() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try AppContainer(rootURL: root)
        let haptics = UIHaptics(container: container)

        XCTAssertNotNil(haptics.feedback(.selection), "unset means light, which taps")
        let cases: [(TouchHaptics, Bool)] = [(.off, false), (.medium, true), (.light, true), (.off, false)]
        for (setting, taps) in cases {
            try container.repositories.settings.setValueJSON(
                "\"\(setting.rawValue)\"", key: SettingKey.touchHaptics.rawValue, scope: .app
            )
            XCTAssertEqual(haptics.feedback(.error) != nil, taps, "\(setting)")
        }
    }

    func testTapsPlayWhereNoContainerIsSet() {
        XCTAssertNotNil(UIHaptics(container: nil).feedback(.success))
    }
}

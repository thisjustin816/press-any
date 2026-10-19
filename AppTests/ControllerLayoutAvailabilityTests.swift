import EmulatorApplication
import EmulatorDomain
import Foundation
import GameplayInput
import Importing
import XCTest
@testable import PressAny

@MainActor
final class ControllerLayoutAvailabilityTests: XCTestCase {
    func testInheritedLayoutsFitTheScreenWithoutRewritingStoredChoices() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try AppContainer(rootURL: root)
        let file = root.appendingPathComponent("Controls.gb")
        try Data(repeating: 0, count: 0x8000).write(to: file)
        let analysis = try container.importAnalyzer.analyzeROM(at: file, targetGameID: nil)
        let result = try container.importCommitter.commit(ROMImportPlan(
            analysis: analysis, disposition: .createGame(title: "Controls"),
            buildDisplayName: "Original", markAsBase: true
        ))
        let context = LaunchContext(gameID: result.build.gameID, buildID: result.build.id, saveProfileID: UUID())
        let store = container.repositories.settings
        let key = SettingKey.controllerLayout.rawValue
        let expected: TouchControlStyle = ControllerLayoutAvailability.supportsPlaytiles ? .playtiles : .gameBoy
        let scopes: [SettingsScope] = [.app, .system(.gameBoy), .game(context.gameID), .build(context.buildID)]

        XCTAssertEqual(container.controllerStyle(for: context), .gameBoy)
        XCTAssertEqual(container.controllerStyle(system: .gameBoy), .gameBoy)
        for scope in scopes {
            try store.set(TouchControlStyle.playtiles, key: key, scope: scope)
            XCTAssertEqual(container.controllerStyle(for: context), expected)
            XCTAssertEqual(container.controllerStyle(
                system: .gameBoy, gameID: context.gameID, buildID: context.buildID
            ), expected)
            XCTAssertEqual(container.controllerStyle(system: .gameBoy), expected)
            XCTAssertEqual(try store.valueJSON(key: key, scope: scope), "\"playtiles\"")
        }

        try store.set(TouchControlStyle.gameBoy, key: key, scope: .build(context.buildID))
        XCTAssertEqual(container.controllerStyle(for: context), .gameBoy)
        XCTAssertEqual(try store.valueJSON(key: key, scope: .app), "\"playtiles\"")
    }
}

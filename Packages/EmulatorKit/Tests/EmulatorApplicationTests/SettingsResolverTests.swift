import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import XCTest

final class SettingsResolverTests: XCTestCase {
    func testBuildOverrideWinsAndResetRevealsGameValue() throws {
        let store = InMemorySettingsStore()
        let gameID = UUID()
        let buildID = UUID()
        try store.setValueJSON("30", key: "rewind.seconds", scope: .app)
        try store.setValueJSON("60", key: "rewind.seconds", scope: .game(gameID))
        try store.setValueJSON("15", key: "rewind.seconds", scope: .build(buildID))

        let resolver = SettingsResolver(store: store)
        XCTAssertEqual(
            try resolver.resolve(
                key: "rewind.seconds",
                system: .gameBoyColor,
                gameID: gameID,
                buildID: buildID
            )?.valueJSON,
            "15"
        )

        try store.removeValue(key: "rewind.seconds", scope: .build(buildID))
        let inherited = try XCTUnwrap(resolver.resolve(
            key: "rewind.seconds",
            system: .gameBoyColor,
            gameID: gameID,
            buildID: buildID
        ))
        XCTAssertEqual(inherited.valueJSON, "60")
        XCTAssertEqual(inherited.source, .game(gameID))
    }

    func testSystemOverridesAppAndMissingChildScopesAreIgnored() throws {
        let store = InMemorySettingsStore()
        try store.setValueJSON("\"raw\"", key: "display.preset", scope: .app)
        try store.setValueJSON("\"lcd-authentic\"", key: "display.preset", scope: .system(.gameBoyColor))

        let resolved = try XCTUnwrap(SettingsResolver(store: store).resolve(
            key: "display.preset",
            system: .gameBoyColor
        ))

        XCTAssertEqual(resolved.source, .system(.gameBoyColor))
        XCTAssertEqual(try resolved.decode(String.self), "lcd-authentic")
    }

    func testRemovingAllOverridesReturnsNil() throws {
        let store = InMemorySettingsStore()
        let resolver = SettingsResolver(store: store)
        XCTAssertNil(try resolver.resolve(key: "audio.fastForward", system: .gameBoy))
    }

    func testTypedStoreRoundTripUsesJSON() throws {
        let store = InMemorySettingsStore()
        try store.set(AutoResumePolicy.ask, key: "resume.policy", scope: .app)

        let value: AutoResumePolicy? = try SettingsResolver(store: store).decode(
            AutoResumePolicy.self,
            key: "resume.policy",
            system: .gameBoy
        )
        XCTAssertEqual(value, .ask)
    }
}

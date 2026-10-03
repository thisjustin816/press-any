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

    func testEditorReportsTheOverrideAndWhatResetWouldInherit() throws {
        let store = InMemorySettingsStore()
        let gameID = UUID()
        let buildID = UUID()
        let resolver = SettingsResolver(store: store)
        let key = "rewind.seconds"

        try store.setValueJSON("30", key: key, scope: .app)
        try store.setValueJSON("15", key: key, scope: .build(buildID))

        let build = try resolver.edit(key: key, at: .build(buildID), system: .gameBoy, gameID: gameID, buildID: buildID)
        XCTAssertEqual(build.overrideJSON, "15")
        XCTAssertEqual(build.inherited, ResolvedSetting(key: key, valueJSON: "30", source: .app))

        try store.setValueJSON("60", key: key, scope: .game(gameID))
        let game = try resolver.edit(key: key, at: .game(gameID), system: .gameBoy, gameID: gameID)
        XCTAssertEqual(game.overrideJSON, "60")
        XCTAssertEqual(game.inherited?.source, .app)
        XCTAssertEqual(
            try resolver.edit(key: key, at: .build(buildID), system: .gameBoy, gameID: gameID, buildID: buildID).inherited?.source,
            .game(gameID),
            "the nearest scope below wins"
        )

        let app = try resolver.edit(key: key, at: .app, system: .gameBoy)
        XCTAssertNil(app.inherited, "only the built-in default is below App")

        XCTAssertThrowsError(try resolver.edit(key: key, at: .build(UUID()), system: .gameBoy, gameID: gameID, buildID: buildID))
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

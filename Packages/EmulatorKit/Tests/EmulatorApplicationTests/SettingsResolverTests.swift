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

    func testLCDFilterInheritsAndCanBeExplicitlyDisabledWithoutChangingScaling() throws {
        let store = InMemorySettingsStore()
        let resolver = SettingsResolver(store: store)
        let gameID = UUID(), buildID = UUID()
        let key = SettingKey.lcdFilter.rawValue
        try store.set(LCDFilter.lcd1x, key: key, scope: .app)
        try store.set(LCDFilter.lcd3x, key: key, scope: .system(.gameBoyColor))
        try store.set("fill", key: SettingKey.screenScaling.rawValue, scope: .build(buildID))
        XCTAssertEqual(try resolver.decode(LCDFilter.self, key: key, system: .gameBoy), .lcd1x)
        XCTAssertEqual(try resolver.decode(LCDFilter.self, key: key, system: .gameBoyColor), .lcd3x)

        try store.set(LCDFilter.off, key: key, scope: .game(gameID))
        try store.set(LCDFilter.lcd1x, key: key, scope: .build(buildID))
        XCTAssertEqual(try resolver.decode(
            LCDFilter.self, key: key, system: .gameBoyColor, gameID: gameID, buildID: buildID
        ), .lcd1x)
        try store.removeValue(key: key, scope: .build(buildID))
        XCTAssertEqual(try resolver.decode(
            LCDFilter.self, key: key, system: .gameBoyColor, gameID: gameID, buildID: buildID
        ), .off)
        XCTAssertEqual(try resolver.decode(
            String.self, key: SettingKey.screenScaling.rawValue,
            system: .gameBoyColor, gameID: gameID, buildID: buildID
        ), "fill")
        try store.removeValue(key: key, scope: .game(gameID))
        XCTAssertEqual(try resolver.decode(
            LCDFilter.self, key: key, system: .gameBoyColor, gameID: gameID, buildID: buildID
        ), .lcd3x)
    }

    func testColorCorrectionAndPaletteInheritIndependentlyThroughEveryScope() throws {
        let store = InMemorySettingsStore()
        let resolver = SettingsResolver(store: store)
        let gameID = UUID(), buildID = UUID()
        let correctionKey = SettingKey.colorCorrection.rawValue
        let paletteKey = SettingKey.dmgPalette.rawValue
        let scopes: [SettingsScope] = [.app, .system(.gameBoy), .game(gameID), .build(buildID)]
        let corrections: [ColorCorrection] = [.off, .accurate, .boostContrast, .lowContrast]
        let palettes: [DMGPalette] = [.cgbUpA, .cgbDownB, .cgbLeftA, .cgbRightB]
        for index in scopes.indices {
            try store.set(corrections[index], key: correctionKey, scope: scopes[index])
            try store.set(palettes[index], key: paletteKey, scope: scopes[index])
        }
        for index in scopes.indices.reversed() {
            XCTAssertEqual(try resolver.decode(ColorCorrection.self, key: correctionKey,
                                              system: .gameBoy, gameID: gameID, buildID: buildID), corrections[index])
            XCTAssertEqual(try resolver.decode(DMGPalette.self, key: paletteKey,
                                              system: .gameBoy, gameID: gameID, buildID: buildID), palettes[index])
            XCTAssertEqual(try resolver.resolve(key: correctionKey, system: .gameBoy,
                                               gameID: gameID, buildID: buildID)?.source, scopes[index])
            try store.removeValue(key: correctionKey, scope: scopes[index])
            XCTAssertEqual(try resolver.decode(DMGPalette.self, key: paletteKey,
                                              system: .gameBoy, gameID: gameID, buildID: buildID), palettes[index])
            try store.removeValue(key: paletteKey, scope: scopes[index])
        }
        XCTAssertNil(try resolver.decode(ColorCorrection.self, key: correctionKey, system: .gameBoy))
        XCTAssertNil(try resolver.decode(DMGPalette.self, key: paletteKey, system: .gameBoy))
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

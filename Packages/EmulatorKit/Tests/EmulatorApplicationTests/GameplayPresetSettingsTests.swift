import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import XCTest

final class GameplayPresetSettingsTests: XCTestCase {
    func testAccurateValuesAreSpecificToTheHardware() throws {
        XCTAssertEqual(
            GameplayPresetValues.values(for: .accurate, hardware: .gameBoy),
            GameplayPresetValues(displayFilter: .lcd1x, frameBlending: .blend, buttonBounce: true, dmgPalette: .dmgGreen)
        )
        XCTAssertEqual(GameplayPresetValues.values(for: .accurate, hardware: .gameBoyPocket)?.dmgPalette, .pocket)
        XCTAssertEqual(
            GameplayPresetValues.values(for: .accurate, hardware: .gameBoyColor),
            GameplayPresetValues(
                displayFilter: .lcd3x, frameBlending: .blend, buttonBounce: true, colorCorrection: .accurate
            )
        )
        XCTAssertEqual(
            GameplayPresetValues.values(for: .accurate, hardware: .superGameBoy2),
            GameplayPresetValues(displayFilter: .crt240p, frameBlending: .off, buttonBounce: false)
        )
        XCTAssertEqual(
            GameplayPresetValues.values(for: .accurate, hardware: .gameBoyPlayer),
            GameplayPresetValues(
                displayFilter: .gameCubeTV,
                frameBlending: .off,
                buttonBounce: false,
                colorCorrection: .off,
                advanceColors: .gameBoyColor
            )
        )
    }

    func testApplyingPresetAndManualChangeDeriveAccurateCustomAndAccurateAgain() throws {
        let store = InMemorySettingsStore()
        let presets = GameplayPresetSettings(store: store)
        let scope = SettingsScope.system(.gameBoyColor)

        try presets.apply(.accurate, at: scope, hardware: .gameBoyColor)
        XCTAssertEqual(try presets.resolvedPreset(system: .gameBoyColor, hardware: .gameBoyColor), .accurate)

        try store.set(FrameBlending.off, key: SettingKey.frameBlending.rawValue, scope: scope)
        XCTAssertEqual(try presets.resolvedPreset(system: .gameBoyColor, hardware: .gameBoyColor), .custom)

        try store.set(FrameBlending.blend, key: SettingKey.frameBlending.rawValue, scope: scope)
        XCTAssertEqual(try presets.resolvedPreset(system: .gameBoyColor, hardware: .gameBoyColor), .accurate)
    }

    func testPresetOverridesAndResetPreserveTheExistingInheritanceModel() throws {
        let store = InMemorySettingsStore()
        let presets = GameplayPresetSettings(store: store)
        let gameID = UUID(), buildID = UUID()

        try presets.apply(.clean, at: .app, hardware: .gameBoyColor)
        XCTAssertEqual(
            try presets.resolvedPreset(system: .gameBoyColor, gameID: gameID, buildID: buildID, hardware: .gameBoyColor),
            .clean
        )

        try presets.apply(.accurate, at: .game(gameID), hardware: .gameBoyColor)
        XCTAssertEqual(
            try presets.resolvedPreset(system: .gameBoyColor, gameID: gameID, buildID: buildID, hardware: .gameBoyColor),
            .accurate
        )

        try presets.reset(at: .game(gameID))
        XCTAssertEqual(
            try presets.resolvedPreset(system: .gameBoyColor, gameID: gameID, buildID: buildID, hardware: .gameBoyColor),
            .clean
        )
    }

    func testExistingDefaultsRemainCustomInsteadOfChangingBehaviorDuringMigration() throws {
        let store = InMemorySettingsStore()
        let presets = GameplayPresetSettings(store: store)
        XCTAssertEqual(try presets.resolvedPreset(system: .gameBoy, hardware: .gameBoy), .custom)
        XCTAssertEqual(try presets.resolvedPreset(system: .gameBoyColor, hardware: .gameBoyColor), .custom)
    }

    func testCleanRemovesDisplayAndInputAuthenticityEffects() throws {
        let gbc = try XCTUnwrap(GameplayPresetValues.values(for: .clean, hardware: .gameBoyColor))
        XCTAssertEqual(gbc.displayFilter, .off)
        XCTAssertEqual(gbc.colorCorrection, .off)
        XCTAssertEqual(gbc.frameBlending, .off)
        XCTAssertFalse(gbc.buttonBounce)

        let gbp = try XCTUnwrap(GameplayPresetValues.values(for: .clean, hardware: .gameBoyPlayer))
        XCTAssertEqual(gbp.displayFilter, .off)
        XCTAssertEqual(gbp.advanceColors, .gameBoyColor)
        XCTAssertFalse(gbp.buttonBounce)
    }

    func testControlledKeysAreExactlyTheCustomGameplayEditor() {
        XCTAssertEqual(
            GameplayPresetSettings.controlledKeys,
            [.lcdFilter, .frameBlending, .buttonBounce, .colorCorrection, .dmgPalette, .advanceColors]
        )
    }
}

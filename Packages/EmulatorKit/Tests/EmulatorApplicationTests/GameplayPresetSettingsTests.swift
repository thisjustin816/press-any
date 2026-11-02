import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import XCTest

final class GameplayPresetSettingsTests: XCTestCase {
    func testBuiltInPresetFollowsTheNewDeviceAndCustomValuesAreKept() throws {
        let store = InMemorySettingsStore()
        let presets = GameplayPresetSettings(store: store)
        let scope = SettingsScope.system(.gameBoyColor)
        try presets.apply(.accurate, at: scope, hardware: .gameBoyColor)
        try presets.retargetBuiltInPreset(from: .gameBoyColor, to: .gameBoyLight, at: scope, system: .gameBoyColor)
        XCTAssertEqual(try presets.resolvedPreset(system: .gameBoyColor, hardware: .gameBoyLight), .accurate)
        XCTAssertEqual(
            try SettingsResolver(store: store).decode(DMGPalette.self, key: SettingKey.dmgPalette.rawValue, system: .gameBoyColor),
            .light
        )
        try store.set(DisplayFilter.crt240p, key: SettingKey.lcdFilter.rawValue, scope: scope)
        try presets.retargetBuiltInPreset(from: .gameBoyLight, to: .gameBoyAdvanceSP101, at: scope, system: .gameBoyColor)
        XCTAssertEqual(
            try SettingsResolver(store: store).decode(DisplayFilter.self, key: SettingKey.lcdFilter.rawValue, system: .gameBoyColor),
            .crt240p
        )
        XCTAssertEqual(try presets.resolvedPreset(system: .gameBoyColor, hardware: .gameBoyAdvanceSP101), .custom)
    }

    func testCleanDisablesInheritedCorrectionOnEveryHardwareModel() throws {
        for hardware in HardwareModel.allCases where hardware != .automatic {
            let store = InMemorySettingsStore()
            let presets = GameplayPresetSettings(store: store)
            let resolver = SettingsResolver(store: store)
            try store.set(ColorCorrection.lowContrast, key: SettingKey.colorCorrection.rawValue, scope: .app)
            try presets.apply(.clean, at: .system(.gameBoy), hardware: hardware)
            XCTAssertEqual(
                try resolver.decode(ColorCorrection.self, key: SettingKey.colorCorrection.rawValue, system: .gameBoy),
                .off, "Clean on \(hardware) must not retain correction"
            )
            try store.set(ColorCorrection.lowContrast, key: SettingKey.colorCorrection.rawValue, scope: .system(.gameBoy))
            XCTAssertEqual(try presets.resolvedPreset(system: .gameBoy, hardware: hardware), .custom)
        }
    }

    func testBuiltInPresetsRoundTripForEveryHardwareModelAndScope() throws {
        for hardware in HardwareModel.allCases where hardware != .automatic {
            let store = InMemorySettingsStore()
            let presets = GameplayPresetSettings(store: store)
            let gameID = UUID(), buildID = UUID()
            let scopes: [SettingsScope] = [.app, .system(.gameBoy), .game(gameID), .build(buildID)]
            for (index, scope) in scopes.enumerated() {
                let preset: GameplayPreset = index.isMultiple(of: 2) ? .clean : .accurate
                try presets.apply(preset, at: scope, hardware: hardware)
                XCTAssertEqual(
                    try presets.resolvedPreset(system: .gameBoy, gameID: gameID, buildID: buildID, hardware: hardware),
                    preset, "\(hardware), \(scope)"
                )
            }
            for index in stride(from: scopes.count - 1, through: 1, by: -1) {
                try presets.reset(at: scopes[index])
                let inherited: GameplayPreset = (index - 1).isMultiple(of: 2) ? .clean : .accurate
                XCTAssertEqual(
                    try presets.resolvedPreset(system: .gameBoy, gameID: gameID, buildID: buildID, hardware: hardware),
                    inherited
                )
            }
        }
    }

    func testAccurateValuesAreSpecificToTheHardware() throws {
        XCTAssertEqual(
            GameplayPresetValues.values(for: .accurate, hardware: .gameBoy),
            GameplayPresetValues(displayFilter: .lcd1x, frameBlending: .blend, buttonBounce: true, colorCorrection: .off, dmgPalette: .dmgGreen)
        )
        XCTAssertEqual(GameplayPresetValues.values(for: .accurate, hardware: .gameBoyPocket)?.dmgPalette, .pocket)
        XCTAssertEqual(
            GameplayPresetValues.values(for: .accurate, hardware: .gameBoyColor),
            GameplayPresetValues(
                displayFilter: .authenticGBC, frameBlending: .blend, buttonBounce: true, colorCorrection: .lowContrast
            )
        )
        XCTAssertEqual(
            GameplayPresetValues.values(for: .accurate, hardware: .superGameBoy2),
            GameplayPresetValues(displayFilter: .crt240p, frameBlending: .off, buttonBounce: false, colorCorrection: .accurate)
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

    func testAllDisplayFiltersAreSelectableOnEveryHardwareModel() {
        for hardware in HardwareModel.allCases {
            XCTAssertEqual(DisplayFilter.selectable(for: hardware), DisplayFilter.allCases.filter { $0 != .lcd3x }, "\(hardware)")
        }
    }

    func testRetiredLCD3xStillDecodesAndResolvesToTheSelectedGBCShader() throws {
        let filter = try JSONDecoder().decode(DisplayFilter.self, from: Data("\"lcd3x\"".utf8))
        XCTAssertEqual(filter.selectionValue, .authenticGBC)
        XCTAssertFalse(DisplayFilter.selectable(for: .gameBoyColor).contains(.lcd3x))
    }

    func testDeviceSubmodelsHaveExplicitAccurateConfigurations() throws {
        XCTAssertEqual(GameplayPresetValues.values(for: .accurate, hardware: .gameBoyLight)?.dmgPalette, .light)
        XCTAssertEqual(GameplayPresetValues.values(for: .accurate, hardware: .gameBoyAdvanceSP101)?.displayFilter, .sp101LCD)
        XCTAssertEqual(HardwareModel.gameBoyLight.family, .gameBoy)
        XCTAssertEqual(HardwareModel.gameBoyAdvanceSP101.family, .gameBoyColor)
    }

    func testCRTTreatmentsUseSignalBasedDisplayNames() {
        XCTAssertEqual(DisplayFilter.crt240p.displayName, "CRT 240p")
        XCTAssertEqual(DisplayFilter.gameCubeTV.displayName, "CRT 480i")
        XCTAssertEqual(DisplayFilter.gameCubeTV.rawValue, "gameCubeTV", "persisted identifier must stay compatible")
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

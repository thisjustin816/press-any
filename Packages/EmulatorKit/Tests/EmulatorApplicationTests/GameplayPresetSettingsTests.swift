import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import XCTest

final class GameplayPresetSettingsTests: XCTestCase {
    private let models = HardwareModel.allCases.filter { $0 != .automatic }

    private func decode<Value: Decodable>(
        _ type: Value.Type, _ key: SettingKey, _ store: InMemorySettingsStore, system: GameSystem = .gameBoy,
        gameID: UUID? = nil, buildID: UUID? = nil
    ) throws -> Value? {
        try SettingsResolver(store: store).decode(type, key: key.rawValue, system: system, gameID: gameID, buildID: buildID)
    }

    func testAnUntouchedScopeIsTheStandardPresetOnEveryModelAndScope() {
        let store = InMemorySettingsStore()
        let presets = GameplayPresetSettings(store: store)
        for hardware in models {
            for system in GameSystem.allCases {
                XCTAssertEqual(presets.resolvedPreset(system: system, hardware: hardware), .standard, "\(hardware)")
                XCTAssertEqual(
                    presets.resolvedPreset(system: system, gameID: UUID(), buildID: UUID(), hardware: hardware),
                    .standard
                )
            }
            let effective = presets.effectiveValues(system: .gameBoy, hardware: hardware)
            let standard = GameplayPresetValues.standard(for: hardware)
            XCTAssertEqual(effective.displayFilter, standard.displayFilter)
            XCTAssertEqual(effective.frameBlending, standard.frameBlending)
            XCTAssertEqual(effective.buttonBounce, standard.buttonBounce)
        }
        XCTAssertEqual(GameplayPreset.standard.displayName, GameplayPreset.standardName)
    }

    func testEachModelHasThreeDistinctBuiltInPresets() throws {
        for hardware in models {
            let values = try GameplayPreset.builtIn.map { try XCTUnwrap(GameplayPresetValues.values(for: $0, hardware: hardware)) }
            XCTAssertEqual(Set(values.map(\.displayFilter)).count, 3, "\(hardware) presets look different")
            XCTAssertEqual(values[2].displayFilter, .off, "Clean is unfiltered")
            XCTAssertEqual(values[2].frameBlending, .off)
            XCTAssertFalse(values[2].buttonBounce)
        }
        XCTAssertNil(GameplayPresetValues.values(for: .custom, hardware: .gameBoy))
    }

    func testAccurateAndStandardValuesAreSpecificToTheHardware() {
        func accurate(_ hardware: HardwareModel) -> GameplayPresetValues? {
            GameplayPresetValues.values(for: .accurate, hardware: hardware)
        }
        XCTAssertEqual(accurate(.gameBoy), GameplayPresetValues(displayFilter: .monochromeLCD, frameBlending: .ghosting, buttonBounce: true))
        XCTAssertEqual(accurate(.gameBoyPocket), GameplayPresetValues(displayFilter: .monochromeLCD, frameBlending: .blend, buttonBounce: true))
        XCTAssertEqual(
            accurate(.gameBoyColor),
            GameplayPresetValues(displayFilter: .authenticGBC, frameBlending: .blend, buttonBounce: true, colorCorrection: .lowContrast)
        )
        XCTAssertEqual(
            accurate(.gameBoyAdvance),
            GameplayPresetValues(
                displayFilter: .gbaLCD, frameBlending: .blend, buttonBounce: true,
                colorCorrection: .off, advanceColors: .gameBoyAdvance
            )
        )
        XCTAssertEqual(accurate(.superGameBoy), accurate(.superGameBoy2))
        XCTAssertEqual(accurate(.superGameBoy)?.displayFilter, .crt240p)
        XCTAssertEqual(accurate(.gameBoyPlayer)?.displayFilter, .crt480p)
        XCTAssertEqual(accurate(.gameBoyPlayer)?.buttonBounce, false, "a GameCube controller has no Game Boy contacts")

        XCTAssertEqual(GameplayPresetValues.standard(for: .gameBoy).displayFilter, .lcd1x)
        XCTAssertEqual(GameplayPresetValues.standard(for: .gameBoyColor).displayFilter, .lcd1x)
        XCTAssertEqual(GameplayPresetValues.standard(for: .gameBoyAdvance).displayFilter, .sp101LCD)
        XCTAssertEqual(GameplayPresetValues.standard(for: .superGameBoy).displayFilter, .scanlines)
        XCTAssertEqual(GameplayPresetValues.standard(for: .gameBoyPlayer).displayFilter, .scanlines)
        XCTAssertEqual(GameplayPresetValues.standard(for: .automatic), GameplayPresetValues.standard(for: .gameBoy))
    }

    func testBuiltInPresetsRoundTripForEveryHardwareModelAndScope() throws {
        for hardware in models {
            let store = InMemorySettingsStore()
            let presets = GameplayPresetSettings(store: store)
            let gameID = UUID(), buildID = UUID()
            let scopes: [SettingsScope] = [.app, .system(.gameBoy), .game(gameID), .build(buildID)]
            let chosen: [GameplayPreset] = [.accurate, .clean, .standard, .accurate]
            for (scope, preset) in zip(scopes, chosen) {
                try presets.apply(preset, at: scope, hardware: hardware, system: .gameBoy, gameID: gameID, buildID: buildID)
                XCTAssertEqual(
                    presets.resolvedPreset(system: .gameBoy, gameID: gameID, buildID: buildID, hardware: hardware),
                    preset, "\(hardware), \(scope)"
                )
            }
            for index in stride(from: scopes.count - 1, through: 1, by: -1) {
                try presets.reset(at: scopes[index])
                XCTAssertEqual(
                    presets.resolvedPreset(system: .gameBoy, gameID: gameID, buildID: buildID, hardware: hardware),
                    chosen[index - 1], "\(hardware) after resetting \(scopes[index])"
                )
            }
        }
    }

    func testChoosingTheStandardPresetOverAnUntouchedScopeStoresNothing() throws {
        let store = InMemorySettingsStore()
        let presets = GameplayPresetSettings(store: store)
        try presets.apply(.standard, at: .system(.gameBoyColor), hardware: .gameBoyColor, system: .gameBoyColor)
        for key in GameplayPresetSettings.controlledKeys {
            XCTAssertNil(try store.valueJSON(key: key.rawValue, scope: .system(.gameBoyColor)), "\(key)")
        }
        try presets.apply(.accurate, at: .system(.gameBoyColor), hardware: .gameBoyColor, system: .gameBoyColor)
        try presets.apply(.standard, at: .system(.gameBoyColor), hardware: .gameBoyColor, system: .gameBoyColor)
        XCTAssertNil(try store.valueJSON(key: SettingKey.lcdFilter.rawValue, scope: .system(.gameBoyColor)))
        XCTAssertEqual(presets.resolvedPreset(system: .gameBoyColor, hardware: .gameBoyColor), .standard)
    }

    func testTheStandardPresetOverridesAParentScopeThatChoseAnother() throws {
        let store = InMemorySettingsStore()
        let presets = GameplayPresetSettings(store: store)
        let gameID = UUID()
        try presets.apply(.accurate, at: .system(.gameBoy), hardware: .gameBoy, system: .gameBoy)
        try presets.apply(.standard, at: .game(gameID), hardware: .gameBoy, system: .gameBoy, gameID: gameID)
        XCTAssertEqual(presets.resolvedPreset(system: .gameBoy, gameID: gameID, hardware: .gameBoy), .standard)
        XCTAssertEqual(presets.resolvedPreset(system: .gameBoy, hardware: .gameBoy), .accurate)
        XCTAssertEqual(try decode(DisplayFilter.self, .lcdFilter, store, gameID: gameID), .lcd1x)
    }

    func testEachControlledValueChangedByHandLeavesThePresetUntilRestored() throws {
        for hardware in models {
            for preset in GameplayPreset.builtIn {
                let store = InMemorySettingsStore()
                let presets = GameplayPresetSettings(store: store)
                let scope = SettingsScope.system(.gameBoyColor)
                let values = try XCTUnwrap(GameplayPresetValues.values(for: preset, hardware: hardware))
                try presets.apply(preset, at: scope, hardware: hardware, system: .gameBoyColor)

                func check<Value: Codable & CaseIterable & Equatable>(_ key: SettingKey, _ expected: Value?) throws {
                    guard let expected else { return }
                    let other = try XCTUnwrap(Value.allCases.first { $0 != expected })
                    try store.set(other, key: key.rawValue, scope: scope)
                    // Another built-in preset can differ in this one value, as Clean does from
                    // Accurate on the Game Boy Player.
                    let changed = presets.resolvedPreset(system: .gameBoyColor, hardware: hardware)
                    XCTAssertNotEqual(changed, preset, "\(hardware) \(preset) \(key)")
                    if changed != .custom {
                        XCTAssertEqual(GameplayPresetValues.values(for: changed, hardware: hardware)?.displayFilter, other as? DisplayFilter)
                    }
                    try store.set(expected, key: key.rawValue, scope: scope)
                    XCTAssertEqual(presets.resolvedPreset(system: .gameBoyColor, hardware: hardware), preset, "\(hardware) \(preset) \(key)")
                }
                try check(.lcdFilter, values.displayFilter)
                try check(.frameBlending, values.frameBlending)
                try check(.colorCorrection, values.colorCorrection)
                try check(.advanceColors, values.advanceColors)
                try store.set(!values.buttonBounce, key: SettingKey.buttonBounce.rawValue, scope: scope)
                XCTAssertEqual(presets.resolvedPreset(system: .gameBoyColor, hardware: hardware), .custom)
                try store.set(values.buttonBounce, key: SettingKey.buttonBounce.rawValue, scope: scope)
                XCTAssertEqual(presets.resolvedPreset(system: .gameBoyColor, hardware: hardware), preset)
            }
        }
    }

    func testPalettesAreFreeOfPresetsInBothDirections() throws {
        for hardware in models {
            for preset in GameplayPreset.builtIn {
                let store = InMemorySettingsStore()
                let presets = GameplayPresetSettings(store: store)
                try store.set(DMGPalette.cgbRightA, key: SettingKey.dmgPalette.rawValue, scope: .system(.gameBoy))
                try presets.apply(preset, at: .system(.gameBoy), hardware: hardware, system: .gameBoy)
                XCTAssertEqual(try decode(DMGPalette.self, .dmgPalette, store), .cgbRightA, "\(preset) keeps the palette")
                for palette in DMGPalette.allCases {
                    try store.set(palette, key: SettingKey.dmgPalette.rawValue, scope: .system(.gameBoy))
                    XCTAssertEqual(presets.resolvedPreset(system: .gameBoy, hardware: hardware), preset, "\(hardware) \(palette)")
                }
                try presets.reset(at: .system(.gameBoy))
                XCTAssertNotNil(try decode(DMGPalette.self, .dmgPalette, store), "resetting the preset keeps the palette")
            }
        }
        XCTAssertFalse(GameplayPresetSettings.controlledKeys.contains(.dmgPalette))
    }

    func testModelChangeRetargetsOnlyAPresetStoredAtThatScope() throws {
        let store = InMemorySettingsStore()
        let presets = GameplayPresetSettings(store: store)
        let gameID = UUID()
        let game = SettingsScope.game(gameID)

        // Inherited: nothing is written at the Game, and the unset values follow the new hardware.
        try presets.retargetBuiltInPreset(from: .gameBoy, to: .superGameBoy, at: game, system: .gameBoy, gameID: gameID)
        for key in GameplayPresetSettings.controlledKeys {
            XCTAssertNil(try store.valueJSON(key: key.rawValue, scope: game))
        }
        XCTAssertEqual(presets.resolvedPreset(system: .gameBoy, gameID: gameID, hardware: .superGameBoy), .standard)

        // Inherited from the system: still nothing written at the Game.
        try presets.apply(.accurate, at: .system(.gameBoy), hardware: .gameBoy, system: .gameBoy)
        try presets.retargetBuiltInPreset(from: .gameBoy, to: .superGameBoy, at: game, system: .gameBoy, gameID: gameID)
        XCTAssertNil(try store.valueJSON(key: SettingKey.lcdFilter.rawValue, scope: game))

        // Stored at the Game: the same preset for the new hardware.
        try presets.apply(.accurate, at: game, hardware: .gameBoy, system: .gameBoy, gameID: gameID)
        try presets.retargetBuiltInPreset(from: .gameBoy, to: .superGameBoy, at: game, system: .gameBoy, gameID: gameID)
        XCTAssertEqual(presets.resolvedPreset(system: .gameBoy, gameID: gameID, hardware: .superGameBoy), .accurate)
        XCTAssertEqual(try decode(DisplayFilter.self, .lcdFilter, store, gameID: gameID), .crt240p)

        // Custom stays as it is.
        try store.set(DisplayFilter.lcd3x, key: SettingKey.lcdFilter.rawValue, scope: game)
        try presets.retargetBuiltInPreset(from: .superGameBoy, to: .gameBoyColor, at: game, system: .gameBoy, gameID: gameID)
        XCTAssertEqual(try decode(DisplayFilter.self, .lcdFilter, store, gameID: gameID), .lcd3x)
        XCTAssertEqual(try decode(Bool.self, .buttonBounce, store, gameID: gameID), false)
    }

    func testVersionOneSettingsKeepTheirValuesAndLCD1xMatchesTheStandardPreset() throws {
        let store = InMemorySettingsStore()
        let presets = GameplayPresetSettings(store: store)
        try store.setValueJSON("\"lcd1x\"", key: SettingKey.lcdFilter.rawValue, scope: .app)
        XCTAssertEqual(presets.resolvedPreset(system: .gameBoy, hardware: .gameBoy), .standard)
        XCTAssertEqual(presets.resolvedPreset(system: .gameBoyColor, hardware: .gameBoyColor), .standard)
        try store.setValueJSON("\"lcd3x\"", key: SettingKey.lcdFilter.rawValue, scope: .app)
        XCTAssertEqual(presets.effectiveValues(system: .gameBoyColor, hardware: .gameBoyColor).displayFilter, .lcd3x)
        XCTAssertEqual(presets.resolvedPreset(system: .gameBoyColor, hardware: .gameBoyColor), .custom)
    }

    func testUnknownStoredValuesReadAsUnset() throws {
        let store = InMemorySettingsStore()
        let presets = GameplayPresetSettings(store: store)
        try store.setValueJSON("\"gameCubeTV\"", key: SettingKey.lcdFilter.rawValue, scope: .system(.gameBoyColor))
        try store.setValueJSON("not json", key: SettingKey.frameBlending.rawValue, scope: .system(.gameBoyColor))
        XCTAssertEqual(
            presets.effectiveValues(system: .gameBoyColor, hardware: .gameBoyColor).displayFilter,
            GameplayPresetValues.standard(for: .gameBoyColor).displayFilter
        )
        XCTAssertEqual(presets.resolvedPreset(system: .gameBoyColor, hardware: .gameBoyColor), .standard)
    }

    func testControlledKeysAreExactlyTheCustomGameplayEditor() {
        XCTAssertEqual(
            GameplayPresetSettings.controlledKeys,
            [.lcdFilter, .frameBlending, .buttonBounce, .colorCorrection, .advanceColors]
        )
    }

    func testAllDisplayFiltersAreSelectableAndNamedForWhatTheyShow() {
        XCTAssertEqual(DisplayFilter.selectable, DisplayFilter.allCases)
        XCTAssertEqual(DisplayFilter.crt240p.displayName, "CRT 240p")
        XCTAssertEqual(DisplayFilter.crt480p.displayName, "CRT 480p")
        for filter in DisplayFilter.allCases {
            XCTAssertFalse(filter.displayName.contains("GameCube"))
            XCTAssertFalse(filter.rawValue.lowercased().contains("gamecube"))
        }
        XCTAssertNil(DisplayFilter(rawValue: "gameCubeTV"))
    }
}

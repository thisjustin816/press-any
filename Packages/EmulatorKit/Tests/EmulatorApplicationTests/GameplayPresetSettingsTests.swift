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
            GameplayPresetValues(displayFilter: .authenticGBC, frameBlending: .blend, buttonBounce: true, colorCorrection: .reduceContrast)
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

        XCTAssertEqual(GameplayPresetValues.standard(for: .gameBoy).displayFilter, .lcd1x)
        XCTAssertEqual(
            GameplayPresetValues.standard(for: .gameBoyColor),
            GameplayPresetValues(displayFilter: .lcd1x, frameBlending: .blend, buttonBounce: true, colorCorrection: .soft),
            "Nostalgic shows a Game Boy Color's colors softened, as a bright backlit screen does"
        )
        XCTAssertEqual(GameplayPresetValues.standard(for: .gameBoyAdvance).displayFilter, .sp101LCD)
        XCTAssertEqual(GameplayPresetValues.standard(for: .superGameBoy).displayFilter, .curvedScanlines)
        XCTAssertEqual(GameplayPresetValues.standard(for: .superGameBoy2).displayFilter, .curvedScanlines)
        XCTAssertEqual(GameplayPresetValues.standard(for: .gameBoyPlayer).displayFilter, .slightlyCurvedScanlines)
        XCTAssertEqual(GameplayPresetValues.standard(for: .automatic), GameplayPresetValues.standard(for: .gameBoyPocket))
        for preset in GameplayPreset.builtIn {
            XCTAssertEqual(
                GameplayPresetValues.values(for: preset, hardware: .automatic),
                GameplayPresetValues.values(for: preset, hardware: .gameBoyPocket),
                "an unresolved Automatic reads as the Pocket it picks for most games"
            )
        }
        for hardware in models {
            XCTAssertTrue(GameplayPresetValues.standard(for: hardware).buttonBounce, "\(hardware) Nostalgic bounces")
            XCTAssertEqual(accurate(hardware)?.buttonBounce, true, "\(hardware) Accurate bounces")
            XCTAssertEqual(GameplayPresetValues.values(for: .clean, hardware: hardware)?.buttonBounce, false, "only Clean turns bounce off")
        }
        XCTAssertFalse(GameplayPresetValues.values(for: .standard, hardware: .superGameBoy)?.displayFilter == .scanlines, "flat Scanlines are a manual choice")
    }

    /// Only Nostalgic on a Game Boy Color plays Soft.
    func testColorCorrectionEachPresetSetsOnEachModel() {
        // Nostalgic, Accurate, Clean.
        let expected: [HardwareModel: [ColorCorrection?]] = [
            .gameBoy: [nil, nil, nil],
            .gameBoyPocket: [nil, nil, nil],
            .superGameBoy: [.balanced, .balanced, .off],
            .superGameBoy2: [.balanced, .balanced, .off],
            .gameBoyColor: [.soft, .reduceContrast, .off],
            .gameBoyAdvance: [.off, .off, .off],
            .gameBoyPlayer: [.balanced, .off, .off],
        ]
        for (hardware, corrections) in expected {
            XCTAssertEqual(
                GameplayPreset.builtIn.map { GameplayPresetValues.values(for: $0, hardware: hardware)?.colorCorrection },
                corrections,
                "\(hardware)"
            )
        }
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
        for key in GameplayPresetSettings.controlledKeys + [.gameplayPreset] {
            XCTAssertNil(try store.valueJSON(key: key.rawValue, scope: .system(.gameBoyColor)), "\(key)")
        }
        try presets.apply(.accurate, at: .system(.gameBoyColor), hardware: .gameBoyColor, system: .gameBoyColor)
        try presets.apply(.standard, at: .system(.gameBoyColor), hardware: .gameBoyColor, system: .gameBoyColor)
        XCTAssertNil(try store.valueJSON(key: SettingKey.lcdFilter.rawValue, scope: .system(.gameBoyColor)))
        XCTAssertNil(presets.storedPreset(at: .system(.gameBoyColor)))
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
        XCTAssertEqual(presets.storedPreset(at: .game(gameID)), .standard)
        XCTAssertEqual(presets.effectiveValues(system: .gameBoy, gameID: gameID, hardware: .gameBoy).displayFilter, .lcd1x)
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
                    // A built-in preset that differs in this one value alone would be recognized
                    // instead of Custom.
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

    /// A television filter chosen by hand on a handheld, or a handheld's on a television model,
    /// plays as chosen and reads as Custom.
    func testAnyFilterChosenByHandOnAnyModelIsCustom() throws {
        for hardware in models {
            for preset in GameplayPreset.builtIn {
                let presetFilter = try XCTUnwrap(GameplayPresetValues.values(for: preset, hardware: hardware)).displayFilter
                for filter in DisplayFilter.allCases where filter != presetFilter {
                    let store = InMemorySettingsStore()
                    let presets = GameplayPresetSettings(store: store)
                    try presets.apply(preset, at: .system(.gameBoy), hardware: hardware, system: .gameBoy)
                    try store.set(filter, key: SettingKey.lcdFilter.rawValue, scope: .system(.gameBoy))
                    XCTAssertEqual(presets.effectiveValues(system: .gameBoy, hardware: hardware).displayFilter, filter)
                    let resolved = presets.resolvedPreset(system: .gameBoy, hardware: hardware)
                    XCTAssertNotEqual(resolved, preset, "\(hardware) \(preset) \(filter)")
                    // Only a filter that completes another built-in preset's values exactly reads
                    // as that preset; a television filter on a handheld, or a handheld's on a
                    // television model, is always Custom.
                    let televisionModels: Set<HardwareModel> = [.superGameBoy, .superGameBoy2, .gameBoyPlayer]
                    let televisionFilters: Set<DisplayFilter> = [.scanlines, .curvedScanlines, .slightlyCurvedScanlines, .crt240p, .crt480p]
                    if televisionModels.contains(hardware) != televisionFilters.contains(filter) || filter == .scanlines {
                        XCTAssertEqual(resolved, .custom, "\(hardware) \(preset) \(filter)")
                    } else if resolved != .custom {
                        XCTAssertEqual(GameplayPresetValues.values(for: resolved, hardware: hardware)?.displayFilter, filter)
                    }
                }
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

    func testModelChangeConvertsOnlyValuesStoredAtThatScopeToTheirPreset() throws {
        let store = InMemorySettingsStore()
        let presets = GameplayPresetSettings(store: store)
        let gameID = UUID()
        let game = SettingsScope.game(gameID)

        // Inherited: nothing is written at the Game, and the unset values follow the new hardware.
        try presets.retargetBuiltInPreset(from: [.gameBoy], to: [.superGameBoy], at: game, system: .gameBoy, gameID: gameID)
        for key in GameplayPresetSettings.controlledKeys + [.gameplayPreset] {
            XCTAssertNil(try store.valueJSON(key: key.rawValue, scope: game))
        }
        XCTAssertEqual(presets.resolvedPreset(system: .gameBoy, gameID: gameID, hardware: .superGameBoy), .standard)

        // Inherited from the system: still nothing written at the Game.
        try presets.apply(.accurate, at: .system(.gameBoy), hardware: .gameBoy, system: .gameBoy)
        try presets.retargetBuiltInPreset(from: [.gameBoy], to: [.superGameBoy], at: game, system: .gameBoy, gameID: gameID)
        XCTAssertNil(try store.valueJSON(key: SettingKey.lcdFilter.rawValue, scope: game))
        XCTAssertNil(presets.storedPreset(at: game))

        // A preset chosen at the Game follows the new hardware with nothing to convert.
        try presets.apply(.accurate, at: game, hardware: .gameBoy, system: .gameBoy, gameID: gameID)
        try presets.retargetBuiltInPreset(from: [.gameBoy], to: [.superGameBoy], at: game, system: .gameBoy, gameID: gameID)
        XCTAssertEqual(presets.storedPreset(at: game), .accurate)
        XCTAssertEqual(presets.effectiveValues(system: .gameBoy, gameID: gameID, hardware: .superGameBoy).displayFilter, .crt240p)

        // Values stored one by one that made Accurate on the old hardware become Accurate itself.
        try presets.reset(at: game)
        let accurateOnGameBoy = try XCTUnwrap(GameplayPresetValues.values(for: .accurate, hardware: .gameBoy))
        try store.set(accurateOnGameBoy.displayFilter, key: SettingKey.lcdFilter.rawValue, scope: game)
        try store.set(accurateOnGameBoy.frameBlending, key: SettingKey.frameBlending.rawValue, scope: game)
        try store.set(accurateOnGameBoy.buttonBounce, key: SettingKey.buttonBounce.rawValue, scope: game)
        try presets.retargetBuiltInPreset(from: [.gameBoy], to: [.superGameBoy], at: game, system: .gameBoy, gameID: gameID)
        XCTAssertEqual(presets.storedPreset(at: game), .accurate)
        XCTAssertNil(try store.valueJSON(key: SettingKey.lcdFilter.rawValue, scope: game))
        XCTAssertEqual(presets.resolvedPreset(system: .gameBoy, gameID: gameID, hardware: .superGameBoy), .accurate)

        // Custom stays as it is, including a bounce turned off by hand, which Accurate on the
        // new hardware would turn on.
        try presets.reset(at: game)
        try store.set(DisplayFilter.lcd3x, key: SettingKey.lcdFilter.rawValue, scope: game)
        try store.set(false, key: SettingKey.buttonBounce.rawValue, scope: game)
        try presets.retargetBuiltInPreset(from: [.superGameBoy], to: [.gameBoyColor], at: game, system: .gameBoy, gameID: gameID)
        XCTAssertEqual(try decode(DisplayFilter.self, .lcdFilter, store, gameID: gameID), .lcd3x)
        XCTAssertEqual(try decode(Bool.self, .buttonBounce, store, gameID: gameID), false)
        XCTAssertNil(presets.storedPreset(at: game))
    }

    /// When presets wrote their values, choosing Accurate at a Game whose settings showed a Game
    /// Boy wrote the Game Boy's Accurate values at the Game, and its Game Boy Color Build played
    /// them: a monochrome LCD with ghosting. Now each game gets the preset's values for its own
    /// hardware, at every scope.
    func testAPresetChosenWhereGamesRunOnSeveralModelsResolvesPerGame() throws {
        let gameID = UUID(), buildID = UUID()
        let scopes: [(SettingsScope, UUID?, UUID?)] = [
            (.app, nil, nil), (.system(.gameBoy), nil, nil), (.game(gameID), gameID, nil), (.build(buildID), gameID, buildID),
        ]
        let automatic = HardwareModel.automaticChoices(for: .gameBoy)
        for (scope, game, build) in scopes {
            for preset in GameplayPreset.builtIn {
                let store = InMemorySettingsStore()
                let presets = GameplayPresetSettings(store: store)
                try presets.apply(preset, at: scope, hardware: automatic, system: .gameBoy, gameID: game, buildID: build)
                for hardware in models {
                    let values = try XCTUnwrap(GameplayPresetValues.values(for: preset, hardware: hardware))
                    let effective = presets.effectiveValues(system: .gameBoy, gameID: game, buildID: build, hardware: hardware)
                    XCTAssertEqual(effective.displayFilter, values.displayFilter, "\(scope) \(preset) \(hardware)")
                    XCTAssertEqual(effective.frameBlending, values.frameBlending, "\(scope) \(preset) \(hardware)")
                    XCTAssertEqual(effective.buttonBounce, values.buttonBounce, "\(scope) \(preset) \(hardware)")
                    if let correction = values.colorCorrection {
                        XCTAssertEqual(effective.colorCorrection, correction, "\(scope) \(preset) \(hardware)")
                    }
                    XCTAssertEqual(presets.resolvedPreset(system: .gameBoy, gameID: game, buildID: build, hardware: hardware), preset)
                }
                XCTAssertEqual(presets.resolvedPreset(system: .gameBoy, gameID: game, buildID: build, hardware: automatic), preset)
                for key in GameplayPresetSettings.controlledKeys {
                    XCTAssertNil(try store.valueJSON(key: key.rawValue, scope: scope), "no one model's values are stored")
                }
            }
        }
    }

    func testAScopeWhereGamesDisagreeIsCustomUntilEveryModelPlaysOnePreset() throws {
        let store = InMemorySettingsStore()
        let presets = GameplayPresetSettings(store: store)
        let automatic = HardwareModel.automaticChoices(for: .gameBoy)
        try presets.apply(.accurate, at: .system(.gameBoy), hardware: automatic, system: .gameBoy)
        // Monochrome LCD is Accurate on a Pocket but not on a Super Game Boy 2 or Game Boy Color.
        try store.set(DisplayFilter.monochromeLCD, key: SettingKey.lcdFilter.rawValue, scope: .system(.gameBoy))
        XCTAssertEqual(presets.resolvedPreset(system: .gameBoy, hardware: .gameBoyPocket), .accurate)
        XCTAssertEqual(presets.resolvedPreset(system: .gameBoy, hardware: .superGameBoy2), .custom)
        XCTAssertEqual(presets.resolvedPreset(system: .gameBoy, hardware: automatic), .custom)
        try store.removeValue(key: SettingKey.lcdFilter.rawValue, scope: .system(.gameBoy))
        XCTAssertEqual(presets.resolvedPreset(system: .gameBoy, hardware: automatic), .accurate)
        XCTAssertEqual(presets.resolvedPreset(system: .gameBoy, hardware: []), .custom, "no hardware plays anything")
    }

    func testTheEditorShowsThePresetsValueForTheHardwareAndWhereItIsChosen() throws {
        let store = InMemorySettingsStore()
        let presets = GameplayPresetSettings(store: store)
        let gameID = UUID()
        try presets.apply(.accurate, at: .system(.gameBoy), hardware: .superGameBoy2, system: .gameBoy)

        let atGame = try presets.edit(.lcdFilter, at: .game(gameID), system: .gameBoy, gameID: gameID, hardware: .superGameBoy2)
        XCTAssertNil(atGame.overrideJSON)
        XCTAssertEqual(atGame.inherited?.source, .system(.gameBoy))
        XCTAssertEqual(atGame.inherited?.preset, .accurate)
        XCTAssertEqual(try atGame.inherited?.decode(DisplayFilter.self), .crt240p)

        let onPocket = try presets.edit(.lcdFilter, at: .game(gameID), system: .gameBoy, gameID: gameID, hardware: .gameBoyPocket)
        XCTAssertEqual(try onPocket.inherited?.decode(DisplayFilter.self), .monochromeLCD)

        // The preset at the scope itself gives the value Reset to Inherited would leave.
        let atSystem = try presets.edit(.frameBlending, at: .system(.gameBoy), system: .gameBoy, hardware: .gameBoyPocket)
        XCTAssertEqual(atSystem.inherited?.source, .system(.gameBoy))
        XCTAssertEqual(try atSystem.inherited?.decode(FrameBlending.self), .blend)

        // A preset that leaves a setting alone on this hardware passes it on from below.
        try store.set(ColorCorrection.boostContrast, key: SettingKey.colorCorrection.rawValue, scope: .app)
        let correction = try presets.edit(.colorCorrection, at: .system(.gameBoy), system: .gameBoy, hardware: .gameBoyPocket)
        XCTAssertEqual(correction.inherited?.source, .app)
        XCTAssertNil(correction.inherited?.preset)

        // A value stored by hand wins over the preset at the same scope.
        try store.set(DisplayFilter.off, key: SettingKey.lcdFilter.rawValue, scope: .system(.gameBoy))
        XCTAssertEqual(presets.effectiveValues(system: .gameBoy, gameID: gameID, hardware: .superGameBoy2).displayFilter, .off)
        XCTAssertThrowsError(try presets.edit(.lcdFilter, at: .build(UUID()), system: .gameBoy, hardware: .gameBoyPocket))
    }

    func testResettingAScopeRemovesItsPresetAndAnUnreadablePresetReadsAsNone() throws {
        let store = InMemorySettingsStore()
        let presets = GameplayPresetSettings(store: store)
        try presets.apply(.clean, at: .system(.gameBoy), hardware: .gameBoyPocket, system: .gameBoy)
        XCTAssertEqual(presets.storedPreset(at: .system(.gameBoy)), .clean)
        try presets.reset(at: .system(.gameBoy))
        XCTAssertNil(try store.valueJSON(key: SettingKey.gameplayPreset.rawValue, scope: .system(.gameBoy)))
        XCTAssertEqual(presets.resolvedPreset(system: .gameBoy, hardware: .gameBoyPocket), .standard)

        try store.setValueJSON("\"custom\"", key: SettingKey.gameplayPreset.rawValue, scope: .system(.gameBoy))
        XCTAssertNil(presets.storedPreset(at: .system(.gameBoy)), "Custom is never a stored preset")
        try store.setValueJSON("\"retro\"", key: SettingKey.gameplayPreset.rawValue, scope: .system(.gameBoy))
        XCTAssertNil(presets.storedPreset(at: .system(.gameBoy)))
        XCTAssertEqual(presets.resolvedPreset(system: .gameBoy, hardware: .gameBoyPocket), .standard)
        try presets.apply(.custom, at: .system(.gameBoy), hardware: .gameBoyPocket, system: .gameBoy)
        XCTAssertEqual(
            try store.valueJSON(key: SettingKey.gameplayPreset.rawValue, scope: .system(.gameBoy)), "\"retro\"",
            "Custom can't be applied"
        )
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
        XCTAssertEqual(DisplayFilter.scanlines.displayName, "Scanlines")
        XCTAssertEqual(DisplayFilter.curvedScanlines.displayName, "Curved Scanlines")
        XCTAssertEqual(DisplayFilter.slightlyCurvedScanlines.displayName, "Slightly Curved Scanlines")
        XCTAssertEqual(DisplayFilter(rawValue: "scanlines"), .scanlines, "a stored scanlines value keeps its flat meaning")
        for filter in DisplayFilter.allCases {
            XCTAssertFalse(filter.displayName.contains("GameCube"))
            XCTAssertFalse(filter.rawValue.lowercased().contains("gamecube"))
        }
        XCTAssertNil(DisplayFilter(rawValue: "gameCubeTV"))
    }
}

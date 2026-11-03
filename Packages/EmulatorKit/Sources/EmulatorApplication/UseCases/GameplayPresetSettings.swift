import EmulatorDomain
import Foundation

/// The values a game plays with for the settings the gameplay presets control.
public struct GameplayEffectiveValues: Equatable, Sendable {
    public var displayFilter: DisplayFilter
    public var frameBlending: FrameBlending
    public var buttonBounce: Bool
    public var colorCorrection: ColorCorrection
    public var advanceColors: AdvanceColors

    public init(
        displayFilter: DisplayFilter,
        frameBlending: FrameBlending,
        buttonBounce: Bool,
        colorCorrection: ColorCorrection,
        advanceColors: AdvanceColors
    ) {
        self.displayFilter = displayFilter
        self.frameBlending = frameBlending
        self.buttonBounce = buttonBounce
        self.colorCorrection = colorCorrection
        self.advanceColors = advanceColors
    }

    func matches(_ preset: GameplayPresetValues) -> Bool {
        displayFilter == preset.displayFilter
            && frameBlending == preset.frameBlending
            && buttonBounce == preset.buttonBounce
            && preset.colorCorrection.map { $0 == colorCorrection } ?? true
            && preset.advanceColors.map { $0 == advanceColors } ?? true
    }
}

/// Applies and recognizes gameplay presets. Choosing a built-in preset at a scope stores the
/// preset there, not its values, so each game below gets the preset's values for the hardware it
/// runs on, whichever hardware Automatic picks for it. A setting the presets control resolves
/// through the scopes, most specific first: at each scope a value stored for the setting wins,
/// then the preset chosen there when it sets that setting on the game's hardware. A setting
/// nothing sets, or one that can't be read, takes the standard preset's value for the hardware,
/// so an untouched scope shows the standard preset. Custom is derived, never stored.
public struct GameplayPresetSettings: Sendable {
    private let store: any SettingsStore

    /// The settings the presets set. Editing one by hand needs Plus. The screen palette is not one
    /// of them: choosing it is free and no preset changes it.
    public static let controlledKeys: [SettingKey] = [
        .lcdFilter, .frameBlending, .buttonBounce, .colorCorrection, .advanceColors,
    ]

    public init(store: any SettingsStore) {
        self.store = store
    }

    /// What a game on `hardware` plays with, through the scopes `system`, `gameID` and `buildID`
    /// describe.
    public func effectiveValues(
        system: GameSystem,
        gameID: UUID? = nil,
        buildID: UUID? = nil,
        hardware: HardwareModel
    ) -> GameplayEffectiveValues {
        let scopes = SettingsResolver.precedence(system: system, gameID: gameID, buildID: buildID)
        // The first value found decides, as for other settings: one that can't be read plays the
        // default rather than what a parent scope sets.
        func value<Value: Decodable>(_ key: SettingKey, _ type: Value.Type) -> Value? {
            for scope in scopes {
                if let json = try? store.valueJSON(key: key.rawValue, scope: scope) {
                    return try? JSONDecoder().decode(type, from: Data(json.utf8))
                }
                if let preset = presetValue(key, at: scope, hardware: hardware) {
                    return try? preset.decode(type)
                }
            }
            return nil
        }
        let standard = GameplayPresetValues.standard(for: hardware)
        return GameplayEffectiveValues(
            displayFilter: value(.lcdFilter, DisplayFilter.self) ?? standard.displayFilter,
            frameBlending: value(.frameBlending, FrameBlending.self) ?? standard.frameBlending,
            buttonBounce: value(.buttonBounce, Bool.self) ?? standard.buttonBounce,
            colorCorrection: value(.colorCorrection, ColorCorrection.self)
                ?? standard.colorCorrection ?? .defaultValue,
            advanceColors: value(.advanceColors, AdvanceColors.self)
                ?? standard.advanceColors ?? .gameBoyAdvance
        )
    }

    /// The preset in effect for a game on `hardware`.
    public func resolvedPreset(
        system: GameSystem,
        gameID: UUID? = nil,
        buildID: UUID? = nil,
        hardware: HardwareModel
    ) -> GameplayPreset {
        resolvedPreset(system: system, gameID: gameID, buildID: buildID, hardware: [hardware])
    }

    /// The preset in effect for games on each model in `hardware`, such as the models Automatic
    /// picks among for a system: a built-in preset when games on every one of them play it,
    /// otherwise Custom.
    public func resolvedPreset(
        system: GameSystem,
        gameID: UUID? = nil,
        buildID: UUID? = nil,
        hardware: [HardwareModel]
    ) -> GameplayPreset {
        GameplayPreset.builtIn.first { preset in
            !hardware.isEmpty && hardware.allSatisfy { model in
                let values = effectiveValues(system: system, gameID: gameID, buildID: buildID, hardware: model)
                return GameplayPresetValues.values(for: preset, hardware: model).map(values.matches) ?? false
            }
        } ?? .custom
    }

    /// The preset chosen at `scope`, or nil when none is or it can't be read.
    public func storedPreset(at scope: SettingsScope) -> GameplayPreset? {
        guard let preset = storedValue(.gameplayPreset, GameplayPreset.self, at: scope), preset != .custom else {
            return nil
        }
        return preset
    }

    public func apply(
        _ preset: GameplayPreset,
        at scope: SettingsScope,
        hardware: HardwareModel,
        system: GameSystem,
        gameID: UUID? = nil,
        buildID: UUID? = nil
    ) throws {
        try apply(preset, at: scope, hardware: [hardware], system: system, gameID: gameID, buildID: buildID)
    }

    /// Makes `preset` the one in effect at `scope` for games on each model in `hardware`. Custom is
    /// derived and can't be applied. Clears what the scope stores for the presets, then stores the
    /// preset, except that the standard preset stores nothing when nothing above sets another.
    public func apply(
        _ preset: GameplayPreset,
        at scope: SettingsScope,
        hardware: [HardwareModel],
        system: GameSystem,
        gameID: UUID? = nil,
        buildID: UUID? = nil
    ) throws {
        guard preset != .custom else { return }
        try reset(at: scope)
        if preset == .standard,
           resolvedPreset(system: system, gameID: gameID, buildID: buildID, hardware: hardware) == .standard {
            return
        }
        try store.set(preset, key: SettingKey.gameplayPreset.rawValue, scope: scope)
    }

    /// Removes the preset and every setting the presets control at this scope, revealing the
    /// inherited values.
    public func reset(at scope: SettingsScope) throws {
        for key in Self.controlledKeys + [.gameplayPreset] {
            try store.removeValue(key: key.rawValue, scope: scope)
        }
    }

    /// After the Model changes at `scope`: when the scope stores no preset but stores its own
    /// values for the settings the presets control, and on the old hardware they made a built-in
    /// preset, the scope gets that preset, which follows the new hardware. A stored preset already
    /// follows the hardware, and inherited and unset values are left alone.
    public func retargetBuiltInPreset(
        from oldHardware: [HardwareModel],
        to newHardware: [HardwareModel],
        at scope: SettingsScope,
        system: GameSystem,
        gameID: UUID? = nil,
        buildID: UUID? = nil
    ) throws {
        guard oldHardware != newHardware, storedPreset(at: scope) == nil else { return }
        let storesOwnValues = try Self.controlledKeys.contains {
            try store.valueJSON(key: $0.rawValue, scope: scope) != nil
        }
        guard storesOwnValues else { return }
        let preset = resolvedPreset(system: system, gameID: gameID, buildID: buildID, hardware: oldHardware)
        guard preset != .custom else { return }
        try apply(preset, at: scope, hardware: newHardware, system: system, gameID: gameID, buildID: buildID)
    }

    /// What an editor for `key`, one of `controlledKeys`, shows at `scope` for a game on
    /// `hardware`: the value stored there, and the value in effect without it. That is the value of
    /// the preset chosen at `scope` when the preset sets `key`, and otherwise what the scopes below
    /// give, a stored value or a preset's.
    public func edit(
        _ key: SettingKey,
        at scope: SettingsScope,
        system: GameSystem,
        gameID: UUID? = nil,
        buildID: UUID? = nil,
        hardware: HardwareModel
    ) throws -> ScopedSetting {
        let scopes = SettingsResolver.precedence(system: system, gameID: gameID, buildID: buildID)
        guard let index = scopes.firstIndex(of: scope) else {
            throw SettingsResolverError.scopeOutsideContext(scope)
        }
        var inherited = presetValue(key, at: scope, hardware: hardware)
        if inherited == nil {
            for parent in scopes[(index + 1)...] {
                if let json = try store.valueJSON(key: key.rawValue, scope: parent) {
                    inherited = ResolvedSetting(key: key.rawValue, valueJSON: json, source: parent)
                    break
                }
                if let value = presetValue(key, at: parent, hardware: hardware) {
                    inherited = value
                    break
                }
            }
        }
        return ScopedSetting(
            key: key.rawValue,
            scope: scope,
            overrideJSON: try store.valueJSON(key: key.rawValue, scope: scope),
            inherited: inherited
        )
    }

    /// The value stored for `key` at `scope`, or nil when none is or it can't be read.
    private func storedValue<Value: Decodable>(_ key: SettingKey, _ type: Value.Type, at scope: SettingsScope) -> Value? {
        guard let json = try? store.valueJSON(key: key.rawValue, scope: scope) else { return nil }
        return try? JSONDecoder().decode(type, from: Data(json.utf8))
    }

    /// The value the preset chosen at `scope` sets for `key` on `hardware`, or nil when no preset
    /// is chosen there or it leaves `key` alone on that hardware.
    private func presetValue(_ key: SettingKey, at scope: SettingsScope, hardware: HardwareModel) -> ResolvedSetting? {
        guard let preset = storedPreset(at: scope),
              let values = GameplayPresetValues.values(for: preset, hardware: hardware),
              let json = Self.json(of: values, key: key) else { return nil }
        return ResolvedSetting(key: key.rawValue, valueJSON: json, source: scope, preset: preset)
    }

    /// The preset's value for `key` as stored JSON, or nil when the preset leaves it alone.
    private static func json(of values: GameplayPresetValues, key: SettingKey) -> String? {
        func encoded<Value: Encodable>(_ value: Value?) -> String? {
            guard let value, let data = try? JSONEncoder().encode(value) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        return switch key {
        case .lcdFilter: encoded(values.displayFilter)
        case .frameBlending: encoded(values.frameBlending)
        case .buttonBounce: encoded(values.buttonBounce)
        case .colorCorrection: encoded(values.colorCorrection)
        case .advanceColors: encoded(values.advanceColors)
        default: nil
        }
    }
}

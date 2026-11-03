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

/// Applies and recognizes gameplay presets without storing a preset. The low-level settings remain
/// the source of truth. A setting no scope sets, or one that can't be read, takes the standard
/// preset's value for the hardware, so an untouched scope shows the standard preset.
public struct GameplayPresetSettings: Sendable {
    private let store: any SettingsStore
    private let resolver: SettingsResolver

    /// The settings the presets write. Editing one by hand needs Plus. The screen palette is not
    /// one of them: choosing it is free and no preset changes it.
    public static let controlledKeys: [SettingKey] = [
        .lcdFilter, .frameBlending, .buttonBounce, .colorCorrection, .advanceColors,
    ]

    public init(store: any SettingsStore) {
        self.store = store
        self.resolver = SettingsResolver(store: store)
    }

    public func effectiveValues(
        system: GameSystem,
        gameID: UUID? = nil,
        buildID: UUID? = nil,
        hardware: HardwareModel
    ) -> GameplayEffectiveValues {
        func stored<Value: Decodable>(_ type: Value.Type, _ key: SettingKey) -> Value? {
            try? resolver.decode(type, key: key.rawValue, system: system, gameID: gameID, buildID: buildID)
        }
        let standard = GameplayPresetValues.standard(for: hardware)
        return GameplayEffectiveValues(
            displayFilter: stored(DisplayFilter.self, .lcdFilter) ?? standard.displayFilter,
            frameBlending: stored(FrameBlending.self, .frameBlending) ?? standard.frameBlending,
            buttonBounce: stored(Bool.self, .buttonBounce) ?? standard.buttonBounce,
            colorCorrection: stored(ColorCorrection.self, .colorCorrection)
                ?? standard.colorCorrection ?? .defaultValue,
            advanceColors: stored(AdvanceColors.self, .advanceColors)
                ?? standard.advanceColors ?? .gameBoyAdvance
        )
    }

    public func resolvedPreset(
        system: GameSystem,
        gameID: UUID? = nil,
        buildID: UUID? = nil,
        hardware: HardwareModel
    ) -> GameplayPreset {
        let values = effectiveValues(system: system, gameID: gameID, buildID: buildID, hardware: hardware)
        return GameplayPreset.builtIn.first { preset in
            GameplayPresetValues.values(for: preset, hardware: hardware).map(values.matches) ?? false
        } ?? .custom
    }

    /// Makes `preset` the one in effect at `scope` for `hardware`. Custom is derived and can't be
    /// applied. The standard preset first clears this scope's preset settings, since unset values
    /// already follow it, and writes values only when a parent scope sets something else.
    public func apply(
        _ preset: GameplayPreset,
        at scope: SettingsScope,
        hardware: HardwareModel,
        system: GameSystem,
        gameID: UUID? = nil,
        buildID: UUID? = nil
    ) throws {
        guard let values = GameplayPresetValues.values(for: preset, hardware: hardware) else { return }
        if preset == .standard {
            for key in Self.keys(of: values) {
                try store.removeValue(key: key.rawValue, scope: scope)
            }
            if resolvedPreset(system: system, gameID: gameID, buildID: buildID, hardware: hardware) == .standard {
                return
            }
        }
        try store.set(values.displayFilter, key: SettingKey.lcdFilter.rawValue, scope: scope)
        try store.set(values.frameBlending, key: SettingKey.frameBlending.rawValue, scope: scope)
        try store.set(values.buttonBounce, key: SettingKey.buttonBounce.rawValue, scope: scope)
        if let value = values.colorCorrection {
            try store.set(value, key: SettingKey.colorCorrection.rawValue, scope: scope)
        }
        if let value = values.advanceColors {
            try store.set(value, key: SettingKey.advanceColors.rawValue, scope: scope)
        }
    }

    /// Removes every setting the presets control at this scope, revealing the inherited values.
    public func reset(at scope: SettingsScope) throws {
        for key in Self.controlledKeys {
            try store.removeValue(key: key.rawValue, scope: scope)
        }
    }

    /// After the Model changes at `scope`: when this scope stores its own preset settings and they
    /// made a built-in preset on the old hardware, writes that preset's values for the new
    /// hardware. Inherited and unset values are left alone; unset ones already follow the hardware.
    public func retargetBuiltInPreset(
        from oldHardware: HardwareModel,
        to newHardware: HardwareModel,
        at scope: SettingsScope,
        system: GameSystem,
        gameID: UUID? = nil,
        buildID: UUID? = nil
    ) throws {
        guard oldHardware != newHardware else { return }
        let storesOwnValues = try Self.controlledKeys.contains {
            try store.valueJSON(key: $0.rawValue, scope: scope) != nil
        }
        guard storesOwnValues else { return }
        let preset = resolvedPreset(system: system, gameID: gameID, buildID: buildID, hardware: oldHardware)
        guard preset != .custom else { return }
        try apply(preset, at: scope, hardware: newHardware, system: system, gameID: gameID, buildID: buildID)
    }

    private static func keys(of values: GameplayPresetValues) -> [SettingKey] {
        [.lcdFilter, .frameBlending, .buttonBounce]
            + (values.colorCorrection == nil ? [] : [.colorCorrection])
            + (values.advanceColors == nil ? [] : [.advanceColors])
    }
}

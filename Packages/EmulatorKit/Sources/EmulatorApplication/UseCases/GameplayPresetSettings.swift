import EmulatorDomain
import Foundation

/// Applies and recognizes gameplay presets without adding a persisted preset setting. The existing
/// low-level settings remain the source of truth and existing overrides remain decodable.
public struct GameplayPresetSettings: Sendable {
    private let store: any SettingsStore
    private let resolver: SettingsResolver

    public static let controlledKeys: [SettingKey] = [
        .lcdFilter, .frameBlending, .buttonBounce, .colorCorrection, .dmgPalette, .advanceColors,
    ]

    public init(store: any SettingsStore) {
        self.store = store
        self.resolver = SettingsResolver(store: store)
    }

    public func retargetBuiltInPreset(
        from oldHardware: HardwareModel,
        to newHardware: HardwareModel,
        at scope: SettingsScope,
        system: GameSystem,
        gameID: UUID? = nil,
        buildID: UUID? = nil
    ) throws {
        guard oldHardware != newHardware else { return }
        let preset = try resolvedPreset(system: system, gameID: gameID, buildID: buildID, hardware: oldHardware)
        if preset != .custom { try apply(preset, at: scope, hardware: newHardware) }
    }

    public func resolvedPreset(
        system: GameSystem,
        gameID: UUID? = nil,
        buildID: UUID? = nil,
        hardware: HardwareModel
    ) throws -> GameplayPreset {
        if let clean = GameplayPresetValues.values(for: .clean, hardware: hardware),
           try matches(clean, system: system, gameID: gameID, buildID: buildID) {
            return .clean
        }
        if let accurate = GameplayPresetValues.values(for: .accurate, hardware: hardware),
           try matches(accurate, system: system, gameID: gameID, buildID: buildID) {
            return .accurate
        }
        return .custom
    }

    /// Writes a built-in preset at exactly this scope. Custom is a derived state and cannot be
    /// applied directly; editing any controlled setting makes the result Custom.
    public func apply(_ preset: GameplayPreset, at scope: SettingsScope, hardware: HardwareModel) throws {
        guard let values = GameplayPresetValues.values(for: preset, hardware: hardware) else { return }
        try store.set(values.displayFilter, key: SettingKey.lcdFilter.rawValue, scope: scope)
        try store.set(values.frameBlending, key: SettingKey.frameBlending.rawValue, scope: scope)
        try store.set(values.buttonBounce, key: SettingKey.buttonBounce.rawValue, scope: scope)
        if let value = values.colorCorrection {
            try store.set(value, key: SettingKey.colorCorrection.rawValue, scope: scope)
        }
        if let value = values.dmgPalette {
            try store.set(value, key: SettingKey.dmgPalette.rawValue, scope: scope)
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

    private func matches(
        _ expected: GameplayPresetValues,
        system: GameSystem,
        gameID: UUID?,
        buildID: UUID?
    ) throws -> Bool {
        let filter = try resolver.decode(
            DisplayFilter.self, key: SettingKey.lcdFilter.rawValue,
            system: system, gameID: gameID, buildID: buildID
        ) ?? .off
        guard filter.selectionValue == expected.displayFilter else { return false }

        let blending = try resolver.decode(
            FrameBlending.self, key: SettingKey.frameBlending.rawValue,
            system: system, gameID: gameID, buildID: buildID
        ) ?? .off
        guard blending == expected.frameBlending else { return false }

        let bounce = try resolver.decode(
            Bool.self, key: SettingKey.buttonBounce.rawValue,
            system: system, gameID: gameID, buildID: buildID
        ) ?? true
        guard bounce == expected.buttonBounce else { return false }

        if let expectedValue = expected.colorCorrection {
            let value = try resolver.decode(
                ColorCorrection.self, key: SettingKey.colorCorrection.rawValue,
                system: system, gameID: gameID, buildID: buildID
            ) ?? .defaultValue
            guard value == expectedValue else { return false }
        }
        if let expectedValue = expected.dmgPalette {
            let value = try resolver.decode(
                DMGPalette.self, key: SettingKey.dmgPalette.rawValue,
                system: system, gameID: gameID, buildID: buildID
            ) ?? .defaultValue
            guard value == expectedValue else { return false }
        }
        if let expectedValue = expected.advanceColors {
            let value = try resolver.decode(
                AdvanceColors.self, key: SettingKey.advanceColors.rawValue,
                system: system, gameID: gameID, buildID: buildID
            ) ?? .gameBoyAdvance
            guard value == expectedValue else { return false }
        }
        return true
    }
}

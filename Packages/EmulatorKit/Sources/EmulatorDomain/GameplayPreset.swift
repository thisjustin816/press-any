/// Built-in picture treatments. Raw values are stored under the existing `lcdFilter` setting key,
/// whose name is kept for compatibility with v1.0 settings and backups.
public enum DisplayFilter: String, Codable, Sendable, CaseIterable {
    case off
    case lcd1x
    case lcd3x
    case crt240p
    /// Legacy persisted identifier retained for compatibility. The user-facing treatment is CRT 480i.
    case gameCubeTV

    /// Every display treatment is available on every hardware model. Built-in presets still choose
    /// the historically appropriate treatment; manual choices are intentionally unrestricted.
    public static func selectable(for _: HardwareModel) -> [Self] { allCases }

    public var displayName: String {
        switch self {
        case .off: "Off"
        case .lcd1x: "LCD 1×"
        case .lcd3x: "LCD 3×"
        case .crt240p: "CRT 240p"
        case .gameCubeTV: "CRT 480i"
        }
    }
}

/// A high-level gameplay presentation. Custom is derived when the controlled low-level settings
/// do not exactly match either built-in preset; it is never stored independently.
public enum GameplayPreset: String, Codable, Sendable, CaseIterable {
    case clean
    case accurate
    case custom

    public var displayName: String {
        switch self {
        case .clean: "Clean"
        case .accurate: "Accurate"
        case .custom: "Custom"
        }
    }
}

/// The low-level settings a built-in gameplay preset controls for one resolved hardware model.
public struct GameplayPresetValues: Equatable, Sendable {
    public let displayFilter: DisplayFilter
    public let frameBlending: FrameBlending
    public let buttonBounce: Bool
    public let colorCorrection: ColorCorrection?
    public let dmgPalette: DMGPalette?
    public let advanceColors: AdvanceColors?

    public init(
        displayFilter: DisplayFilter,
        frameBlending: FrameBlending,
        buttonBounce: Bool,
        colorCorrection: ColorCorrection? = nil,
        dmgPalette: DMGPalette? = nil,
        advanceColors: AdvanceColors? = nil
    ) {
        self.displayFilter = displayFilter
        self.frameBlending = frameBlending
        self.buttonBounce = buttonBounce
        self.colorCorrection = colorCorrection
        self.dmgPalette = dmgPalette
        self.advanceColors = advanceColors
    }

    /// `hardware` is expected to be resolved rather than Automatic. Automatic is treated as the
    /// original Game Boy only as a defensive fallback.
    public static func values(for preset: GameplayPreset, hardware: HardwareModel) -> Self? {
        switch preset {
        case .custom:
            return nil
        case .clean:
            switch hardware {
            case .automatic, .gameBoy, .gameBoyPocket:
                return Self(displayFilter: .off, frameBlending: .off, buttonBounce: false, dmgPalette: .cgbLeftB)
            case .superGameBoy, .superGameBoy2:
                return Self(displayFilter: .off, frameBlending: .off, buttonBounce: false)
            case .gameBoyColor:
                return Self(displayFilter: .off, frameBlending: .off, buttonBounce: false, colorCorrection: .off)
            case .gameBoyAdvance, .gameBoyPlayer:
                return Self(
                    displayFilter: .off,
                    frameBlending: .off,
                    buttonBounce: false,
                    colorCorrection: .off,
                    advanceColors: .gameBoyColor
                )
            }
        case .accurate:
            switch hardware {
            case .automatic, .gameBoy:
                return Self(displayFilter: .lcd1x, frameBlending: .blend, buttonBounce: true, dmgPalette: .dmgGreen)
            case .gameBoyPocket:
                return Self(displayFilter: .lcd1x, frameBlending: .blend, buttonBounce: true, dmgPalette: .pocket)
            case .superGameBoy, .superGameBoy2:
                return Self(displayFilter: .crt240p, frameBlending: .off, buttonBounce: false)
            case .gameBoyColor:
                return Self(displayFilter: .lcd3x, frameBlending: .blend, buttonBounce: true, colorCorrection: .accurate)
            case .gameBoyAdvance:
                return Self(
                    displayFilter: .lcd3x,
                    frameBlending: .blend,
                    buttonBounce: true,
                    colorCorrection: .accurate,
                    advanceColors: .gameBoyAdvance
                )
            case .gameBoyPlayer:
                return Self(
                    displayFilter: .gameCubeTV,
                    frameBlending: .off,
                    buttonBounce: false,
                    colorCorrection: .off,
                    advanceColors: .gameBoyColor
                )
            }
        }
    }
}

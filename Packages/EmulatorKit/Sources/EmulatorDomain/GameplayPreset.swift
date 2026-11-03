/// Built-in picture treatments. Raw values are stored under the `lcdFilter` setting key, whose name
/// is kept for v1.0 settings and backups; `lcd1x` and `lcd3x` are the v1.0 values and keep their
/// v1.0 look. An unknown stored value reads as unset.
public enum DisplayFilter: String, Codable, Sendable, CaseIterable {
    case off
    /// A faint grid between pixels.
    case lcd1x
    /// The faint grid with red, green and blue bands in each pixel.
    case lcd3x
    /// SameBoy's monochrome LCD filter.
    case monochromeLCD
    /// fishku's Authentic GBC subpixels.
    case authenticGBC
    /// SameBoy's color LCD filter with the Game Boy Advance color profile.
    case gbaLCD
    /// The faint grid with the backlit Game Boy Advance SP (AGS-101) color profile.
    case sp101LCD
    /// Sharp scanlines on a gently curved screen, without a phosphor mask or glow.
    case scanlines
    /// A consumer television showing a 240-line picture.
    case crt240p
    /// A flat late-model television showing each line twice, as a 480-line picture.
    case crt480p

    /// Every display treatment is available on every hardware model. Built-in presets still choose
    /// the historically appropriate one.
    public static var selectable: [Self] { allCases }

    public var displayName: String {
        switch self {
        case .off: "Off"
        case .lcd1x: "Pixel Grid"
        case .lcd3x: "RGB Subpixels"
        case .monochromeLCD: "Monochrome LCD"
        case .authenticGBC: "Game Boy Color LCD"
        case .gbaLCD: "Game Boy Advance LCD"
        case .sp101LCD: "Backlit GBA SP LCD"
        case .scanlines: "Scanlines"
        case .crt240p: "CRT 240p"
        case .crt480p: "CRT 480p"
        }
    }
}

/// A high-level gameplay presentation. Custom is derived when the controlled low-level settings
/// match no built-in preset; no preset is stored.
public enum GameplayPreset: String, Codable, Sendable, CaseIterable {
    /// How players remember the screen, cleaned up. Unset settings resolve to it.
    case standard
    case accurate
    case clean
    case custom

    /// The standard preset's name, in one place so it can be renamed.
    public static let standardName = "Nostalgic"

    public static let builtIn: [Self] = [.standard, .accurate, .clean]

    public var displayName: String {
        switch self {
        case .standard: Self.standardName
        case .accurate: "Accurate"
        case .clean: "Clean"
        case .custom: "Custom"
        }
    }
}

/// The low-level settings a built-in gameplay preset controls for one resolved hardware model. A
/// nil value is a setting the preset leaves alone on that hardware. Screen palettes are never
/// part of a preset.
public struct GameplayPresetValues: Equatable, Sendable {
    public let displayFilter: DisplayFilter
    public let frameBlending: FrameBlending
    public let buttonBounce: Bool
    public let colorCorrection: ColorCorrection?
    public let advanceColors: AdvanceColors?

    public init(
        displayFilter: DisplayFilter,
        frameBlending: FrameBlending,
        buttonBounce: Bool,
        colorCorrection: ColorCorrection? = nil,
        advanceColors: AdvanceColors? = nil
    ) {
        self.displayFilter = displayFilter
        self.frameBlending = frameBlending
        self.buttonBounce = buttonBounce
        self.colorCorrection = colorCorrection
        self.advanceColors = advanceColors
    }

    /// What unset settings resolve to on `hardware`.
    public static func standard(for hardware: HardwareModel) -> Self {
        values(for: .standard, hardware: hardware)!
    }

    /// `hardware` is expected to be resolved. Automatic is treated as the original Game Boy.
    /// Only Clean and the television models turn button bounce off; the television models because their controllers are not the Game Boy's
    /// own buttons. A Game Boy or Pocket shows a palette, which color correction doesn't apply to
    /// in the way the presets mean, so those presets leave correction alone.
    public static func values(for preset: GameplayPreset, hardware: HardwareModel) -> Self? {
        switch (preset, hardware) {
        case (.custom, _):
            return nil

        case (.clean, .automatic), (.clean, .gameBoy), (.clean, .gameBoyPocket):
            return Self(displayFilter: .off, frameBlending: .off, buttonBounce: false)
        case (.clean, .superGameBoy), (.clean, .superGameBoy2), (.clean, .gameBoyColor):
            return Self(displayFilter: .off, frameBlending: .off, buttonBounce: false, colorCorrection: .off)
        case (.clean, .gameBoyAdvance), (.clean, .gameBoyPlayer):
            return Self(
                displayFilter: .off, frameBlending: .off, buttonBounce: false,
                colorCorrection: .off, advanceColors: .gameBoyAdvance
            )

        case (.standard, .automatic), (.standard, .gameBoy), (.standard, .gameBoyPocket):
            return Self(displayFilter: .lcd1x, frameBlending: .blend, buttonBounce: true)
        case (.standard, .superGameBoy), (.standard, .superGameBoy2):
            return Self(displayFilter: .scanlines, frameBlending: .off, buttonBounce: false, colorCorrection: .balanced)
        case (.standard, .gameBoyColor):
            return Self(displayFilter: .lcd1x, frameBlending: .blend, buttonBounce: true, colorCorrection: .balanced)
        case (.standard, .gameBoyAdvance):
            // The backlit SP's profile colors the picture, so the core leaves colors as they are.
            return Self(
                displayFilter: .sp101LCD, frameBlending: .blend, buttonBounce: true,
                colorCorrection: .off, advanceColors: .gameBoyColor
            )
        case (.standard, .gameBoyPlayer):
            return Self(
                displayFilter: .scanlines, frameBlending: .off, buttonBounce: false,
                colorCorrection: .balanced, advanceColors: .gameBoyColor
            )

        case (.accurate, .automatic), (.accurate, .gameBoy):
            // The original screen's slow response leaves a trail behind moving things.
            return Self(displayFilter: .monochromeLCD, frameBlending: .ghosting, buttonBounce: true)
        case (.accurate, .gameBoyPocket):
            return Self(displayFilter: .monochromeLCD, frameBlending: .blend, buttonBounce: true)
        case (.accurate, .superGameBoy), (.accurate, .superGameBoy2):
            return Self(displayFilter: .crt240p, frameBlending: .off, buttonBounce: false, colorCorrection: .balanced)
        case (.accurate, .gameBoyColor):
            return Self(displayFilter: .authenticGBC, frameBlending: .blend, buttonBounce: true, colorCorrection: .lowContrast)
        case (.accurate, .gameBoyAdvance):
            // The Game Boy Advance profile darkens the picture as that screen does.
            return Self(
                displayFilter: .gbaLCD, frameBlending: .blend, buttonBounce: true,
                colorCorrection: .off, advanceColors: .gameBoyAdvance
            )
        case (.accurate, .gameBoyPlayer):
            return Self(
                displayFilter: .crt480p, frameBlending: .off, buttonBounce: false,
                colorCorrection: .off, advanceColors: .gameBoyAdvance
            )
        }
    }
}

/// Built-in picture treatments. Raw values are stored under the `lcdFilter` setting key, whose name
/// is kept for v1.0 settings and backups; `lcd1x` and `lcd3x` are the v1.0 values and keep their
/// v1.0 look. An unknown stored value reads as unset.
public enum DisplayFilter: String, Codable, Sendable, CaseIterable {
    case off
    /// A faint grid between pixels.
    case lcd1x
    /// The faint grid with red, green and blue bands in each pixel.
    case lcd3x
    /// A Game Boy's or Pocket's screen as BGB measured it, with light gaps between pixels.
    case monochromeLCD
    /// fishku's Authentic GBC subpixels.
    case authenticGBC
    /// SameBoy's color LCD filter with the Game Boy Advance color profile.
    case gbaLCD
    /// The faint grid with the backlit Game Boy Advance SP (AGS-101) color profile.
    case sp101LCD
    /// Sharp scanlines on a flat picture, without curvature, rounded corners, a phosphor mask or
    /// glow.
    case scanlines
    /// The sharp scanlines on a curved screen with small rounded corners, as Nostalgic shows a
    /// Super Game Boy's television.
    case curvedScanlines
    /// The sharp scanlines on a slightly curved screen, as Nostalgic shows a Game Boy Player's
    /// later television.
    case slightlyCurvedScanlines
    /// A 1990s consumer television showing a 240-line picture.
    case crt240p
    /// A flatter 2000s television showing each line twice, as a 480-line picture.
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
        case .curvedScanlines: "Curved Scanlines"
        case .slightlyCurvedScanlines: "Slightly Curved Scanlines"
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

/// The hardware a game plays on, as the gameplay presets choose their values for it. A game with
/// Game Boy Advance features (`GameBoyAdvanceFeatures`) brightens its own colors on a Game Boy
/// Advance, so the presets tell that game's Game Boy Advance apart from one any other game plays
/// on, whether Automatic picked it or Model was set to it by hand.
public struct PresetHardware: Hashable, Sendable {
    /// Resolved: the model the game runs on, never Automatic but by mistake.
    public let model: HardwareModel
    /// A Game Boy Advance playing a game with Game Boy Advance features.
    public let forGameBoyAdvanceFeatures: Bool

    /// `model` chosen by hand.
    public init(_ model: HardwareModel) {
        self.model = model
        forGameBoyAdvanceFeatures = false
    }

    /// `model` as Automatic picked it.
    public init(automatic model: HardwareModel) {
        self.model = model
        forGameBoyAdvanceFeatures = model == .gameBoyAdvance
    }

    /// `model` chosen by hand for a game with Game Boy Advance features: on a Game Boy Advance the
    /// presets treat it as Automatic's pick would be.
    public init(chosenForGameWithGameBoyAdvanceFeatures model: HardwareModel) {
        self.model = model
        forGameBoyAdvanceFeatures = model == .gameBoyAdvance
    }
}

/// The low-level settings a built-in gameplay preset controls for one resolved hardware model. A
/// nil value is a setting the preset leaves alone on that hardware. Screen palettes are never
/// part of a preset.
public struct GameplayPresetValues: Equatable, Sendable {
    public let displayFilter: DisplayFilter
    public let frameBlending: FrameBlending
    public let buttonBounce: Bool
    public let audioFilter: AudioFilter
    public let colorCorrection: ColorCorrection?
    public let advanceColors: AdvanceColors?

    public init(
        displayFilter: DisplayFilter,
        frameBlending: FrameBlending,
        buttonBounce: Bool,
        audioFilter: AudioFilter,
        colorCorrection: ColorCorrection? = nil,
        advanceColors: AdvanceColors? = nil
    ) {
        self.displayFilter = displayFilter
        self.frameBlending = frameBlending
        self.buttonBounce = buttonBounce
        self.audioFilter = audioFilter
        self.colorCorrection = colorCorrection
        self.advanceColors = advanceColors
    }

    /// What unset settings resolve to on `hardware`.
    public static func standard(for hardware: PresetHardware) -> Self {
        values(for: .standard, hardware: hardware)!
    }

    /// What unset settings resolve to on `hardware` chosen by hand.
    public static func standard(for hardware: HardwareModel) -> Self {
        standard(for: PresetHardware(hardware))
    }

    /// `preset`'s values on `hardware` chosen by hand.
    public static func values(for preset: GameplayPreset, hardware: HardwareModel) -> Self? {
        values(for: preset, hardware: PresetHardware(hardware))
    }

    /// `hardware` is expected to be resolved; callers pass the model each game runs on. Automatic
    /// arrives only by mistake and reads as a Game Boy Pocket, the model Automatic picks for most
    /// games.
    /// Only Clean turns button bounce and the audio filter off: Nostalgic and Accurate bounce and
    /// filter on every model, the television models included. A Game Boy or Pocket shows a palette, which color correction
    /// doesn't apply to in the way the presets mean, so those presets leave correction alone.
    public static func values(for preset: GameplayPreset, hardware: PresetHardware) -> Self? {
        switch (preset, hardware.model) {
        case (.custom, _):
            return nil

        case (.clean, .automatic), (.clean, .gameBoy), (.clean, .gameBoyPocket):
            return Self(displayFilter: .off, frameBlending: .off, buttonBounce: false, audioFilter: .off)
        case (.clean, .superGameBoy), (.clean, .superGameBoy2), (.clean, .gameBoyColor):
            return Self(displayFilter: .off, frameBlending: .off, buttonBounce: false, audioFilter: .off, colorCorrection: .off)
        case (.clean, .gameBoyAdvance), (.clean, .gameBoyPlayer):
            return Self(
                displayFilter: .off, frameBlending: .off, buttonBounce: false, audioFilter: .off,
                colorCorrection: .off, advanceColors: .gameBoyAdvance
            )

        case (.standard, .automatic), (.standard, .gameBoy), (.standard, .gameBoyPocket):
            return Self(displayFilter: .lcd1x, frameBlending: .blend, buttonBounce: true, audioFilter: .accurate)
        case (.standard, .superGameBoy), (.standard, .superGameBoy2):
            return Self(displayFilter: .curvedScanlines, frameBlending: .off, buttonBounce: true, audioFilter: .accurate, colorCorrection: .balanced)
        case (.standard, .gameBoyColor):
            // The screen as people remember it: Modern Accurate softened, as a bright backlit
            // screen shows it.
            return Self(displayFilter: .lcd1x, frameBlending: .blend, buttonBounce: true, audioFilter: .accurate, colorCorrection: .soft)
        case (.standard, .gameBoyAdvance) where hardware.forGameBoyAdvanceFeatures:
            // The game brightens its own colors for the Game Boy Advance's darker screen, which
            // Original would show washed out. Modern Accurate darkens them as that screen does, and
            // with the backlit SP's profile on top comes closest to the same colors on a Game Boy
            // Color in Nostalgic (docs/display-presets.md).
            return Self(
                displayFilter: .sp101LCD, frameBlending: .blend, buttonBounce: true, audioFilter: .accurate,
                colorCorrection: .accurate, advanceColors: .gameBoyAdvance
            )
        case (.standard, .gameBoyAdvance):
            // The backlit SP's profile colors the picture, so the core leaves colors as they are.
            return Self(
                displayFilter: .sp101LCD, frameBlending: .blend, buttonBounce: true, audioFilter: .accurate,
                colorCorrection: .off, advanceColors: .gameBoyColor
            )
        case (.standard, .gameBoyPlayer):
            return Self(
                displayFilter: .slightlyCurvedScanlines, frameBlending: .off, buttonBounce: true, audioFilter: .accurate,
                colorCorrection: .balanced, advanceColors: .gameBoyColor
            )

        case (.accurate, .gameBoy):
            // The original screen's slow response leaves a trail behind moving things.
            return Self(displayFilter: .monochromeLCD, frameBlending: .ghosting, buttonBounce: true, audioFilter: .accurate)
        case (.accurate, .automatic), (.accurate, .gameBoyPocket):
            return Self(displayFilter: .monochromeLCD, frameBlending: .blend, buttonBounce: true, audioFilter: .accurate)
        case (.accurate, .superGameBoy), (.accurate, .superGameBoy2):
            return Self(displayFilter: .crt240p, frameBlending: .off, buttonBounce: true, audioFilter: .accurate, colorCorrection: .balanced)
        case (.accurate, .gameBoyColor):
            // Reduce Contrast's white and black (#dbdfd7, #282420, 40:1) are close to BGB's
            // measured Game Boy Color in light (#d9e1c6, #17282d, 38:1).
            return Self(displayFilter: .authenticGBC, frameBlending: .blend, buttonBounce: true, audioFilter: .accurate, colorCorrection: .reduceContrast)
        case (.accurate, .gameBoyAdvance):
            // The Game Boy Advance profile darkens the picture as that screen does.
            return Self(
                displayFilter: .gbaLCD, frameBlending: .blend, buttonBounce: true, audioFilter: .accurate,
                colorCorrection: .off, advanceColors: .gameBoyAdvance
            )
        case (.accurate, .gameBoyPlayer):
            return Self(
                displayFilter: .crt480p, frameBlending: .off, buttonBounce: true, audioFilter: .accurate,
                colorCorrection: .off, advanceColors: .gameBoyAdvance
            )
        }
    }
}

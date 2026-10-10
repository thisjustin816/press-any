import Foundation

public enum SettingsScope: Hashable, Sendable {
    case app
    case system(GameSystem)
    case game(UUID)
    case build(UUID)

    public var databaseType: String {
        switch self {
        case .app: "app"
        case .system: "system"
        case .game: "game"
        case .build: "build"
        }
    }

    public var databaseID: String {
        switch self {
        case .app: "app"
        case .system(let system): system.rawValue
        case .game(let id), .build(let id): id.uuidString.lowercased()
        }
    }
}

public struct LaunchContext: Hashable, Sendable {
    public let gameID: UUID
    public let buildID: UUID
    public let saveProfileID: UUID

    public init(gameID: UUID, buildID: UUID, saveProfileID: UUID) {
        self.gameID = gameID
        self.buildID = buildID
        self.saveProfileID = saveProfileID
    }
}

/// Keys in the settings store. The raw values are stored, so renaming a case must not change them.
public enum SettingKey: String, Sendable, CaseIterable {
    /// Bool, unset means false. Library launches start past the boot logo when true; Quick Play
    /// always skips it.
    case skipBootAnimation
    /// `AutoResumePolicy`, unset means `.always`. Applies when a library game launches with a
    /// resumable Auto State and when the app returns to the foreground mid-session.
    case autoResumePolicy
    /// The on-screen controller layout's raw value (GameplayInput's `TouchControlStyle`), unset
    /// means `gameBoy`.
    case controllerLayout
    /// The controller theme's raw value (GameplayInput's `ControllerTheme`), unset means
    /// `matchSystem`.
    case controllerTheme
    /// The game picture's scaling (GameplayInput's `ScreenScaling`), unset means `integer`.
    case screenScaling
    /// `LCDFilter`, unset means `.off`. Independent of the picture’s scaling.
    case lcdFilter
    /// `ColorCorrection`, unset means `.balanced`.
    case colorCorrection = "colorCorrection"
    /// `DMGPalette`, unset means `.dmgGreen`.
    case dmgPalette = "dmgPalette"
    /// `FrameBlending`, unset means `.off`.
    case frameBlending
    /// `FastForwardSpeed`, unset means `.x2`.
    case fastForwardSpeed
    /// `FastForwardAudio`, unset means `.muted`.
    case fastForwardAudio
    /// `SoundMode`, unset means `.followSilentSwitch`.
    case soundMode
    /// Bool, unset means false. When true, tapping the game picture opens the game menu, as tapping
    /// the logo always does.
    case tapGameForMenu
    /// Bool, unset means true. With a controller connected the touch controls hide, and a touch
    /// brings them back until the next controller button press.
    case hideTouchControlsWithController
    /// `TouchHaptics`, unset means `.light`.
    case touchHaptics
    /// Which way gameplay faces (GameplayInput's `ScreenOrientation`), unset means `automatic`.
    case orientation
    /// `SaveStateSlots`, App scope only; unset means `.off`.
    case saveStateSlots
    /// Bool, App scope only; unset means false.
    case nameNewStates
    /// `KeepSaveStates`, App scope only; unset means `.all`.
    case keepSaveStates
    /// `KeepAutoStates`, App scope only; unset means `.five`.
    case keepAutoStates
    /// `TimedStates`, unset means `.off`.
    case timedStates

    public var isAppOnly: Bool {
        switch self {
        case .saveStateSlots, .nameNewStates, .keepSaveStates, .keepAutoStates: true
        default: false
        }
    }
}

/// How strongly the on-screen controls tap back when pressed. Raw values are stored in settings.
public enum TouchHaptics: String, Codable, Sendable, CaseIterable {
    case off
    case light
    case medium
}

/// Whether game sound plays. Every mode plays alongside other apps' audio. Raw values are stored
/// in settings.
public enum SoundMode: String, Codable, Sendable, CaseIterable {
    /// Silent when the ring/silent switch is set to silent.
    case followSilentSwitch
    /// Plays even when the phone is set to silent.
    case alwaysOn
    /// Never plays.
    case alwaysOff

    public var displayName: String {
        switch self {
        case .followSilentSwitch: "Follow Silent Switch"
        case .alwaysOn: "Always On"
        case .alwaysOff: "Always Off"
        }
    }
}

public enum AutoResumePolicy: String, Codable, Sendable, CaseIterable {
    case always
    case ask
    case never
}

/// Built-in display effects. Raw values are stored in settings.
public enum LCDFilter: String, Codable, Sendable, CaseIterable {
    case off
    case lcd1x
    case lcd3x

    public var displayName: String {
        switch self {
        case .off: "Off"
        case .lcd1x: "LCD 1×"
        case .lcd3x: "LCD 3×"
        }
    }
}

public enum ColorCorrection: String, Codable, Sendable, CaseIterable {
    case balanced = "balanced"
    case accurate = "accurate"
    case boostContrast = "boostContrast"
    case reduceContrast = "reduceContrast"
    case lowContrast = "lowContrast"
    case off = "off"

    public static let defaultValue: Self = .balanced
    public static let explanation = "Adjusts Game Boy Color colors for a modern screen. Original shows them as the game stores them."

    public var displayName: String {
        switch self {
        case .balanced: "Balanced"
        case .accurate: "Accurate"
        case .boostContrast: "Boost Contrast"
        case .reduceContrast: "Reduce Contrast"
        case .lowContrast: "Low Contrast"
        case .off: "Original"
        }
    }
}

public enum DMGPalette: String, Codable, Sendable, CaseIterable {
    case dmgGreen = "dmgGreen"
    case pocket = "pocket"
    case light = "light"
    case grey = "grey"
    case cgbUp = "cgbUp"
    case cgbUpA = "cgbUpA"
    case cgbUpB = "cgbUpB"
    case cgbDown = "cgbDown"
    case cgbDownA = "cgbDownA"
    case cgbDownB = "cgbDownB"
    case cgbLeft = "cgbLeft"
    case cgbLeftA = "cgbLeftA"
    case cgbLeftB = "cgbLeftB"
    case cgbRight = "cgbRight"
    case cgbRightA = "cgbRightA"
    case cgbRightB = "cgbRightB"
    case cgbOlive = "cgbOlive"
    case cgbZelda = "cgbZelda"
    case cgbMarioLand = "cgbMarioLand"
    case cgbMarioLand2 = "cgbMarioLand2"
    case cgbDonkeyKongLand = "cgbDonkeyKongLand"
    case cgbCamera = "cgbCamera"

    public static let defaultValue: Self = .dmgGreen
    public static let explanation = "Previews show background colors above the two sprite palettes. Button combos identify Game Boy Color boot palettes; no buttons need to be held."

    // The legacy grayscale value stays decodable for saved settings.
    public static var selectableCases: [Self] { allCases.filter { $0 != .grey } }
    public var selectionValue: Self { self == .grey ? .cgbLeftB : self }

    public var displayName: String {
        "\(colorName) (\(originDescription))"
    }

    public var colorName: String { label.name }
    public var originDescription: String { label.origin }

    private var label: (name: String, origin: String) {
        switch self {
        case .dmgGreen: ("Green", "DMG")
        case .pocket: ("Olive", "Pocket")
        case .light: ("Teal", "Light")
        case .grey, .cgbLeftB: ("Black & White", "Left + B")
        case .cgbUp: ("Brown", "Up")
        case .cgbUpA: ("Red", "Up + A")
        case .cgbUpB: ("Dark Brown", "Up + B")
        case .cgbDown: ("Pastel", "Down")
        case .cgbDownA: ("Orange", "Down + A")
        case .cgbDownB: ("Yellow", "Down + B")
        case .cgbLeft: ("Blue", "Left")
        case .cgbLeftA: ("Dark Blue", "Left + A")
        case .cgbRight: ("Green", "Right")
        case .cgbRightA: ("Dark Green", "Right + A")
        case .cgbRightB: ("Inverted", "Right + B")
        case .cgbOlive: ("Olive & Orange", "Mole Mania")
        case .cgbZelda: ("Red & Green", "Link's Awakening")
        case .cgbMarioLand: ("Tan & Red", "Super Mario Land")
        case .cgbMarioLand2: ("Pastel & Orange", "Super Mario Land 2")
        case .cgbDonkeyKongLand: ("Blue & Orange", "Donkey Kong Land")
        case .cgbCamera: ("Amber", "Game Boy Camera")
        }
    }

    /// RGB888 swatches in Game Boy shade order (0-3), with background, OBJ0 and OBJ1 rows.
    /// Boot colors are uncorrected.
    public var previewColors: [[UInt32]] {
        let brown: [UInt16] = [0x7fff, 0x32bf, 0x00d0, 0x0000]
        let red: [UInt16] = [0x7fff, 0x421f, 0x1cf2, 0x0000]
        let green: [UInt16] = [0x7fff, 0x1bef, 0x0200, 0x0000]
        let blue: [UInt16] = [0x7fff, 0x7e8c, 0x7c00, 0x0000]
        let colors: [[UInt16]]
        switch self {
        case .dmgGreen:
            return Array(repeating: [0xc6de8c, 0x84a563, 0x396139, 0x081810], count: 3)
        case .pocket:
            return Array(repeating: [0xc2ce93, 0x818d66, 0x3a4c3a, 0x07100e], count: 3)
        case .light:
            return Array(repeating: [0x7fe2c3, 0x56b495, 0x357862, 0x0a1c15], count: 3)
        case .grey:
            return Array(repeating: [0xffffff, 0xaaaaaa, 0x555555, 0x000000], count: 3)
        case .cgbUp: colors = [brown, brown, brown]
        case .cgbUpA: colors = [red, green, blue]
        case .cgbUpB: colors = [[0x639f, 0x4279, 0x15b0, 0x04cb], brown, brown]
        case .cgbDown: colors = Array(repeating: [0x53ff, 0x4a5f, 0x7e52, 0x0000], count: 3)
        case .cgbDownA: colors = Array(repeating: [0x7fff, 0x03ff, 0x001f, 0x0000], count: 3)
        case .cgbDownB: colors = [[0x7fff, 0x03ff, 0x012f, 0x0000], blue, green]
        case .cgbLeft: colors = [blue, red, green]
        case .cgbLeftA: colors = [[0x7fff, 0x6e31, 0x454a, 0x0000], red, brown]
        case .cgbLeftB: colors = Array(repeating: [0x7fff, 0x5294, 0x294a, 0x0000], count: 3)
        case .cgbRight: colors = Array(repeating: [0x7fff, 0x03ea, 0x011f, 0x0000], count: 3)
        case .cgbRightA: colors = [[0x7fff, 0x1bef, 0x6180, 0x0000], red, red]
        case .cgbRightB: colors = Array(repeating: [0x0000, 0x4200, 0x037f, 0x7fff], count: 3)
        case .cgbOlive:
            colors = [[0x7fff, 0x42b5, 0x3dc8, 0x0000],
                      [0x7fff, 0x01df, 0x0112, 0x0000],
                      [0x7fff, 0x01df, 0x0112, 0x0000]]
        case .cgbZelda:
            colors = [red, [0x7fff, 0x03e0, 0x0206, 0x0120], blue]
        case .cgbMarioLand:
            colors = [[0x7ed6, 0x4bff, 0x2175, 0x0000],
                      [0x0000, 0x7fff, 0x421f, 0x1cf2],
                      [0x0000, 0x7fff, 0x421f, 0x1cf2]]
        case .cgbMarioLand2:
            colors = [[0x67ff, 0x77ac, 0x1a13, 0x2d6b], [0x7fff, 0x01df, 0x0112, 0x0000], blue]
        case .cgbDonkeyKongLand:
            colors = [[0x7fff, 0x6e31, 0x454a, 0x0000],
                      [0x231f, 0x035f, 0x00f2, 0x0009],
                      [0x7fff, 0x7eeb, 0x001f, 0x7c00]]
        case .cgbCamera:
            colors = Array(repeating: [0x7fff, 0x033f, 0x0193, 0x0000], count: 3)
        }
        return colors.map { $0.map { color in
            func channel(_ shift: UInt16) -> UInt32 {
                let value = UInt32((color >> shift) & 31)
                return (value << 3) | (value >> 2)
            }
            return channel(0) << 16 | channel(5) << 8 | channel(10)
        } }
    }
}

/// How fast the game menu's Fast Forward runs the game. Raw values are stored in settings.
public enum FastForwardSpeed: String, Codable, Sendable, CaseIterable {
    case x1_5
    case x2
    case x3
    case x4
    case x8
    case unlimited

    public var displayName: String {
        switch self {
        case .x1_5: "1.5×"
        case .x2: "2×"
        case .x3: "3×"
        case .x4: "4×"
        case .x8: "8×"
        case .unlimited: "Unlimited"
        }
    }

    /// The speed as a multiple of normal, or nil for as fast as the device can run.
    public var multiplier: Double? {
        switch self {
        case .x1_5: 1.5
        case .x2: 2
        case .x3: 3
        case .x4: 4
        case .x8: 8
        case .unlimited: nil
        }
    }
}

/// What game sound does while Fast Forward runs. Raw values are stored in settings.
public enum FastForwardAudio: String, Codable, Sendable, CaseIterable {
    case muted
    /// Plays sped up with the game, its pitch rising with it. Only up to 4×; faster speeds and
    /// Unlimited stay muted.
    case accelerated

    public var displayName: String {
        switch self {
        case .muted: "Muted"
        case .accelerated: "Accelerated"
        }
    }
}

/// How each shown picture mixes in the frames before it. Raw values are stored in settings.
public enum FrameBlending: String, Codable, Sendable, CaseIterable {
    case off
    /// Each frame averaged with the one before. Games that draw a sprite on alternate frames to
    /// make it look see-through rely on the screen doing this.
    case blend
    /// A fading trail of the two frames before, like a slow LCD.
    case ghosting

    public var displayName: String {
        switch self {
        case .off: "Off"
        case .blend: "Blend"
        case .ghosting: "LCD Ghosting"
        }
    }

    /// The weights of the newest frame and the two before it, summing to 1. With fewer earlier
    /// frames held, as just after a game starts, the missing frames' share goes to the rest.
    public func weights(heldFrames: Int) -> [Double] {
        let full: [Double] = switch self {
        case .off: [1, 0, 0]
        case .blend: [0.5, 0.5, 0]
        case .ghosting: [0.5, 0.3, 0.2]
        }
        let available = min(max(heldFrames, 1), full.count)
        let total = full.prefix(available).reduce(0, +)
        return full.indices.map { $0 < available ? full[$0] / total : 0 }
    }
}


public enum SaveStateSlots: Int, Codable, Sendable, CaseIterable {
    case off = 0
    case three = 3
    case five = 5
    case ten = 10

    public var displayName: String { self == .off ? "Off" : String(rawValue) }
}

public enum KeepSaveStates: Int, Codable, Sendable, CaseIterable {
    case all = 0
    case ten = 10
    case twentyFive = 25
    case fifty = 50

    public var displayName: String { self == .all ? "All" : String(rawValue) }
    public var keepCount: Int? { self == .all ? nil : rawValue }
}

public enum KeepAutoStates: Int, Codable, Sendable, CaseIterable {
    case three = 3
    case five = 5
    case ten = 10

    public var displayName: String { String(rawValue) }
}

public enum TimedStates: Int, Codable, Sendable, CaseIterable {
    case off = 0
    case oneMinute = 1
    case twoMinutes = 2
    case fiveMinutes = 5
    case tenMinutes = 10

    public var displayName: String {
        switch self {
        case .off: "Off"
        case .oneMinute: "Every 1 Minute"
        default: "Every \(rawValue) Minutes"
        }
    }
}

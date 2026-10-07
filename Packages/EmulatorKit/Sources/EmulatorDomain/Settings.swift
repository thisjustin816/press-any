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
    /// `DMGPalette`, unset means `.grey`.
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
}

/// How strongly the on-screen controls tap back when pressed. Raw values are stored in settings.
public enum TouchHaptics: String, Codable, Sendable, CaseIterable {
    case off
    case light
    case medium
}

/// Whether game sound plays. Raw values are stored in settings.
public enum SoundMode: String, Codable, Sendable, CaseIterable {
    /// Silent when the ring/silent switch is set to silent.
    case followSilentSwitch
    /// Plays even when the phone is set to silent.
    case alwaysOn
    /// Never plays, and leaves other apps' audio playing.
    case alwaysOff
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
    case off = "off"
    case accurate = "accurate"
    case balanced = "balanced"
    case boostContrast = "boostContrast"
    case reduceContrast = "reduceContrast"
    case lowContrast = "lowContrast"

    public static let defaultValue: Self = .balanced
    public static let explanation = "Adjusts colors in Game Boy Color games."

    public var displayName: String {
        switch self {
        case .off: "Off"
        case .accurate: "Accurate"
        case .balanced: "Balanced"
        case .boostContrast: "Boost Contrast"
        case .reduceContrast: "Reduce Contrast"
        case .lowContrast: "Low Contrast"
        }
    }
}

public enum DMGPalette: String, Codable, Sendable, CaseIterable {
    case grey = "grey"
    case dmgGreen = "dmgGreen"
    case pocket = "pocket"
    case light = "light"

    public static let defaultValue: Self = .grey
    public static let explanation = "Changes the four shades in original Game Boy games."

    public var displayName: String {
        switch self {
        case .grey: "Grey"
        case .dmgGreen: "DMG Green"
        case .pocket: "Pocket"
        case .light: "Light"
        }
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

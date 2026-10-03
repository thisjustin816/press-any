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
    /// always skips it (docs/decisions.md).
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
    /// `SoundMode`, unset means `.followSilentSwitch`.
    case soundMode
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

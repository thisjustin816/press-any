/// Why gameplay frames aren't running. Frames run only while none applies, so each reason can
/// begin and end on its own without undoing another: coming back to the app doesn't resume a
/// game the player paused, and resuming doesn't start frames in the middle of loading a state.
struct GameplayPauseReasons: Equatable {
    /// Paused from the menu, or by losing the controller. Only Resume ends it.
    var byPlayer = false
    /// The scene isn't active: Control Center, Notification Center, a call, or the app in the
    /// background.
    var inactive = false
    /// Back from the background with Resume Games set to Ask or Never, until the player resumes.
    var awaitingResume = false
    /// Work that needs the game still, such as checking and loading a state, holds frames until
    /// it finishes. A count, so overlapping work releases only its own hold.
    var holds = 0

    var shouldRun: Bool { !byPlayer && !inactive && !awaitingResume && holds == 0 }

    /// The paused overlay shows when it's the player's move to resume.
    var showsPausedOverlay: Bool { byPlayer || awaitingResume }
}

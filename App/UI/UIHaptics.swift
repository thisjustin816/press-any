import EmulatorDomain
import SwiftUI

/// The taps the library and settings screens give back, as opposed to the game's own. They follow
/// Touch Haptics, so Off silences them along with the on-screen controls, and iOS's own haptics
/// switch applies on top. A tap marks a selection changing or a failure; anything the screen
/// already shows plainly, such as a sheet closing on a finished import, gets none.
struct UIHaptics: Sendable {
    /// Nil where no container is set, as in a preview, which taps at the default strength.
    let container: AppContainer?

    /// The feedback to play, or nil when Touch Haptics is off. The setting is read when the tap
    /// fires, so a change in Settings applies at once.
    @MainActor
    func feedback(_ feedback: SensoryFeedback) -> SensoryFeedback? {
        container?.touchHaptics() == .off ? nil : feedback
    }
}

private struct UIHapticsKey: EnvironmentKey {
    static let defaultValue = UIHaptics(container: nil)
}

extension EnvironmentValues {
    var uiHaptics: UIHaptics {
        get { self[UIHapticsKey.self] }
        set { self[UIHapticsKey.self] = newValue }
    }
}

private struct UIHapticModifier<Trigger: Equatable>: ViewModifier {
    @Environment(\.uiHaptics) private var haptics
    let feedback: SensoryFeedback
    let trigger: Trigger
    let when: (Trigger, Trigger) -> Bool

    func body(content: Content) -> some View {
        content.sensoryFeedback(trigger: trigger) { old, new in
            when(old, new) ? haptics.feedback(feedback) : nil
        }
    }
}

extension View {
    /// Plays `feedback` when `trigger` changes and `when` accepts the change, unless Touch Haptics
    /// is off. The first value never plays.
    func uiHaptic<Trigger: Equatable>(
        _ feedback: SensoryFeedback,
        trigger: Trigger,
        when: @escaping (Trigger, Trigger) -> Bool = { _, _ in true }
    ) -> some View {
        modifier(UIHapticModifier(feedback: feedback, trigger: trigger, when: when))
    }

    /// The error tap, played as an alert that reports a failure appears. Pass the alert's own
    /// condition so the tap and the alert agree.
    func errorHaptic(isShowing: Bool) -> some View {
        uiHaptic(.error, trigger: isShowing) { _, showing in showing }
    }
}

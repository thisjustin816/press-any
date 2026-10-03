import CoreHaptics
import GameController
import UIKit

@MainActor
final class RumbleRouter {
    private let phoneFeedback = UIImpactFeedbackGenerator(style: .medium)
    private weak var controller: GCController?
    private var controllerEngine: CHHapticEngine?
    private var lastPhonePulse = Date.distantPast

    init() {
        phoneFeedback.prepare()
    }

    func setController(_ controller: GCController?) {
        self.controller = controller
        controllerEngine?.stop(completionHandler: nil)
        controllerEngine = nil
        guard let haptics = controller?.haptics else { return }
        controllerEngine = haptics.createEngine(withLocality: .default)
        try? controllerEngine?.start()
    }

    /// Product default: controller rumble when available, phone haptics as fallback.
    func route(amplitude: Double) {
        let clamped = Float(max(0, min(1, amplitude)))
        guard clamped > 0.01 else { return }

        if let engine = controllerEngine {
            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: clamped)],
                relativeTime: 0
            )
            if let pattern = try? CHHapticPattern(events: [event], parameters: []),
               let player = try? engine.makePlayer(with: pattern) {
                try? player.start(atTime: 0)
                return
            }
        }

        // Avoid hammering UIKit's transient generator at the emulation frame rate.
        let now = Date()
        guard now.timeIntervalSince(lastPhonePulse) > 0.045 else { return }
        lastPhonePulse = now
        phoneFeedback.impactOccurred(intensity: CGFloat(clamped))
        phoneFeedback.prepare()
    }
}

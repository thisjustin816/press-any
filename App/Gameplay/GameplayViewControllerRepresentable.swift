import EmulatorDomain
import SwiftUI

struct GameplayViewControllerRepresentable: UIViewControllerRepresentable {
    let runtime: any GameplayRuntime
    let autoResumePolicy: AutoResumePolicy
    let launchMessage: String?
    let firstFrameClock: UInt64?
    let onClose: () -> Void

    func makeUIViewController(context: Context) -> GameplayViewController {
        let controller = GameplayViewController(
            runtime: runtime,
            autoResumePolicy: autoResumePolicy,
            launchMessage: launchMessage,
            firstFrameClock: firstFrameClock
        )
        controller.onClose = onClose
        return controller
    }

    func updateUIViewController(_ uiViewController: GameplayViewController, context: Context) {}
}

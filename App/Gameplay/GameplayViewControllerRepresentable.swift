import EmulatorDomain
import SwiftUI

struct GameplayViewControllerRepresentable: UIViewControllerRepresentable {
    let runtime: any GameplayRuntime
    let autoResumePolicy: AutoResumePolicy
    let launchMessage: String?
    let onClose: () -> Void

    func makeUIViewController(context: Context) -> GameplayViewController {
        let controller = GameplayViewController(
            runtime: runtime,
            autoResumePolicy: autoResumePolicy,
            launchMessage: launchMessage
        )
        controller.onClose = onClose
        return controller
    }

    func updateUIViewController(_ uiViewController: GameplayViewController, context: Context) {}
}

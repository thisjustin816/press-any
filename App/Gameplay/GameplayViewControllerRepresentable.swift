import SwiftUI

struct GameplayViewControllerRepresentable: UIViewControllerRepresentable {
    let runtime: any GameplayRuntime
    let onClose: () -> Void

    func makeUIViewController(context: Context) -> GameplayViewController {
        let controller = GameplayViewController(runtime: runtime)
        controller.onClose = onClose
        return controller
    }

    func updateUIViewController(_ uiViewController: GameplayViewController, context: Context) {}
}

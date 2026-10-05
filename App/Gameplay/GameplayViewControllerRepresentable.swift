import EmulatorDomain
import GameplayInput
import SwiftUI

struct GameplayViewControllerRepresentable: UIViewControllerRepresentable {
    let runtime: any GameplayRuntime
    let autoResumePolicy: AutoResumePolicy
    let launchMessage: String?
    let firstFrameClock: UInt64?
    let controlStyle: TouchControlStyle
    let screenScaling: ScreenScaling
    let controllerTheme: ControllerTheme
    let tapGameForMenu: Bool
    let soundMode: SoundMode
    let hidesTouchControlsWithController: Bool
    let touchHaptics: TouchHaptics
    let onClose: () -> Void
    var onAddToLibrary: (() -> Void)?

    func makeUIViewController(context: Context) -> GameplayViewController {
        let controller = GameplayViewController(
            runtime: runtime,
            autoResumePolicy: autoResumePolicy,
            launchMessage: launchMessage,
            firstFrameClock: firstFrameClock,
            controlStyle: controlStyle,
            screenScaling: screenScaling,
            controllerTheme: controllerTheme,
            tapGameForMenu: tapGameForMenu,
            soundMode: soundMode,
            hidesTouchControlsWithController: hidesTouchControlsWithController,
            touchHaptics: touchHaptics
        )
        controller.onClose = onClose
        controller.onAddToLibrary = onAddToLibrary
        return controller
    }

    func updateUIViewController(_ uiViewController: GameplayViewController, context: Context) {}
}

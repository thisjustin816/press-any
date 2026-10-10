import EmulatorDomain
import GameplayInput
import SwiftUI

struct GameplayViewControllerRepresentable: UIViewControllerRepresentable {
    let runtime: any GameplayRuntime
    let autoResumePolicy: AutoResumePolicy
    var saveStateSlots: SaveStateSlots = .off
    var nameNewStates: Bool = false
    let launchMessage: String?
    let firstFrameClock: UInt64?
    let display: GameplayDisplaySettings
    let controllerTheme: ControllerTheme
    let tapGameForMenu: Bool
    let soundMode: SoundMode
    let hidesTouchControlsWithController: Bool
    let touchHaptics: TouchHaptics
    let controllerMonitor: PhysicalControllerMonitor
    /// A sheet is open over the game, which pauses it.
    var isCoveredBySheet = false
    /// Set once to close the game the normal way, saving first.
    var closeRequested = false
    let onClose: () -> Void
    var onAddToLibrary: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenCheats: (() -> Void)?
    var onSoundModeChange: ((SoundMode) throws -> Void)?
    var artworkTarget: GameplayArtworkTarget?

    func makeUIViewController(context: Context) -> GameplayViewController {
        let controller = GameplayViewController(
            runtime: runtime,
            autoResumePolicy: autoResumePolicy,
            saveStateSlots: saveStateSlots,
            nameNewStates: nameNewStates,
            launchMessage: launchMessage,
            firstFrameClock: firstFrameClock,
            controlStyle: display.controlStyle,
            orientation: display.orientation,
            screenScaling: display.screenScaling,
            lcdFilter: display.lcdFilter,
            colorCorrection: display.colorCorrection,
            dmgPalette: display.dmgPalette,
            frameBlending: display.frameBlending,
            fastForwardSpeed: display.fastForwardSpeed,
            fastForwardAudio: display.fastForwardAudio,
            controllerTheme: controllerTheme,
            tapGameForMenu: tapGameForMenu,
            soundMode: soundMode,
            hidesTouchControlsWithController: hidesTouchControlsWithController,
            touchHaptics: touchHaptics,
            controllerMonitor: controllerMonitor
        )
        controller.onClose = onClose
        controller.onAddToLibrary = onAddToLibrary
        controller.onOpenSettings = onOpenSettings
        controller.onOpenCheats = onOpenCheats
        controller.onSoundModeChange = onSoundModeChange
        controller.artworkTarget = artworkTarget
        return controller
    }

    func updateUIViewController(_ uiViewController: GameplayViewController, context: Context) {
        uiViewController.saveStateSlots = saveStateSlots
        uiViewController.nameNewStates = nameNewStates
        uiViewController.setCoveredBySheet(isCoveredBySheet)
        uiViewController.applyDisplaySettings(
            controlStyle: display.controlStyle,
            orientation: display.orientation,
            screenScaling: display.screenScaling,
            lcdFilter: display.lcdFilter,
            colorCorrection: display.colorCorrection,
            dmgPalette: display.dmgPalette,
            frameBlending: display.frameBlending,
            fastForwardSpeed: display.fastForwardSpeed,
            fastForwardAudio: display.fastForwardAudio
        )
        // Updates repeat, and a close that fails to save waits on the player, so ask only once.
        if closeRequested, !context.coordinator.closeSent {
            context.coordinator.closeSent = true
            uiViewController.requestClose()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var closeSent = false
    }
}

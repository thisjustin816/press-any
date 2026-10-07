import Combine
import EmulationCore
import GameController
import GameplayInput
import UIKit

@MainActor
final class PhysicalControllerMonitor: ObservableObject {
    var onInputChanged: ((EmulatorInputState) -> Void)?
    var onConnectionChanged: ((Bool) -> Void)?
    var onUnexpectedDisconnect: (() -> Void)?

    @Published private(set) var activeController: GCController?
    private let connectedControllers: () -> [GCController]

    /// Whether a controller drives the game, so the touch controls hide.
    var isConnected: Bool { activeController != nil || ScreenshotScene.simulatesGamepad }
    // Written only during init and read only in deinit, which runs once nothing else can reach
    // the monitor, so the nonisolated deinit can remove the observers without a hop.
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    init(connectedControllers: @escaping () -> [GCController] = { GCController.controllers() }) {
        self.connectedControllers = connectedControllers
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] note in
            // queue: .main delivers on the main thread, so the controller never crosses threads.
            nonisolated(unsafe) let controller = note.object as? GCController
            MainActor.assumeIsolated {
                guard let controller else { return }
                self?.activate(controller)
            }
        })
        observers.append(center.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] note in
            nonisolated(unsafe) let controller = note.object as? GCController
            MainActor.assumeIsolated {
                guard let self, let controller else { return }
                self.handleDisconnect(controller)
            }
        })

        if let controller = connectedControllers().first {
            activate(controller)
        }
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    func selectPlayerOne(_ controller: GCController) {
        activate(controller)
    }

    private func activate(_ controller: GCController) {
        // Screenshot runs decide for themselves whether a controller is connected.
        if ScreenshotScene.current != nil {
            ScreenshotScene.log("Ignoring controller: \(controller.vendorName ?? "unnamed")")
            return
        }
        activeController = controller
        installHandlers(on: controller)
        onConnectionChanged?(true)
        publish(from: controller)
    }

    private func handleDisconnect(_ controller: GCController) {
        guard activeController === controller else { return }
        activeController = nil
        onInputChanged?(.init())
        onConnectionChanged?(false)
        onUnexpectedDisconnect?()

        if let replacement = connectedControllers().first(where: { $0 !== controller }) {
            activate(replacement)
        }
    }

    private func installHandlers(on controller: GCController) {
        guard let pad = controller.extendedGamepad else { return }
        pad.valueChangedHandler = { [weak self, weak controller] _, _ in
            guard let self, let controller else { return }
            Task { @MainActor in self.publish(from: controller) }
        }
    }

    private func publish(from controller: GCController) {
        guard activeController === controller, let pad = controller.extendedGamepad else { return }
        onInputChanged?(GamepadInputMapping.input(
            dpad: .init(
                up: pad.dpad.up.isPressed, down: pad.dpad.down.isPressed,
                left: pad.dpad.left.isPressed, right: pad.dpad.right.isPressed
            ),
            leftStickX: pad.leftThumbstick.xAxis.value,
            leftStickY: pad.leftThumbstick.yAxis.value,
            buttonA: pad.buttonA.isPressed,
            buttonB: pad.buttonB.isPressed,
            menu: pad.buttonMenu.isPressed,
            options: pad.buttonOptions?.isPressed == true,
            leftShoulder: pad.leftShoulder.isPressed
        ))
    }
}

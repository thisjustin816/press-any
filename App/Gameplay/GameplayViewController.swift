import EmulationCore
import EmulatorDomain
import MetalKit
import UIKit

@MainActor
final class GameplayViewController: UIViewController {
    private let runtime: any GameplayRuntime
    private let input = GameplayInputAccumulator()
    private lazy var driver = GameplayDriver(runtime: runtime, input: input)
    private let metalView = MTKView(frame: .zero)
    private let touchControls = TouchControllerView(frame: .zero)
    private let audio = AudioOutputEngine()
    private let controllerMonitor = PhysicalControllerMonitor()
    private let rumble = RumbleRouter()
    private var renderer: MetalRenderer?
    // Appended only on the main actor and read only in deinit, which runs once nothing else can
    // reach the controller, so the nonisolated deinit can remove the observers without a hop.
    nonisolated(unsafe) private var lifecycleObservers: [NSObjectProtocol] = []
    private var stopped = false

    var onClose: (() -> Void)?

    init(runtime: any GameplayRuntime) {
        self.runtime = runtime
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        installViews()
        configureRuntimeLoop()
        configureInput()
        observeLifecycle()

        renderer = MetalRenderer(view: metalView)
        do {
            try audio.start()
            driver.start()
        } catch {
            presentRuntimeError(error)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || navigationController?.isBeingDismissed == true {
            stopRuntime()
        }
    }

    deinit {
        for observer in lifecycleObservers { NotificationCenter.default.removeObserver(observer) }
    }

    private func installViews() {
        metalView.translatesAutoresizingMaskIntoConstraints = false
        touchControls.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(metalView)
        view.addSubview(touchControls)
        NSLayoutConstraint.activate([
            metalView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            metalView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            metalView.topAnchor.constraint(equalTo: view.topAnchor),
            metalView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            touchControls.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            touchControls.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            touchControls.topAnchor.constraint(equalTo: view.topAnchor),
            touchControls.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let close = UIButton(type: .system)
        close.translatesAutoresizingMaskIntoConstraints = false
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: "xmark")
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = UIColor.black.withAlphaComponent(0.45)
        configuration.cornerStyle = .capsule
        close.configuration = configuration
        close.accessibilityLabel = "Close Game"
        close.addAction(UIAction { [weak self] _ in self?.closeTapped() }, for: .touchUpInside)
        view.addSubview(close)
        NSLayoutConstraint.activate([
            close.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 14),
            close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            close.widthAnchor.constraint(equalToConstant: 42),
            close.heightAnchor.constraint(equalToConstant: 42),
        ])
    }

    private func configureRuntimeLoop() {
        driver.onFrame = { [weak self] frame in
            DispatchQueue.main.async {
                guard let self, let renderer = self.renderer else { return }
                renderer.submit(frame, to: self.metalView)
            }
        }
        driver.onAudio = { [weak self] samples in
            self?.audio.enqueue(samples)
        }
        driver.onRumble = { [weak self] amplitude in
            DispatchQueue.main.async { self?.rumble.route(amplitude: amplitude) }
        }
        driver.onError = { [weak self] error in
            DispatchQueue.main.async { self?.presentRuntimeError(error) }
        }
    }

    private func configureInput() {
        touchControls.onInputChanged = { [weak self] input in self?.input.setTouch(input) }
        controllerMonitor.onInputChanged = { [weak self] controllerInput in self?.input.setController(controllerInput) }
        controllerMonitor.onConnectionChanged = { [weak self] connected in
            guard let self else { return }
            self.touchControls.isHidden = connected
            self.touchControls.hapticsEnabled = !connected
            self.rumble.setController(self.controllerMonitor.activeController)
        }
        controllerMonitor.onUnexpectedDisconnect = { [weak self] in
            guard let self else { return }
            self.driver.stop()
            try? self.runtime.pause()
            self.audio.pause()
            self.touchControls.isHidden = false
            self.touchControls.hapticsEnabled = true
            self.input.resetController()
            self.showTransientMessage("Controller disconnected. Game paused.")
        }

        let connected = controllerMonitor.activeController != nil
        touchControls.isHidden = connected
        touchControls.hapticsEnabled = !connected
        rumble.setController(controllerMonitor.activeController)
    }

    private func observeLifecycle() {
        let center = NotificationCenter.default
        lifecycleObservers.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.backgrounded() }
        })
        lifecycleObservers.append(center.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.foregrounded() }
        })
    }

    private func backgrounded() {
        driver.stop()
        audio.pause()
        touchControls.cancelInput()
        input.resetTouch()
        do { try runtime.background() }
        catch { presentRuntimeError(error) }
    }

    private func foregrounded() {
        do {
            let resumed = try runtime.foreground(policy: .always)
            if resumed {
                try audio.resume()
                driver.start()
            }
        } catch {
            presentRuntimeError(error)
        }
    }

    private func closeTapped() {
        stopRuntime()
        dismiss(animated: true)
        onClose?()
    }

    private func stopRuntime() {
        guard !stopped else { return }
        stopped = true
        driver.stop()
        audio.stop()
        do { try runtime.stop(createAutoState: true) }
        catch { /* Closing must remain possible even if persistence fails. */ }
    }

    private func presentRuntimeError(_ error: Error) {
        guard presentedViewController == nil else { return }
        driver.stop()
        audio.pause()
        let alert = UIAlertController(
            title: "Emulation Error",
            message: String(describing: error),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Close", style: .default) { [weak self] _ in
            self?.closeTapped()
        })
        present(alert, animated: true)
    }

    private func showTransientMessage(_ text: String) {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.layer.cornerRadius = 10
        label.layer.masksToBounds = true
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            label.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.82),
            label.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
        ])
        UIView.animate(withDuration: 0.25, delay: 2.0, options: []) {
            label.alpha = 0
        } completion: { _ in
            label.removeFromSuperview()
        }
    }
}

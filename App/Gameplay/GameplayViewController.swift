import EmulationCore
import EmulatorDomain
import MetalKit
import OSLog
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
    private let autoResumePolicy: AutoResumePolicy
    private let launchMessage: String?
    private let pausedOverlay = UIButton(type: .system)
    /// Uptime when Quick Play's file was chosen, cleared once the first frame is reported.
    private var firstFrameClock: UInt64?
    private var userPaused = false
    private var fastForward = false
    // Appended only on the main actor and read only in deinit, which runs once nothing else can
    // reach the controller, so the nonisolated deinit can remove the observers without a hop.
    nonisolated(unsafe) private var lifecycleObservers: [NSObjectProtocol] = []
    private var stopped = false

    var onClose: (() -> Void)?

    init(
        runtime: any GameplayRuntime,
        autoResumePolicy: AutoResumePolicy,
        launchMessage: String? = nil,
        firstFrameClock: UInt64? = nil
    ) {
        self.runtime = runtime
        self.firstFrameClock = firstFrameClock
        self.autoResumePolicy = autoResumePolicy
        self.launchMessage = launchMessage
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
        if let launchMessage { showTransientMessage(launchMessage) }
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

        let menu = UIButton(type: .system)
        menu.translatesAutoresizingMaskIntoConstraints = false
        var menuConfiguration = configuration
        menuConfiguration.image = UIImage(systemName: "ellipsis")
        menu.configuration = menuConfiguration
        menu.accessibilityLabel = "Game Menu"
        menu.showsMenuAsPrimaryAction = true
        menu.menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                MainActor.assumeIsolated { completion(self?.menuElements() ?? []) }
            },
        ])
        view.addSubview(menu)

        var resumeConfiguration = UIButton.Configuration.filled()
        resumeConfiguration.title = "Resume"
        resumeConfiguration.image = UIImage(systemName: "play.fill")
        resumeConfiguration.imagePadding = 8
        resumeConfiguration.cornerStyle = .capsule
        resumeConfiguration.buttonSize = .large
        pausedOverlay.configuration = resumeConfiguration
        pausedOverlay.translatesAutoresizingMaskIntoConstraints = false
        pausedOverlay.isHidden = true
        pausedOverlay.addAction(UIAction { [weak self] _ in self?.resumeTapped() }, for: .touchUpInside)
        view.addSubview(pausedOverlay)

        NSLayoutConstraint.activate([
            close.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 14),
            close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            close.widthAnchor.constraint(equalToConstant: 42),
            close.heightAnchor.constraint(equalToConstant: 42),
            menu.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
            menu.topAnchor.constraint(equalTo: close.topAnchor),
            menu.widthAnchor.constraint(equalToConstant: 42),
            menu.heightAnchor.constraint(equalToConstant: 42),
            pausedOverlay.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pausedOverlay.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
        ])
    }

    private func menuElements() -> [UIMenuElement] {
        var elements: [UIMenuElement] = []
        if pausedOverlay.isHidden {
            elements.append(UIAction(title: "Pause", image: UIImage(systemName: "pause.fill")) { [weak self] _ in
                self?.userPaused = true
                self?.pauseGameplay()
            })
        } else {
            elements.append(UIAction(title: "Resume", image: UIImage(systemName: "play.fill")) { [weak self] _ in
                self?.resumeTapped()
            })
        }
        elements.append(UIAction(
            title: "Fast Forward",
            image: UIImage(systemName: "forward.fill"),
            state: fastForward ? .on : .off
        ) { [weak self] _ in
            guard let self else { return }
            self.fastForward.toggle()
            self.driver.setSpeed(self.fastForward ? .multiplier(2) : .normal)
        })

        if let states = runtime as? any SaveStateRuntime {
            elements.append(UIAction(title: "Save State", image: UIImage(systemName: "square.and.arrow.down")) { [weak self] _ in
                self?.saveState()
            })
            let saved = (try? states.saveStates()) ?? []
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .medium
            let loadActions = saved.map { state in
                UIAction(
                    title: state.label ?? (state.kind == .auto ? "Auto State" : "State"),
                    subtitle: formatter.string(from: state.createdAt)
                ) { [weak self] _ in
                    self?.loadState(state)
                }
            }
            let loadImage = UIImage(systemName: "square.and.arrow.up")
            if loadActions.isEmpty {
                elements.append(UIAction(title: "Load State", image: loadImage, attributes: .disabled) { _ in })
            } else {
                elements.append(UIMenu(title: "Load State", image: loadImage, children: loadActions))
            }
        }
        return elements
    }

    private func saveState() {
        guard let states = runtime as? any SaveStateRuntime else { return }
        do {
            _ = try states.saveManualState(label: nil)
            showTransientMessage("State saved.")
        } catch {
            showTransientMessage("Couldn’t save the state: \(error)")
        }
    }

    private func loadState(_ state: SaveState) {
        guard let states = runtime as? any SaveStateRuntime else { return }
        do {
            try states.loadState(state)
            showTransientMessage("State loaded.")
        } catch {
            showTransientMessage("Couldn’t load that state: \(error)")
        }
    }

    private func configureRuntimeLoop() {
        driver.onFrame = { [weak self] frame in
            DispatchQueue.main.async {
                guard let self, let renderer = self.renderer else { return }
                renderer.submit(frame, to: self.metalView)
                self.reportFirstFrame()
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

    /// Quick Play's primary metric (docs/decisions.md): time from choosing the file to the first
    /// frame handed to Metal. The device checklist records this figure.
    private func reportFirstFrame() {
        guard let start = firstFrameClock else { return }
        firstFrameClock = nil
        let milliseconds = (DispatchTime.now().uptimeNanoseconds &- start) / 1_000_000
        Logger(subsystem: "Gameplay", category: "QuickPlay").notice("First frame after \(milliseconds) ms")
        showTransientMessage("First frame in \(milliseconds) ms")
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
            self.userPaused = true
            self.pauseGameplay()
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
        guard !stopped else { return }
        if userPaused {
            pausedOverlay.isHidden = false
            return
        }
        do {
            if try runtime.foreground(policy: autoResumePolicy) {
                try audio.resume()
                driver.start()
                pausedOverlay.isHidden = true
                return
            }
        } catch {
            presentRuntimeError(error)
            return
        }
        pausedOverlay.isHidden = false
        if autoResumePolicy == .ask, presentedViewController == nil {
            let alert = UIAlertController(title: "Resume Game?", message: nil, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Not Now", style: .cancel))
            alert.addAction(UIAlertAction(title: "Resume", style: .default) { [weak self] _ in
                self?.resumeTapped()
            })
            present(alert, animated: true)
        }
    }

    private func pauseGameplay() {
        driver.stop()
        audio.pause()
        touchControls.cancelInput()
        input.resetTouch()
        try? runtime.pause()
        pausedOverlay.isHidden = false
    }

    private func resumeTapped() {
        do {
            try runtime.resume()
            try audio.resume()
            userPaused = false
            pausedOverlay.isHidden = true
            driver.start()
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

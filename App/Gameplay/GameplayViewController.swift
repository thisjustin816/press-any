import EmulationCore
import EmulatorDomain
import GameplayInput
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
    private let controllerMonitor: PhysicalControllerMonitor
    private let rumble = RumbleRouter()
    private var renderer: MetalRenderer?
    private let autoResumePolicy: AutoResumePolicy
    private let launchMessage: String?
    private let pausedOverlay = UIButton(type: .system)
    /// Uptime when Quick Play's file was chosen, cleared once the first frame is reported.
    private var firstFrameClock: UInt64?
    private var userPaused = false
    private let controlStyle: TouchControlStyle
    private let screenScaling: ScreenScaling
    private let controllerTheme: ControllerTheme
    private let tapGameForMenu: Bool
    private let soundMode: SoundMode
    private let hidesTouchControlsWithController: Bool
    private let touchHaptics: TouchHaptics
    /// Set by a touch while a controller hides the touch controls, and cleared by the controller's
    /// next button press.
    private var touchControlsRevealed = false
    /// Clear buttons over the layout's menu areas, the logo and, with Tap Game for Menu, the
    /// picture. They open the game menu with or without a controller connected.
    private var menuButtons: [GameMenuButton] = []
    private var fastForward = false
    // Appended only on the main actor and read only in deinit, which runs once nothing else can
    // reach the controller, so the nonisolated deinit can remove the observers without a hop.
    nonisolated(unsafe) private var lifecycleObservers: [NSObjectProtocol] = []
    private var stopped = false

    var onClose: (() -> Void)?
    /// Set for Quick Play: the menu then offers Add to Library, which closes the game and calls this.
    var onAddToLibrary: (() -> Void)?

    init(
        runtime: any GameplayRuntime,
        autoResumePolicy: AutoResumePolicy,
        launchMessage: String? = nil,
        firstFrameClock: UInt64? = nil,
        controlStyle: TouchControlStyle = .gameBoy,
        screenScaling: ScreenScaling = .integer,
        controllerTheme: ControllerTheme = .matchSystem,
        tapGameForMenu: Bool = false,
        soundMode: SoundMode = .followSilentSwitch,
        hidesTouchControlsWithController: Bool = true,
        touchHaptics: TouchHaptics = .light,
        controllerMonitor: PhysicalControllerMonitor = PhysicalControllerMonitor()
    ) {
        self.runtime = runtime
        self.controllerMonitor = controllerMonitor
        self.controlStyle = controlStyle
        self.screenScaling = screenScaling
        self.controllerTheme = controllerTheme
        self.tapGameForMenu = tapGameForMenu
        self.soundMode = soundMode
        self.hidesTouchControlsWithController = hidesTouchControlsWithController
        self.touchHaptics = touchHaptics
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
        renderer?.scaling = screenScaling
        applyLayout(touchControls.layout)
        // Audio can be unavailable, during a call for example. The game still runs, silently,
        // and resuming tries the audio again. An alert can't be shown yet: the view isn't on screen.
        var message = launchMessage
        audio.apply(soundMode)
        do {
            try audio.start()
        } catch {
            message = [launchMessage, "Sound is unavailable right now."].compactMap { $0 }.joined(separator: " ")
        }
        // The menu has no visible button, so the first game played says where it is.
        if !UserDefaults.standard.bool(forKey: Self.menuHintShownKey) {
            UserDefaults.standard.set(true, forKey: Self.menuHintShownKey)
            message = [message, "Tap \(AppBrand.displayName) for the menu."].compactMap { $0 }.joined(separator: " ")
        }
        driver.start()
        if let message { showTransientMessage(message) }
    }

    private static let menuHintShownKey = "gameplay.menuHintShown"

    /// Whether the touch controls are showing, for tests.
    var showsTouchControls: Bool { touchControls.showsControls }
    /// Whether gameplay is paused behind the paused overlay, for tests.
    var isShowingPaused: Bool { !pausedOverlay.isHidden }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || navigationController?.isBeingDismissed == true {
            // Close and Add to Library stop first and ask when saving fails; this covers any
            // other dismissal, which has no screen left to ask from.
            try? stopRuntime()
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
            pausedOverlay.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pausedOverlay.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
        ])
    }

    private lazy var gameMenu = makeGameMenu()

    /// The game menu, built when it opens so it shows the current pause, speed and save states.
    private func makeGameMenu() -> UIMenu {
        UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                MainActor.assumeIsolated { completion(self?.menuElements() ?? []) }
            },
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
            self.toggleFastForward()
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
                    subtitle: formatter.string(from: state.createdAt),
                    image: states.thumbnailData(for: state).flatMap { Self.menuThumbnail($0) }
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
        } else {
            elements.append(UIAction(
                title: "Save State",
                subtitle: "Add to Library to save states",
                image: UIImage(systemName: "square.and.arrow.down"),
                attributes: .disabled
            ) { _ in })
        }
        if onAddToLibrary != nil {
            elements.append(UIAction(title: "Add to Library…", image: UIImage(systemName: "square.and.arrow.down.on.square")) { [weak self] _ in
                self?.addToLibraryTapped()
            })
        }
        let close = UIAction(title: "Close Game", image: UIImage(systemName: "xmark"), attributes: .destructive) { [weak self] _ in
            self?.closeTapped()
        }
        elements.append(UIMenu(options: .displayInline, children: [close]))
        return elements
    }

    /// A state's thumbnail at menu-icon size, with the pixels kept sharp.
    private static func menuThumbnail(_ data: Data) -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        let size = CGSize(width: 40, height: 36)
        return UIGraphicsImageRenderer(size: size).image { context in
            context.cgContext.interpolationQuality = .none
            image.draw(in: CGRect(origin: .zero, size: size))
        }
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

    /// A state carries the game save from when it was made, so loading one older than the
    /// current save asks first and keeps the newer save as a copy.
    private func loadState(_ state: SaveState) {
        guard let states = runtime as? any SaveStateRuntime else { return }
        do {
            guard try states.loadingWouldRollBackSave(state) else {
                try states.loadState(state)
                showTransientMessage("State loaded.")
                return
            }
        } catch {
            showTransientMessage("Couldn’t load that state: \(error)")
            return
        }
        let alert = UIAlertController(
            title: "Load an Older State?",
            message: "This state is older than the game’s save, so loading it takes the save back to then. The current save is kept as a copy named “before loading state”.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Load State", style: .default) { [weak self] _ in
            guard let states = self?.runtime as? any SaveStateRuntime else { return }
            do {
                try states.loadStateKeepingCopy(state)
                self?.showTransientMessage("State loaded. The newer save was kept as a copy.")
            } catch {
                self?.showTransientMessage("Couldn’t load that state: \(error)")
            }
        })
        present(alert, animated: true)
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
        driver.onSaveError = { [weak self] _ in
            DispatchQueue.main.async {
                self?.showTransientMessage("Couldn’t save the game. Free up space on your iPhone; it will keep trying.")
            }
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
        touchControls.style = controlStyle
        touchControls.scaling = screenScaling
        touchControls.theme = controllerTheme
        touchControls.pictureOpensMenu = tapGameForMenu
        touchControls.onInputChanged = { [weak self] input in self?.input.setTouch(input) }
        touchControls.onLayoutChanged = { [weak self] layout in self?.applyLayout(layout) }
        controllerMonitor.onInputChanged = { [weak self] controllerInput in
            guard let self else { return }
            self.input.setController(controllerInput)
            if self.touchControlsRevealed, controllerInput != EmulatorInputState() {
                self.touchControlsRevealed = false
                self.updateTouchControls(controllerConnected: true)
            }
        }
        controllerMonitor.onConnectionChanged = { [weak self] connected in
            guard let self else { return }
            self.touchControlsRevealed = false
            self.updateTouchControls(controllerConnected: connected)
            self.rumble.setController(self.controllerMonitor.activeController)
        }
        controllerMonitor.onUnexpectedDisconnect = { [weak self] in
            guard let self else { return }
            self.userPaused = true
            self.pauseGameplay()
            self.touchControlsRevealed = false
            self.updateTouchControls(controllerConnected: false)
            self.input.resetController()
            self.showTransientMessage("Controller disconnected. Game paused.")
        }

        updateTouchControls(controllerConnected: controllerMonitor.isConnected)
        rumble.setController(controllerMonitor.activeController)
    }

    /// With a controller connected the touch controls hide, unless Settings keeps them or a touch
    /// brought them back. Their haptics follow them, so a controller player feels only rumble.
    private func updateTouchControls(controllerConnected: Bool) {
        let shows = !controllerConnected || !hidesTouchControlsWithController || touchControlsRevealed
        touchControls.showsControls = shows
        touchControls.hapticIntensity = shows ? touchHaptics.intensity : nil
    }

    /// Touches reach this controller only while the touch controls are hidden, since they take
    /// every touch otherwise; the menu buttons take their own.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard !touchControls.showsControls else { return }
        touchControlsRevealed = true
        updateTouchControls(controllerConnected: controllerMonitor.isConnected)
    }

    private func applyLayout(_ layout: TouchControlLayout) {
        let screen = layout.screen
        renderer?.screenRect = screen.width > 0
            ? CGRect(x: screen.x, y: screen.y, width: screen.width, height: screen.height)
            : nil
        placeMenuButtons(over: layout.menuAreas)
    }

    /// The menu buttons sit under the paused overlay and above the touch controls, which pass
    /// touches through with a controller connected, so the logo opens the menu either way.
    private func placeMenuButtons(over areas: [TouchRect]) {
        while menuButtons.count < areas.count {
            let button = GameMenuButton(menu: gameMenu)
            // Where a menu area overlaps a control, as on narrow screens, the control wins.
            button.yieldsTouch = { [weak self] point in
                guard let self, self.touchControls.showsControls else { return false }
                return !self.touchControls.layout.opensMenu(at: TouchPoint(x: point.x, y: point.y))
            }
            view.insertSubview(button, aboveSubview: touchControls)
            menuButtons.append(button)
        }
        for (index, button) in menuButtons.enumerated() {
            guard index < areas.count else {
                button.isHidden = true
                continue
            }
            let area = areas[index]
            button.isHidden = false
            button.frame = CGRect(x: area.x, y: area.y, width: area.width, height: area.height)
            // The first area is the logo; VoiceOver finds the menu there, once.
            button.isAccessibilityElement = index == 0
        }
    }

    private func toggleFastForward() {
        fastForward.toggle()
        driver.setSpeed(fastForward ? .multiplier(2) : .normal)
    }

    private func observeLifecycle() {
        let center = NotificationCenter.default
        lifecycleObservers.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Saved before this returns: iOS can suspend the app soon after, and a hop to a later
            // main-queue turn could leave the writes half done.
            MainActor.assumeIsolated { self?.backgrounded() }
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
        // Asks iOS for time to finish writing the save and Auto State before suspending.
        let saving = UIApplication.shared.beginBackgroundTask(withName: "Save game")
        defer {
            if saving != .invalid { UIApplication.shared.endBackgroundTask(saving) }
        }
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
                resumeAudio()
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

    /// Sound is optional: the game keeps running silently when audio can't start.
    private func resumeAudio() {
        do {
            try audio.resume()
        } catch {
            showTransientMessage("Sound is unavailable right now.")
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
            resumeAudio()
            userPaused = false
            pausedOverlay.isHidden = true
            driver.start()
        } catch {
            presentRuntimeError(error)
        }
    }

    private enum Exit {
        case close
        case addToLibrary
    }

    private func closeTapped() {
        finish(.close)
    }

    private func addToLibraryTapped() {
        finish(.addToLibrary)
    }

    /// Saves and closes the game, then closes or adds it to the library. When saving fails the
    /// game stays open and paused, and the player chooses to try again or to close without the
    /// save.
    private func finish(_ exit: Exit) {
        do {
            try stopRuntime()
        } catch {
            let alert = UIAlertController(
                title: "Couldn’t Save",
                message: "The game couldn’t be saved, so closing now would lose your latest progress. Free up space on your iPhone, then try again. (\(error))",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Try Again", style: .default) { [weak self] _ in
                self?.finish(exit)
            })
            alert.addAction(UIAlertAction(title: "Close Without Saving", style: .destructive) { [weak self] _ in
                guard let self else { return }
                try? self.runtime.stop(createAutoState: true, discardUnsaved: true)
                self.stopped = true
                self.leave(exit)
            })
            present(alert, animated: true)
            return
        }
        leave(exit)
    }

    private func leave(_ exit: Exit) {
        dismiss(animated: true)
        switch exit {
        case .close: onClose?()
        case .addToLibrary: onAddToLibrary?()
        }
    }

    /// A failed stop leaves the session open, so `stopped` stays false and the next call retries.
    private func stopRuntime() throws {
        guard !stopped else { return }
        driver.stop()
        audio.stop()
        try runtime.stop(createAutoState: true)
        stopped = true
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

/// A clear button over a menu area that opens the game menu where the finger landed.
private final class GameMenuButton: UIButton {
    /// Whether a point in the superview belongs to something under the button instead.
    var yieldsTouch: ((CGPoint) -> Bool)?

    init(menu: UIMenu) {
        super.init(frame: .zero)
        self.menu = menu
        showsMenuAsPrimaryAction = true
        accessibilityLabel = "Game Menu"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard super.point(inside: point, with: event) else { return false }
        return !(yieldsTouch?(convert(point, to: superview)) ?? false)
    }

    override func menuAttachmentPoint(for configuration: UIContextMenuConfiguration) -> CGPoint {
        contextMenuInteraction?.location(in: self) ?? super.menuAttachmentPoint(for: configuration)
    }
}

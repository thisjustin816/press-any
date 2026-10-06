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
    private var pauseReasons = GameplayPauseReasons()
    private var coveredBySheet = false
    /// Set when the scene went to the background, so returning applies Resume Games.
    private var backgrounded = false
    /// Set once an emulation error has stopped the game for good.
    private var halted = false
    private var controlStyle: TouchControlStyle
    private var lcdFilter: LCDFilter
    private var frameBlending: FrameBlending
    private var screenScaling: ScreenScaling
    private let controllerTheme: ControllerTheme
    private let tapGameForMenu: Bool
    private let soundMode: SoundMode
    private let hidesTouchControlsWithController: Bool
    private let touchHaptics: TouchHaptics
    /// Set by a touch while a controller hides the touch controls, and cleared by the controller's
    /// next button press.
    private var touchControlsRevealed = false
    /// The wordmark button and optional clear picture target share the same game menu.
    private var menuButtons: [GameMenuButton] = []
    private var fastForward = false
    // Appended only on the main actor and read only in deinit, which runs once nothing else can
    // reach the controller, so the nonisolated deinit can remove the observers without a hop.
    nonisolated(unsafe) private var lifecycleObservers: [NSObjectProtocol] = []
    private var stopped = false

    var onClose: (() -> Void)?
    /// Set for Quick Play: the menu then offers Add to Library, which closes the game and calls this.
    var onAddToLibrary: (() -> Void)?
    /// When set, the menu offers Settings, which calls this. The game stays paused under the
    /// settings, which arrive through `applyDisplaySettings` as they change.
    var onOpenSettings: (() -> Void)?

    init(
        runtime: any GameplayRuntime,
        autoResumePolicy: AutoResumePolicy,
        launchMessage: String? = nil,
        firstFrameClock: UInt64? = nil,
        controlStyle: TouchControlStyle = .gameBoy,
        screenScaling: ScreenScaling = .integer,
        lcdFilter: LCDFilter = .off,
        frameBlending: FrameBlending = .off,
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
        self.lcdFilter = lcdFilter
        self.frameBlending = frameBlending
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
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: GameplayViewController, _: UITraitCollection) in
            self.updateMenuButtonAppearance()
        }

        renderer = MetalRenderer(view: metalView)
        renderer?.scaling = screenScaling
        renderer?.lcdFilter = lcdFilter
        renderer?.frameBlending = frameBlending
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
        // Introduce the menu button once, on the first game played.
        if !UserDefaults.standard.bool(forKey: Self.menuHintShownKey) {
            UserDefaults.standard.set(true, forKey: Self.menuHintShownKey)
            message = [message, "Tap \(AppBrand.displayName) for the menu."].compactMap { $0 }.joined(separator: " ")
        }
        // Nothing is paused yet. Starting directly keeps a failed audio start to the one message.
        driver.start()
        if let message { showTransientMessage(message) }
    }

    private static let menuHintShownKey = "gameplay.menuHintShown"

    /// Whether the touch controls are showing, for tests.
    var showsTouchControls: Bool { touchControls.showsControls }
    /// Whether gameplay is paused behind the paused overlay, for tests.
    var isShowingPaused: Bool { !pausedOverlay.isHidden }
    /// Whether frames are running, for tests.
    var isRunningFrames: Bool { driver.isRunning }
    /// The buttons the game sees held, for tests.
    var heldInput: EmulatorInputState { input.current() }
    /// The controller layout drawn, for tests.
    var touchControlStyle: TouchControlStyle { touchControls.style }

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
        pausedOverlay.accessibilityLabel = "Resume Game"
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
                MainActor.assumeIsolated { completion(self?.prepareGameMenu() ?? []) }
            },
        ])
    }

    func prepareGameMenu() -> [UIMenuElement] {
        pauseGameplay()
        var elements: [UIMenuElement] = []
        if pausedOverlay.isHidden {
            elements.append(UIAction(title: "Pause", image: UIImage(systemName: "pause.fill")) { [weak self] _ in
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
        if onOpenSettings != nil {
            elements.append(UIAction(title: "Settings…", image: UIImage(systemName: "gearshape")) { [weak self] _ in
                self?.onOpenSettings?()
            })
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
        holdFrames()
        defer { releaseFrames() }
        do {
            _ = try states.saveManualState(label: nil)
            showTransientMessage("State saved.")
        } catch {
            showTransientMessage("Couldn’t save the state: \(error)")
        }
    }

    /// A state carries the game save from when it was made, so loading one older than the
    /// current save asks first and keeps the newer save as a copy. Frames stay stopped from the
    /// check until the state is loaded or the player cancels, so the game can't save in between.
    private func loadState(_ state: SaveState) {
        guard let states = runtime as? any SaveStateRuntime else { return }
        holdFrames()
        do {
            guard try states.loadingWouldRollBackSave(state) else {
                try states.loadState(state)
                releaseFrames()
                showTransientMessage("State loaded.")
                return
            }
        } catch {
            releaseFrames()
            showTransientMessage("Couldn’t load that state: \(error)")
            return
        }
        let alert = UIAlertController(
            title: "Load an Older State?",
            message: "This state is older than the game’s save, so loading it takes the save back to then. The current save is kept as a copy named “before loading state”.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.releaseFrames()
        })
        alert.addAction(UIAlertAction(title: "Load State", style: .default) { [weak self] _ in
            guard let self else { return }
            defer { self.releaseFrames() }
            guard let states = self.runtime as? any SaveStateRuntime else { return }
            do {
                try states.loadStateKeepingCopy(state)
                self.showTransientMessage("State loaded. The newer save was kept as a copy.")
            } catch {
                self.showTransientMessage("Couldn’t load that state: \(error)")
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
        // A paused game draws only when asked, so a new layout redraws the held picture in place.
        metalView.setNeedsDisplay()
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
        updateMenuButtonAppearance()
    }

    private func updateMenuButtonAppearance() {
        let palette = ControllerPalette.resolve(controllerTheme, for: traitCollection)
        for (index, button) in menuButtons.enumerated() {
            button.configureWordmark(palette: index == 0 ? palette : nil)
        }
    }

    /// Settings changed while the game is open, from its settings sheet. The paused picture redraws
    /// with them, so the player sees each change behind the sheet.
    func applyDisplaySettings(
        controlStyle: TouchControlStyle,
        screenScaling: ScreenScaling,
        lcdFilter: LCDFilter,
        frameBlending: FrameBlending
    ) {
        guard controlStyle != self.controlStyle || screenScaling != self.screenScaling
            || lcdFilter != self.lcdFilter || frameBlending != self.frameBlending else { return }
        self.controlStyle = controlStyle
        self.screenScaling = screenScaling
        self.lcdFilter = lcdFilter
        self.frameBlending = frameBlending
        // The touch controls lay out again and report the new layout, which moves the picture.
        touchControls.style = controlStyle
        touchControls.scaling = screenScaling
        renderer?.scaling = screenScaling
        renderer?.lcdFilter = lcdFilter
        renderer?.frameBlending = frameBlending
        metalView.setNeedsDisplay()
    }

    private func toggleFastForward() {
        fastForward.toggle()
        driver.setSpeed(fastForward ? .multiplier(2) : .normal)
    }

    /// Follows this game's own scene, so another window's changes don't pause or resume it.
    private func observeLifecycle() {
        let names: [Notification.Name] = [
            UIScene.willDeactivateNotification,
            UIScene.didEnterBackgroundNotification,
            UIScene.didActivateNotification,
        ]
        for name in names {
            lifecycleObservers.append(NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                // Only Sendable values cross into the main-actor block.
                let posted = notification.name
                let scene = (notification.object as? UIScene).map(ObjectIdentifier.init)
                // Handled before this returns: entering the background, iOS can suspend the app
                // soon after, and a hop to a later main-queue turn could leave the save half done.
                MainActor.assumeIsolated {
                    guard let self, self.isOwnScene(scene) else { return }
                    switch posted {
                    case UIScene.willDeactivateNotification: self.sceneWillDeactivate()
                    case UIScene.didEnterBackgroundNotification: self.sceneDidEnterBackground()
                    default: self.sceneDidActivate()
                    }
                }
            })
        }
    }

    /// Before the view is in a window its scene is unknown, and any scene counts.
    private func isOwnScene(_ scene: ObjectIdentifier?) -> Bool {
        guard let own = view.window?.windowScene else { return true }
        return scene == ObjectIdentifier(own)
    }

    /// Something covered the game or the app is leaving: stop frames and let go of every button,
    /// so nothing stays held while the player can't see the game.
    func sceneWillDeactivate() {
        touchControls.cancelInput()
        input.resetTouch()
        input.resetController()
        pauseReasons.inactive = true
        applyPauseReasons()
    }

    func sceneDidEnterBackground() {
        sceneWillDeactivate()
        guard !stopped, !halted, !backgrounded else { return }
        backgrounded = true
        // Asks iOS for time to finish writing the save and Auto State before suspending.
        let saving = UIApplication.shared.beginBackgroundTask(withName: "Save game")
        defer {
            if saving != .invalid { UIApplication.shared.endBackgroundTask(saving) }
        }
        do { try runtime.background() }
        catch { presentRuntimeError(error) }
    }

    /// Back in front. After a trip to the background, Resume Games decides; after only an
    /// overlay such as Control Center, the game picks up where it was (docs/decisions.md). A game
    /// the player paused stays paused either way.
    func sceneDidActivate() {
        pauseReasons.inactive = false
        defer { applyPauseReasons() }
        guard backgrounded else { return }
        backgrounded = false
        guard !stopped, !halted, !pauseReasons.byPlayer else { return }
        do {
            if try runtime.foreground(policy: autoResumePolicy) { return }
        } catch {
            presentRuntimeError(error)
            return
        }
        pauseReasons.awaitingResume = true
        if autoResumePolicy == .ask, presentedViewController == nil {
            let alert = UIAlertController(title: "Resume Game?", message: nil, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Not Now", style: .cancel))
            alert.addAction(UIAlertAction(title: "Resume", style: .default) { [weak self] _ in
                self?.resumeTapped()
            })
            present(alert, animated: true)
        }
    }

    /// Starts or stops frames and sound to match the pause reasons. Every pause and resume goes
    /// through here.
    private func applyPauseReasons() {
        guard !stopped, !halted else { return }
        pausedOverlay.isHidden = !pauseReasons.showsPausedOverlay
        if pauseReasons.shouldRun {
            guard !driver.isRunning else { return }
            resumeAudio()
            driver.start()
        } else if driver.isRunning {
            driver.stop()
            audio.pause()
        }
    }

    private func holdFrames() {
        pauseReasons.holds += 1
        applyPauseReasons()
    }

    private func releaseFrames() {
        pauseReasons.holds = max(0, pauseReasons.holds - 1)
        applyPauseReasons()
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
        touchControls.cancelInput()
        input.resetTouch()
        input.resetController()
        pauseReasons.byPlayer = true
        applyPauseReasons()
        try? runtime.pause()
    }

    private func resumeTapped() {
        do {
            try runtime.resume()
            pauseReasons.byPlayer = false
            pauseReasons.awaitingResume = false
            applyPauseReasons()
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

    /// Closes the game as the menu's Close Game does, for a caller replacing it with another game.
    func requestClose() {
        closeTapped()
    }

    /// A sheet over the game, such as a file shared mid-game, pauses it as the game menu does, so
    /// the player resumes when the sheet closes. A sheet never opens over this screen's own alerts,
    /// the Resume Game? prompt included: a shared file waits until the player answers it.
    func setCoveredBySheet(_ covered: Bool) {
        guard covered != coveredBySheet else { return }
        coveredBySheet = covered
        guard covered else { return }
        pauseGameplay()
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
        halted = true
        driver.stop()
        audio.pause()
        guard presentedViewController == nil else { return }
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

/// The logo has a raised face with the wordmark pressed into it; an optional game-picture target
/// remains clear.
private final class GameMenuButton: UIButton {
    private let face = CAGradientLayer()
    private let wordmark = UIImageView()
    private var palette: ControllerPalette?
    /// The width the wordmark image was drawn for, so layout redraws it only when that changes. A
    /// new palette clears it.
    private var drawnWordmarkWidth: CGFloat?
    /// Whether a point in the superview belongs to something under the button instead.
    var yieldsTouch: ((CGPoint) -> Bool)?

    init(menu: UIMenu) {
        super.init(frame: .zero)
        self.menu = menu
        showsMenuAsPrimaryAction = true
        accessibilityLabel = "Game Menu"
        accessibilityHint = "Pauses the game and opens the menu"
        layer.insertSublayer(face, at: 0)
        wordmark.isUserInteractionEnabled = false
        wordmark.contentMode = .center
        addSubview(wordmark)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowRadius = 2
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configureWordmark(palette: ControllerPalette?) {
        self.palette = palette
        face.isHidden = palette == nil
        wordmark.isHidden = palette == nil
        if let palette {
            face.borderColor = palette.logo.withAlphaComponent(0.35).cgColor
            face.borderWidth = 1
        }
        drawnWordmarkWidth = nil
        updatePressedAppearance()
        setNeedsLayout()
    }

    override var isHighlighted: Bool {
        didSet { updatePressedAppearance() }
    }

    private func updatePressedAppearance() {
        guard let palette else {
            layer.shadowOpacity = 0
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        face.colors = isHighlighted
            ? [palette.bodyBottom.cgColor, palette.bodyBottom.cgColor]
            : [palette.bodyTop.cgColor, palette.bodyBottom.cgColor]
        layer.shadowOpacity = isHighlighted ? 0.15 : 0.4
        layer.shadowOffset = CGSize(width: 0, height: isHighlighted ? 1 : 3)
        CATransaction.commit()
        wordmark.transform = CGAffineTransform(translationX: 0, y: isHighlighted ? 1 : 0)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        face.frame = bounds
        face.cornerRadius = bounds.height / 2
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: bounds.height / 2).cgPath
        CATransaction.commit()
        wordmark.bounds = bounds
        wordmark.center = CGPoint(x: bounds.midX, y: bounds.midY)
        if let palette, drawnWordmarkWidth != bounds.width {
            wordmark.image = Self.debossedWordmark(fitting: bounds.width - 16, palette: palette)
            drawnWordmarkWidth = bounds.width
        }
    }

    /// The wordmark at 28 points, or down to 80% of that to fit `width`, pressed into the face. Lit
    /// from above, each letter's top edge shades the floor of its recess, which shows as a band
    /// in the recess colors, and its bottom edge catches the light, which shows as a line below.
    private static func debossedWordmark(fitting width: CGFloat, palette: ControllerPalette) -> UIImage {
        let natural = AppBrand.Wordmark.attributedString(size: 28, ink: palette.logo, accent: palette.logoAccent).size()
        let size = 28 * min(1, max(0.8, width / max(natural.width, 1)))
        let fill = AppBrand.Wordmark.attributedString(size: size, ink: palette.logo, accent: palette.logoAccent)
        let recess = AppBrand.Wordmark.attributedString(size: size, ink: palette.logoRecess, accent: palette.logoAccentRecess)
        let highlight = AppBrand.Wordmark.attributedString(size: size, ink: palette.logoHighlight, accent: palette.logoHighlight)
        let textSize = fill.size()
        let canvas = CGSize(width: ceil(textSize.width) + 2, height: ceil(textSize.height) + 2)
        let origin = CGPoint(x: 1, y: 0)
        // One point deep, so the edges land on whole pixels.
        let depth: CGFloat = 1
        func image(_ draw: () -> Void) -> UIImage {
            UIGraphicsImageRenderer(size: canvas).image { _ in draw() }
        }
        let shaded = image { recess.draw(at: origin) }
        let lit = image { fill.draw(at: CGPoint(x: origin.x, y: origin.y + depth)) }
        // Source-atop keeps the lit letters inside the shaded ones, so the shade stays only along
        // the top edges.
        let letters = image {
            shaded.draw(at: .zero)
            lit.draw(at: .zero, blendMode: .sourceAtop, alpha: 1)
        }
        return image {
            highlight.draw(at: CGPoint(x: origin.x, y: origin.y + 1))
            letters.draw(at: .zero)
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard super.point(inside: point, with: event) else { return false }
        return !(yieldsTouch?(convert(point, to: superview)) ?? false)
    }

    override func menuAttachmentPoint(for configuration: UIContextMenuConfiguration) -> CGPoint {
        contextMenuInteraction?.location(in: self) ?? super.menuAttachmentPoint(for: configuration)
    }
}

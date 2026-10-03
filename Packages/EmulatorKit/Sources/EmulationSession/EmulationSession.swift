import EmulatorApplication
import EmulatorDomain
import EmulationCore
import Foundation

public enum EmulationSessionState: Equatable, Sendable {
    case idle
    case loading(LaunchContext)
    case running(LaunchContext)
    case paused(LaunchContext)
    case stopped
}

public enum EmulationSessionError: Error, Equatable {
    case buildNotFound(UUID)
    case saveProfileNotFound(UUID)
    case romAssetNotFound(UUID)
    case buildGameMismatch
    case profileGameMismatch
    case noActiveSession
    case sessionNotRunning
}

public final class EmulationSession: @unchecked Sendable {
    private let builds: any BuildRepository
    private let profiles: any SaveProfileRepository
    private let assets: any ManagedAssetRepository
    private let assetStore: any AssetStore
    private let imageResolver: any BuildImageResolving
    private let coreResolver: ResolveCoreForBuild
    private let persistentSaveService: PersistentSaveService
    private let stateService: SaveStateService
    private let settings: SettingsResolver?

    private let lock = NSLock()
    private var _state: EmulationSessionState = .idle
    private var worker: SessionWorker?
    private var activeContext: LaunchContext?
    private var sessionEmulatedNanoseconds: UInt64 = 0
    private var basePlaytimeSeconds: Double = 0
    private var latestFrame: EmulatorVideoFrame?

    public init(
        builds: any BuildRepository,
        profiles: any SaveProfileRepository,
        states: any SaveStateRepository,
        assets: any ManagedAssetRepository,
        assetStore: any AssetStore,
        imageResolver: any BuildImageResolving,
        coreRegistry: CoreRegistry,
        settings: SettingsResolver? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.builds = builds
        self.profiles = profiles
        self.assets = assets
        self.assetStore = assetStore
        self.imageResolver = imageResolver
        self.coreResolver = ResolveCoreForBuild(builds: builds, registry: coreRegistry, now: now)
        self.persistentSaveService = PersistentSaveService(profiles: profiles, assets: assets, assetStore: assetStore, now: now)
        self.stateService = SaveStateService(states: states, assets: assets, assetStore: assetStore, now: now)
        self.settings = settings
    }

    public var state: EmulationSessionState {
        lock.withLock { _state }
    }

    public var currentFrame: EmulatorVideoFrame? {
        lock.withLock { latestFrame }
    }

    public var playtimeSeconds: Double {
        lock.withLock { basePlaytimeSeconds + Double(sessionEmulatedNanoseconds) / 1_000_000_000 }
    }

    public func start(context: LaunchContext) throws {
        lock.withLock { _state = .loading(context) }
        do {
            guard let build = try builds.fetchBuild(id: context.buildID) else {
                throw EmulationSessionError.buildNotFound(context.buildID)
            }
            guard build.gameID == context.gameID else {
                throw EmulationSessionError.buildGameMismatch
            }
            guard let profile = try profiles.fetchSaveProfile(id: context.saveProfileID) else {
                throw EmulationSessionError.saveProfileNotFound(context.saveProfileID)
            }
            guard profile.gameID == context.gameID else {
                throw EmulationSessionError.profileGameMismatch
            }
            let romURL = try imageResolver.resolveImageURL(buildID: build.id)
            let rom = try assetStore.readData(at: romURL)
            let core = try coreResolver.execute(buildID: build.id)
            let newWorker = SessionWorker(core: core)
            try newWorker.perform { try $0.loadImage(rom, system: build.system) }
            let battery = try persistentSaveService.loadPersistentSave(for: profile)
            try newWorker.perform { try $0.loadPersistentSave(battery) }
            if skipsBootAnimation(build) {
                try newWorker.perform { core in
                    _ = try (core as? any BootSkippingCapability)?.skipBootAnimation()
                }
            }

            lock.withLock {
                worker = newWorker
                activeContext = context
                sessionEmulatedNanoseconds = 0
                basePlaytimeSeconds = profile.totalPlaytimeSeconds
                latestFrame = nil
                _state = .running(context)
            }
        } catch {
            lock.withLock {
                worker = nil
                activeContext = nil
                latestFrame = nil
                _state = .idle
            }
            throw error
        }
    }

    /// The boot logo shows unless the setting resolved for this Build says to skip it. An unreadable
    /// setting falls back to showing it rather than blocking the launch.
    private func skipsBootAnimation(_ build: Build) -> Bool {
        let skip = try? settings?.decode(
            Bool.self,
            key: SettingKey.skipBootAnimation.rawValue,
            system: build.system,
            gameID: build.gameID,
            buildID: build.id
        )
        return skip ?? false
    }

    @discardableResult
    public func stepFrame(input: EmulatorInputState = .init()) throws -> EmulatorVideoFrame {
        let (worker, context, running) = try snapshotActive()
        guard running else { throw EmulationSessionError.sessionNotRunning }
        let frame = try worker.perform { try $0.runFrame(input: input) }
        lock.withLock {
            guard activeContext == context else { return }
            sessionEmulatedNanoseconds &+= frame.emulatedNanoseconds
            latestFrame = frame
        }
        return frame
    }

    public func drainAudio(maxFrames: Int) throws -> [StereoSample] {
        let (worker, _, _) = try snapshotActive()
        return try worker.perform { $0.drainAudio(maxFrames: maxFrames) }
    }

    public func setSpeed(_ speed: EmulationSpeed) throws {
        let (worker, _, _) = try snapshotActive()
        try worker.perform { $0.setSpeed(speed) }
    }

    public func consumeRumbleAmplitude() throws -> Double {
        let (worker, _, _) = try snapshotActive()
        return try worker.perform { core in
            (core as? any RumbleCapability)?.consumeRumbleAmplitude() ?? 0
        }
    }

    public func pause() throws {
        let (_, context, _) = try snapshotActive()
        lock.withLock { _state = .paused(context) }
    }

    public func resume() throws {
        let (_, context, _) = try snapshotActive()
        lock.withLock { _state = .running(context) }
    }

    @discardableResult
    public func flushBattery() throws -> SaveProfile {
        let (worker, context, _) = try snapshotActive()
        return try persistentSaveService.flush(worker: worker, profileID: context.saveProfileID)
    }

    @discardableResult
    public func saveManualState(label: String? = nil) throws -> SaveState {
        let (worker, context, _) = try snapshotActive()
        return try stateService.save(
            worker: worker,
            context: context,
            kind: .manual,
            label: label,
            playtimeSeconds: playtimeSeconds
        )
    }

    @discardableResult
    public func saveAutoState() throws -> SaveState {
        let (worker, context, _) = try snapshotActive()
        return try stateService.save(
            worker: worker,
            context: context,
            kind: .auto,
            playtimeSeconds: playtimeSeconds
        )
    }

    public func loadState(_ saveState: SaveState) throws {
        let (worker, context, _) = try snapshotActive()
        try stateService.load(saveState, worker: worker, context: context)
    }

    /// App lifecycle entry point. Gameplay is paused before persistent state is captured.
    public func background() throws {
        try pause()
        _ = try flushBattery()
        _ = try saveAutoState()
    }

    /// Returns true when gameplay resumed immediately. `.ask` and `.never` remain paused.
    @discardableResult
    public func foreground(policy: AutoResumePolicy) throws -> Bool {
        switch policy {
        case .always:
            try resume()
            return true
        case .ask, .never:
            return false
        }
    }

    public func stop(createAutoState: Bool = false) throws {
        guard lock.withLock({ activeContext != nil && worker != nil }) else {
            lock.withLock { _state = .stopped }
            return
        }
        try pause()
        _ = try flushBattery()
        if createAutoState {
            _ = try saveAutoState()
        }
        lock.withLock {
            worker = nil
            activeContext = nil
            latestFrame = nil
            _state = .stopped
        }
    }

    private func snapshotActive() throws -> (SessionWorker, LaunchContext, Bool) {
        try lock.withLock {
            guard let worker, let context = activeContext else {
                throw EmulationSessionError.noActiveSession
            }
            let running: Bool
            switch _state {
            case .running:
                running = true
            default:
                running = false
            }
            return (worker, context, running)
        }
    }
}

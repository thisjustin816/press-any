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

public enum AutoStateRestore: Equatable, Sendable {
    case notRequested
    case restored(SaveState)
    /// The state was rejected and the game booted normally. The state is kept.
    case failed(SaveState)
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
    private let states: any SaveStateRepository
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
    /// Session time already added to the profile, and whether this session has been counted.
    private var recordedNanoseconds: UInt64 = 0
    private var sessionCounted = false
    private let now: @Sendable () -> Date
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
        self.states = states
        self.assets = assets
        self.assetStore = assetStore
        self.imageResolver = imageResolver
        self.now = now
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

    /// Starts the session, restoring `autoState` when one is given. A state that fails to restore
    /// boots the game normally and stays on disk for diagnosis.
    @discardableResult
    public func start(context: LaunchContext, resumeFrom autoState: SaveState? = nil) throws -> AutoStateRestore {
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
            let battery = try persistentSaveService.loadPersistentSave(for: profile)

            func bootedWorker(skipBoot: Bool) throws -> SessionWorker {
                let newWorker = SessionWorker(core: try coreResolver.execute(buildID: build.id))
                try newWorker.perform { try $0.loadImage(rom, system: build.system) }
                try newWorker.perform { try $0.loadPersistentSave(battery) }
                if skipBoot {
                    try newWorker.perform { core in
                        _ = try (core as? any BootSkippingCapability)?.skipBootAnimation()
                    }
                }
                return newWorker
            }

            let newWorker: SessionWorker
            let restore: AutoStateRestore
            if let autoState {
                let candidate = try bootedWorker(skipBoot: false)
                do {
                    try stateService.load(autoState, worker: candidate, context: context)
                    newWorker = candidate
                    restore = .restored(autoState)
                } catch {
                    // The core may hold part of the rejected state, so boot a clean one.
                    newWorker = try bootedWorker(skipBoot: skipsBootAnimation(build))
                    restore = .failed(autoState)
                }
            } else {
                newWorker = try bootedWorker(skipBoot: skipsBootAnimation(build))
                restore = .notRequested
            }

            lock.withLock {
                worker = newWorker
                activeContext = context
                sessionEmulatedNanoseconds = 0
                recordedNanoseconds = 0
                sessionCounted = false
                basePlaytimeSeconds = profile.totalPlaytimeSeconds
                latestFrame = nil
                _state = .running(context)
            }
            return restore
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

    /// The newest Auto State for `context` that is safe to restore, or nil.
    ///
    /// A state carries the cartridge RAM it was taken with. Once the profile's battery save has been
    /// written after the state, by this Build or another one sharing the profile, restoring the state
    /// would roll that save back, so the state is not offered.
    public func resumableAutoState(for context: LaunchContext) throws -> SaveState? {
        guard let profile = try profiles.fetchSaveProfile(id: context.saveProfileID) else {
            throw EmulationSessionError.saveProfileNotFound(context.saveProfileID)
        }
        let newest = try states.fetchSaveStates(buildID: context.buildID, saveProfileID: context.saveProfileID)
            .filter { $0.kind == .auto }
            .max { ($0.autoSequence ?? 0, $0.createdAt) < ($1.autoSequence ?? 0, $1.createdAt) }
        guard let newest, profile.modifiedAt <= newest.createdAt else { return nil }
        return newest
    }

    /// The resolved launch and foreground policy for `context`. Unset or unreadable means `.always`.
    public func autoResumePolicy(for context: LaunchContext) -> AutoResumePolicy {
        guard let build = try? builds.fetchBuild(id: context.buildID) else { return .always }
        let policy = try? settings?.decode(
            AutoResumePolicy.self,
            key: SettingKey.autoResumePolicy.rawValue,
            system: build.system,
            gameID: build.gameID,
            buildID: build.id
        )
        return policy ?? .always
    }

    /// Manual and Auto States for the active Build and profile, newest first.
    public func saveStates() throws -> [SaveState] {
        let (_, context, _) = try snapshotActive()
        return try states.fetchSaveStates(buildID: context.buildID, saveProfileID: context.saveProfileID)
            .sorted { $0.createdAt > $1.createdAt }
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
        return try persistentSaveService.flush(worker: worker, profileID: context.saveProfileID, buildID: context.buildID)
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
        try recordPlaytime()
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
        try recordPlaytime()
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

    /// Adds the time played since the last call to the profile, counts the session once, and
    /// stamps lastPlayedAt. modifiedAt is left alone: it marks battery writes, which decide
    /// whether an Auto State is still safe to restore.
    private func recordPlaytime() throws {
        let (_, context, _) = try snapshotActive()
        let (unrecorded, firstRecord) = lock.withLock { () -> (UInt64, Bool) in
            let delta = sessionEmulatedNanoseconds &- recordedNanoseconds
            recordedNanoseconds = sessionEmulatedNanoseconds
            defer { sessionCounted = true }
            return (delta, !sessionCounted)
        }
        guard var profile = try profiles.fetchSaveProfile(id: context.saveProfileID) else {
            throw EmulationSessionError.saveProfileNotFound(context.saveProfileID)
        }
        profile.totalPlaytimeSeconds += Double(unrecorded) / 1_000_000_000
        if firstRecord { profile.sessionCount += 1 }
        profile.lastPlayedAt = now()
        try profiles.updateSaveProfile(profile)
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

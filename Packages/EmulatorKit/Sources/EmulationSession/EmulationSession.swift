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

/// The save steps of a background or stop that failed. Each step is attempted whether or not
/// an earlier one failed, so a failed battery write still leaves an Auto State to resume from.
public struct SessionSaveError: Error {
    public let failures: [any Error]

    public static func attempting(_ steps: [() throws -> Void]) throws {
        var failures: [any Error] = []
        for step in steps {
            do { try step() } catch { failures.append(error) }
        }
        guard failures.isEmpty else { throw SessionSaveError(failures: failures) }
    }
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
    private let launchHistory: SessionLaunchHistory?
    private let transactions: any LibraryTransactionRunner
    private let inFlight: InFlightFiles?
    private var lastCheckpointNanoseconds: UInt64 = 0

    private let lock = NSLock()
    private let playtimeRecordingLock = NSLock()
    private var _state: EmulationSessionState = .idle
    private var worker: SessionWorker?
    private var activeContext: LaunchContext?
    /// Holds the running game's image from launch until the session ends.
    private var imageLease: InFlightFiles.Lease?
    private var sessionEmulatedNanoseconds: UInt64 = 0
    private var basePlaytimeSeconds: Double = 0
    /// Session time already added to the Build and profile, and whether this session has been counted.
    private var recordedNanoseconds: UInt64 = 0
    private var sessionCounted = false
    private let now: @Sendable () -> Date
    private var latestFrame: EmulatorVideoFrame?
    private let batteryCheckIntervalNanoseconds: UInt64
    private var lastBatteryCheckNanoseconds: UInt64 = 0
    private var lastWrittenBattery = Data()

    public init(
        builds: any BuildRepository,
        profiles: any SaveProfileRepository,
        states: any SaveStateRepository,
        assets: any ManagedAssetRepository,
        assetStore: any AssetStore,
        imageResolver: any BuildImageResolving,
        coreRegistry: CoreRegistry,
        settings: SettingsResolver? = nil,
        launchHistory: SessionLaunchHistory? = nil,
        transactions: any LibraryTransactionRunner = PassthroughTransactionRunner(),
        thumbnails: (any FrameImageEncoding)? = nil,
        deletion: LibraryDeletionOperations? = nil,
        inFlight: InFlightFiles? = nil,
        batteryCheckInterval: TimeInterval = 5,
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
        self.stateService = SaveStateService(
            states: states,
            assets: assets,
            assetStore: assetStore,
            settings: settings,
            deletion: deletion,
            transactions: transactions,
            thumbnails: thumbnails,
            now: now
        )
        self.settings = settings
        self.launchHistory = launchHistory
        self.transactions = transactions
        self.inFlight = inFlight
        self.batteryCheckIntervalNanoseconds = UInt64(batteryCheckInterval * 1_000_000_000)
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

    /// Starts the session, restoring the supplied state when one is given. A state that fails to restore
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
            // Held before the image is resolved, so trimming the patched ROM cache can't remove it
            // between resolving and reading it, or while the game runs.
            let lease = inFlight?.lease()
            if let image = try assets.fetchAsset(id: build.imageAssetID) { lease?.hold(image.relativePath) }
            let romURL = try imageResolver.resolveImageURL(buildID: build.id)
            let rom = try assetStore.readData(at: romURL)
            let battery = try persistentSaveService.loadPersistentSave(for: profile)
            // The save as the core reports it, which can differ in size from the file, so an
            // unchanged save isn't mistaken for a new one.
            var savedBattery = Data()

            func bootedWorker(skipBoot: Bool) throws -> SessionWorker {
                let newWorker = SessionWorker(core: try coreResolver.execute(buildID: build.id))
                try newWorker.perform { try $0.loadImage(rom, system: build.system) }
                try newWorker.perform { try $0.loadPersistentSave(battery) }
                savedBattery = try newWorker.perform { try $0.persistentSaveData() }
                if skipBoot {
                    try newWorker.perform { core in
                        _ = try (core as? any BootSkippingCapability)?.skipBootAnimation()
                    }
                }
                return newWorker
            }

            try launchHistory?.started(context)
            for profile in try profiles.fetchSaveProfiles(gameID: context.gameID) {
                try stateService.removeCrashRecoveryStates(
                    context: LaunchContext(gameID: context.gameID, buildID: context.buildID, saveProfileID: profile.id),
                    keeping: autoState?.kind == .crashRecovery ? autoState?.id : nil
                )
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
                imageLease = lease
                sessionEmulatedNanoseconds = 0
                recordedNanoseconds = 0
                sessionCounted = false
                basePlaytimeSeconds = profile.totalPlaytimeSeconds
                latestFrame = nil
                lastBatteryCheckNanoseconds = 0
                lastCheckpointNanoseconds = 0
                lastWrittenBattery = savedBattery
                _state = .running(context)
            }
            return restore
        } catch {
            lock.withLock {
                worker = nil
                activeContext = nil
                imageLease = nil
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

    /// Manual, Quick and Auto States for the active Build and profile, newest first.
    public func saveStates() throws -> [SaveState] {
        let (_, context, _) = try snapshotActive()
        return try states.fetchSaveStates(buildID: context.buildID, saveProfileID: context.saveProfileID)
            .filter { $0.kind != .crashRecovery }
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

    @discardableResult
    public func setDisplaySettings(colorCorrection: ColorCorrection, dmgPalette: DMGPalette) throws -> EmulatorVideoFrame? {
        let (worker, context, _) = try snapshotActive()
        let frame = try worker.perform { core in
            try (core as? any DisplaySettingsCapability)?.setDisplaySettings(colorCorrection: colorCorrection, dmgPalette: dmgPalette)
        }
        if let frame {
            lock.withLock {
                if activeContext == context { latestFrame = frame }
            }
        }
        return frame
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
        try launchHistory?.started(context)
        lock.withLock { _state = .running(context) }
    }

    @discardableResult
    public func flushBattery() throws -> SaveProfile {
        let (worker, context, _) = try snapshotActive()
        let battery = try worker.perform { try $0.persistentSaveData() }
        let profile = try persistentSaveService.replacePersistentSaveData(
            battery,
            profileID: context.saveProfileID,
            writtenByBuildID: context.buildID
        )
        lock.withLock { lastWrittenBattery = battery }
        return profile
    }

    /// Writes the game's battery save if it changed, checking at most once per check interval of
    /// play. Between checks it does nothing, so the frame loop can call it after every frame, and
    /// a crash or a killed app loses at most that much in-game saving. Returns true when it wrote.
    @discardableResult
    public func flushBatteryIfChanged() throws -> Bool {
        let (worker, _, _) = try snapshotActive()
        let due = lock.withLock { () -> Bool in
            guard sessionEmulatedNanoseconds &- lastBatteryCheckNanoseconds >= batteryCheckIntervalNanoseconds else {
                return false
            }
            lastBatteryCheckNanoseconds = sessionEmulatedNanoseconds
            return true
        }
        guard due else { return false }
        let battery = try worker.perform { try $0.persistentSaveData() }
        guard !battery.isEmpty, battery != lock.withLock({ lastWrittenBattery }) else { return false }
        try flushBattery()
        return true
    }

    /// Writes the game's battery save now if it changed since the last write, whatever the check
    /// interval. Returns true when it wrote.
    @discardableResult
    private func flushBatteryIfDirty() throws -> Bool {
        let (worker, _, _) = try snapshotActive()
        let battery = try worker.perform { try $0.persistentSaveData() }
        guard !battery.isEmpty, battery != lock.withLock({ lastWrittenBattery }) else { return false }
        try flushBattery()
        return true
    }

    /// Whether the game has saved since its battery save was last written.
    private func batteryIsDirty(worker: SessionWorker) throws -> Bool {
        let battery = try worker.perform { try $0.persistentSaveData() }
        return !battery.isEmpty && battery != lock.withLock({ lastWrittenBattery })
    }

    /// Writes the game's save before taking the state, so the state never holds in-game saving
    /// that isn't on disk yet. That keeps `loadingWouldRollBackSave` exact: in-game saving that
    /// is still unwritten is newer than every state.
    @discardableResult
    public func saveManualState(label: String? = nil) throws -> SaveState {
        try savePlayerState(kind: .manual, label: label)
    }

    @discardableResult
    public func saveQuickState() throws -> SaveState {
        try savePlayerState(kind: .quick)
    }

    @discardableResult
    public func saveSlotState(slot: Int) throws -> SaveState {
        try savePlayerState(kind: .slot, slot: slot)
    }

    private func savePlayerState(kind: SaveStateKind, label: String? = nil, slot: Int? = nil) throws -> SaveState {
        let (worker, context, _) = try snapshotActive()
        // A failed write leaves the save unwritten, so loading warns more often, never less.
        _ = try? flushBatteryIfDirty()
        return try stateService.save(
            worker: worker,
            context: context,
            kind: kind,
            label: label,
            slot: slot,
            playtimeSeconds: playtimeSeconds,
            frame: currentFrame
        )
    }

    @discardableResult
    public func saveAutoState() throws -> SaveState {
        let (worker, context, _) = try snapshotActive()
        _ = try? flushBatteryIfDirty()
        let state = try stateService.save(
            worker: worker,
            context: context,
            kind: .auto,
            playtimeSeconds: playtimeSeconds,
            frame: currentFrame
        )
        try stateService.removeCrashRecoveryStates(context: context)
        return state
    }

    /// Starts the game again from its boot, the way switching the cartridge off and on does. The
    /// cartridge keeps its battery-backed RAM through a reset, so the save stays. An Auto State
    /// taken first keeps the moment being left, so Load State can go back to it; when that state
    /// can't be written, the game isn't reset. Stop the frame loop before calling this.
    public func restart() throws {
        let (worker, context, _) = try snapshotActive()
        try saveAutoState()
        let skipBoot = try builds.fetchBuild(id: context.buildID).map(skipsBootAnimation) ?? false
        try worker.perform { core in
            try core.reset()
            if skipBoot { _ = try (core as? any BootSkippingCapability)?.skipBootAnimation() }
        }
        lock.withLock { latestFrame = nil }
    }

    /// The periodic save queue calls this during play. Checkpoints have their own cadence and
    /// never enter the player's state list or Auto State retention.
    @discardableResult
    public func saveCrashRecoveryIfDue() throws -> Bool {
        let (worker, context, running) = try snapshotActive()
        guard running else { return false }
        let elapsed = lock.withLock { sessionEmulatedNanoseconds }
        guard elapsed &- lock.withLock({ lastCheckpointNanoseconds }) >= 60_000_000_000 else { return false }
        _ = try stateService.save(
            worker: worker, context: context, kind: .crashRecovery,
            playtimeSeconds: playtimeSeconds
        )
        lock.withLock { lastCheckpointNanoseconds = elapsed }
        return true
    }

    /// The state's thumbnail image, or nil when it has none.
    public func thumbnailData(for state: SaveState) -> Data? {
        stateService.thumbnailData(for: state)
    }

    /// Loads the state. Call it only when `loadingWouldRollBackSave` is false, with the frame loop
    /// stopped between the two, and use `loadStateKeepingCopy` otherwise.
    public func loadState(_ saveState: SaveState) throws {
        let (worker, context, _) = try snapshotActive()
        do {
            try load(saveState, worker: worker, context: context, restoringBattery: lock.withLock { lastWrittenBattery })
        } catch let failure as StateLoadFailure {
            throw failure.underlying
        }
    }

    /// Whether loading the state could take the game's save back to an older one. The state
    /// carries the cartridge RAM it was taken with, and the game's next save writes it over
    /// whatever was saved since: a battery save written after the state, or in-game saving not
    /// written yet, which is always newer than the state since taking one writes the save first.
    /// Stop the frame loop before asking, so the game can't save between this and the load.
    public func loadingWouldRollBackSave(_ saveState: SaveState) throws -> Bool {
        let (worker, _, _) = try snapshotActive()
        guard let profile = try profiles.fetchSaveProfile(id: saveState.saveProfileID) else {
            throw EmulationSessionError.saveProfileNotFound(saveState.saveProfileID)
        }
        return try saveState.createdAt < profile.modifiedAt || batteryIsDirty(worker: worker)
    }

    /// Writes the game's latest save, copies the profile to "<name> before loading state", then
    /// loads the state, and returns the copy. When the save or the copy can't be written, nothing
    /// is loaded. A load that fails puts the latest save back in the game, and removes the copy
    /// only once it has.
    @discardableResult
    public func loadStateKeepingCopy(_ saveState: SaveState) throws -> SaveProfile {
        let (worker, context, _) = try snapshotActive()
        let profile = try flushBattery()
        let latest = lock.withLock { lastWrittenBattery }
        let copy = try DuplicateSaveProfile(profiles: profiles, assets: assets, assetStore: assetStore, now: now)
            .execute(sourceProfileID: profile.id, name: "\(profile.displayName) before loading state")
        do {
            try load(saveState, worker: worker, context: context, restoringBattery: latest)
        } catch let failure as StateLoadFailure {
            if failure.batteryRestored { profiles.discardNewProfile(copy, assets: assets, files: assetStore) }
            throw failure.underlying
        }
        return copy
    }

    private struct StateLoadFailure: Error {
        let underlying: Error
        let batteryRestored: Bool
    }

    /// SameBoy writes a state's cartridge RAM into the game before it has read the whole state, so
    /// a state that fails partway can leave the game holding the state's older save. Put
    /// `battery` back then, so the next write doesn't take the save back.
    private func load(
        _ saveState: SaveState,
        worker: SessionWorker,
        context: LaunchContext,
        restoringBattery battery: Data
    ) throws {
        do {
            try stateService.load(saveState, worker: worker, context: context)
        } catch {
            var restored = battery.isEmpty
            if !restored {
                restored = (try? worker.perform { try $0.loadPersistentSave(battery) }) != nil
            }
            throw StateLoadFailure(underlying: error, batteryRestored: restored)
        }
    }

    /// App lifecycle entry point. Gameplay is paused before persistent state is captured.
    public func background() throws {
        try pause()
        let (_, context, _) = try snapshotActive()
        try SessionSaveError.attempting([
            { _ = try self.flushBattery() },
            { try self.recordPlaytime() },
            {
                _ = try self.saveAutoState()
                try self.launchHistory?.backgroundSaved(context)
            },
        ])
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

    /// Saves and ends the session. When a save step fails the session stays open and paused, so
    /// calling stop again retries.
    public func stop(createAutoState: Bool = false) throws {
        try stop(createAutoState: createAutoState, discardUnsaved: false)
    }

    /// `discardUnsaved` ends the session without saving anything, for closing after a failed stop.
    public func stop(createAutoState: Bool, discardUnsaved: Bool) throws {
        guard lock.withLock({ activeContext != nil && worker != nil }) else {
            lock.withLock { _state = .stopped }
            return
        }
        try pause()
        if !discardUnsaved {
            var steps: [() throws -> Void] = [
                { _ = try self.flushBattery() },
                { try self.recordPlaytime() },
            ]
            if createAutoState { steps.append { _ = try self.saveAutoState() } }
            try SessionSaveError.attempting(steps)
        }
        let (_, context, _) = try snapshotActive()
        try stateService.removeCrashRecoveryStates(context: context)
        try launchHistory?.closed()
        lock.withLock {
            worker = nil
            activeContext = nil
            imageLease?.end()
            imageLease = nil
            latestFrame = nil
            _state = .stopped
        }
    }

    /// Records the same played time for the Build and profile. The profile's modifiedAt marks
    /// battery writes and stays unchanged so Auto State eligibility is preserved.
    private func recordPlaytime() throws {
        try playtimeRecordingLock.withLock {
            let (_, context, _) = try snapshotActive()
            let (played, recorded, firstRecord) = lock.withLock {
                (sessionEmulatedNanoseconds, recordedNanoseconds, !sessionCounted)
            }
            let seconds = Double(played &- recorded) / 1_000_000_000
            try transactions.run { [builds, profiles, now] in
                guard var profile = try profiles.fetchSaveProfile(id: context.saveProfileID) else {
                    throw EmulationSessionError.saveProfileNotFound(context.saveProfileID)
                }
                try builds.addPlaytime(buildID: context.buildID, seconds: seconds)
                profile.totalPlaytimeSeconds += seconds
                if firstRecord { profile.sessionCount += 1 }
                profile.lastPlayedAt = now()
                try profiles.updateSaveProfile(profile)
            }
            lock.withLock {
                recordedNanoseconds = played
                sessionCounted = true
            }
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

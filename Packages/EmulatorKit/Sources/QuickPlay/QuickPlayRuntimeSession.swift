import EmulationCore
import EmulatorApplication
import EmulationSession
import EmulatorDomain
import Foundation
import GameIdentity

public enum QuickPlayRuntimeState: Equatable, Sendable {
    case idle
    case running(UUID)
    case paused(UUID)
    case stopped
}

public enum QuickPlayRuntimeError: Error, Equatable {
    case noCompatibleCore(GameSystem)
    case noActiveSession
    case sessionNotRunning
}

/// Runtime for a temporary Quick Play workspace.
///
/// It deliberately has no Game/Build/SaveProfile repositories. ROM, battery, and lifecycle state
/// remain inside the Quick Play directory until the user explicitly promotes the session.
public final class QuickPlayRuntimeSession: @unchecked Sendable {
    private let session: QuickPlaySession
    private let registry: CoreRegistry
    /// Quick Play has no Game or Build, so this comes from the App and System settings.
    private let buttonBounce: Bool
    private let audioFilter: AudioFilter
    /// The Super Game Boy borders setting for the system, which Automatic reads.
    private let superGameBoyBorders: Bool
    private let files: any AssetStore
    private let lock = NSLock()
    private var worker: SessionWorker?
    private var _state: QuickPlayRuntimeState = .idle
    private var latestFrame: EmulatorVideoFrame?
    private var _runningHardwareModel: HardwareModel?
    private var sessionNanoseconds: UInt64 = 0
    /// Real time played this session, which Fast Forward doesn't speed up.
    private var playtime: PlaytimeClock
    private let batteryCheckIntervalNanoseconds: UInt64
    private var lastBatteryCheckNanoseconds: UInt64 = 0
    private var lastWrittenBattery = Data()

    public init(
        session: QuickPlaySession,
        coreRegistry: CoreRegistry,
        assetStore: any AssetStore,
        buttonBounce: Bool = true,
        audioFilter: AudioFilter = .accurate,
        superGameBoyBorders: Bool = false,
        batteryCheckInterval: TimeInterval = 5,
        playtime: PlaytimeClock = PlaytimeClock()
    ) {
        self.session = session
        self.playtime = playtime
        self.buttonBounce = buttonBounce
        self.audioFilter = audioFilter
        self.superGameBoyBorders = superGameBoyBorders
        self.registry = coreRegistry
        self.files = assetStore
        self.batteryCheckIntervalNanoseconds = UInt64(batteryCheckInterval * 1_000_000_000)
    }

    public var state: QuickPlayRuntimeState { lock.withLock { _state } }
    public var currentFrame: EmulatorVideoFrame? { lock.withLock { latestFrame } }
    public var playtimeSeconds: Double { lock.withLock { Double(playtime.nanoseconds) / 1_000_000_000 } }

    /// The hardware the game runs on, or nil before it starts. Quick Play always runs on
    /// Automatic: a Game Boy Advance for a listed release with Game Boy Advance features
    /// (`GameBoyAdvanceFeatures`), otherwise the hardware the game's header suits, except that a
    /// resumed Auto State keeps the hardware it was made on, so a state from before Automatic read
    /// the header still loads.
    public var runningHardwareModel: HardwareModel? { lock.withLock { _runningHardwareModel } }

    /// True when the last start found an autosave the core rejected. The game booted normally and
    /// the rejected file was kept beside the session as `autosave.rejected.state`.
    public var autoStateRejected: Bool { lock.withLock { _autoStateRejected } }
    private var _autoStateRejected = false

    public func start(resumeAutoState: Bool = true) throws {
        let factory: any EmulatorCoreFactory
        do {
            factory = try registry.latestFactory(system: session.system)
        } catch {
            throw QuickPlayRuntimeError.noCompatibleCore(session.system)
        }
        let rom = try Data(contentsOf: session.imageURL, options: .mappedIfSafe)
        let battery = FileManager.default.fileExists(atPath: session.persistentSaveURL.path)
            ? try Data(contentsOf: session.persistentSaveURL, options: .mappedIfSafe)
            : nil

        // The save as the core reports it, so an unchanged save isn't mistaken for a new one.
        var savedBattery = Data()
        // Quick Play has no Build, so only the image itself can be a listed release.
        let automatic = GameBoyAdvanceFeatures.lists(sha1: SHA1Digest.data(rom))
            ? .gameBoyAdvance
            : HardwareModel.automatic.resolved(
                forImage: rom, system: session.system, superGameBoyBorders: superGameBoyBorders
            )

        func bootedWorker(madeOn state: Data? = nil) throws -> SessionWorker {
            let worker = SessionWorker(
                core: try factory.makeCore(),
                label: "QuickPlay.RuntimeSession.\(session.id.uuidString)"
            )
            try worker.perform { core in
                (core as? any ButtonBounceCapability)?.setButtonBounce(self.buttonBounce)
                (core as? any AudioFilterCapability)?.setAudioFilter(self.audioFilter)
                if let hardware = core as? any HardwareModelCapability {
                    try hardware.setHardwareModel(state.flatMap(hardware.hardwareModel(ofState:)) ?? automatic)
                }
                try core.loadImage(rom, system: self.session.system)
            }
            try worker.perform { try $0.loadPersistentSave(battery) }
            savedBattery = try worker.perform { try $0.persistentSaveData() }
            return worker
        }

        // Quick Play starts at the game, not the boot logo.
        func freshWorker() throws -> SessionWorker {
            let worker = try bootedWorker()
            try worker.perform { core in
                _ = try (core as? any BootSkippingCapability)?.skipBootAnimation()
            }
            return worker
        }

        let autoStateURL = session.autoStateURL
        var rejected = false
        let worker: SessionWorker
        if resumeAutoState, FileManager.default.fileExists(atPath: autoStateURL.path),
           !session.autoStateIsUnsafeToRestore(files: files) {
            let state = try? Data(contentsOf: autoStateURL, options: .mappedIfSafe)
            let candidate = try bootedWorker(madeOn: state)
            do {
                guard let state else { throw CocoaError(.fileReadUnknown) }
                try candidate.perform { try $0.deserializeState(state) }
                worker = candidate
            } catch {
                // Keep the rejected state for diagnosis, out of the way of the next resume.
                let rejectedURL = session.rootURL.appendingPathComponent("autosave.rejected.state")
                try? FileManager.default.removeItem(at: rejectedURL)
                try? FileManager.default.moveItem(at: autoStateURL, to: rejectedURL)
                worker = try freshWorker()
                rejected = true
            }
        } else {
            worker = try freshWorker()
        }

        let running = try worker.perform { ($0 as? any HardwareModelCapability)?.runningModel }
        lock.withLock {
            self.worker = worker
            latestFrame = nil
            _runningHardwareModel = running
            sessionNanoseconds = 0
            playtime.reset()
            lastBatteryCheckNanoseconds = 0
            lastWrittenBattery = savedBattery
            _autoStateRejected = rejected
            _state = .running(session.id)
        }
    }

    @discardableResult
    public func stepFrame(input: EmulatorInputState = .init()) throws -> EmulatorVideoFrame {
        let worker = try activeWorker(requireRunning: true)
        let frame = try worker.perform { try $0.runFrame(input: input) }
        lock.withLock {
            sessionNanoseconds &+= frame.emulatedNanoseconds
            playtime.ranFrame(lasting: frame.emulatedNanoseconds)
            latestFrame = frame
        }
        return frame
    }

    public func drainAudio(maxFrames: Int) throws -> [StereoSample] {
        let worker = try activeWorker(requireRunning: false)
        return try worker.perform { $0.drainAudio(maxFrames: maxFrames) }
    }

    public func setSpeed(_ speed: EmulationSpeed) throws {
        let worker = try activeWorker(requireRunning: false)
        try worker.perform { $0.setSpeed(speed) }
        lock.withLock { playtime.setSpeed(speed) }
    }

    /// Changes the audio filter on the running game. With none running there is nothing to change.
    public func setAudioFilter(_ filter: AudioFilter) throws {
        guard let worker = try? activeWorker(requireRunning: false) else { return }
        try worker.perform { core in
            (core as? any AudioFilterCapability)?.setAudioFilter(filter)
        }
    }

    /// Changes button bounce on the running game. With none running there is nothing to change.
    public func setButtonBounce(_ enabled: Bool) throws {
        guard let worker = try? activeWorker(requireRunning: false) else { return }
        try worker.perform { core in
            (core as? any ButtonBounceCapability)?.setButtonBounce(enabled)
        }
    }

    @discardableResult
    public func setDisplaySettings(
        colorCorrection: ColorCorrection,
        dmgPalette: DMGPalette,
        advanceColors: AdvanceColors
    ) throws -> EmulatorVideoFrame? {
        let worker = try activeWorker(requireRunning: false)
        let frame = try worker.perform { core in
            try (core as? any DisplaySettingsCapability)?.setDisplaySettings(
                colorCorrection: colorCorrection, dmgPalette: dmgPalette, advanceColors: advanceColors
            )
        }
        if let frame { lock.withLock { latestFrame = frame } }
        return frame
    }

    public var supportsPrinter: Bool {
        guard let worker = try? activeWorker(requireRunning: false) else { return false }
        return (try? worker.perform { $0 is any PrinterCapability }) ?? false
    }

    public func setPrinterConnected(_ connected: Bool) throws {
        let worker = try activeWorker(requireRunning: false)
        try worker.perform { ($0 as? any PrinterCapability)?.setPrinterConnected(connected) }
    }

    public func printerActivity() throws -> PrinterActivity {
        let worker = try activeWorker(requireRunning: false)
        return try worker.perform { ($0 as? any PrinterCapability)?.printerActivity ?? .idle }
    }

    public func drainPrinterEvents() throws -> [PrinterEvent] {
        let worker = try activeWorker(requireRunning: false)
        return try worker.perform { ($0 as? any PrinterCapability)?.drainPrinterEvents() ?? [] }
    }

    public func drainPrinterOutput() throws -> [PrinterOutput] {
        let worker = try activeWorker(requireRunning: false)
        return try worker.perform { try ($0 as? any PrinterCapability)?.drainPrinterOutput() ?? [] }
    }

    public var hasTiltSensor: Bool {
        guard let worker = try? activeWorker(requireRunning: false) else { return false }
        return (try? worker.perform { ($0 as? any TiltCapability)?.hasTiltSensor ?? false }) ?? false
    }

    public func setTilt(x: Double, y: Double) throws {
        let worker = try activeWorker(requireRunning: false)
        try worker.perform { ($0 as? any TiltCapability)?.setTilt(x: x, y: y) }
    }

    public var hasCamera: Bool {
        guard let worker = try? activeWorker(requireRunning: false) else { return false }
        return (try? worker.perform { ($0 as? any CameraCapability)?.hasCamera ?? false }) ?? false
    }

    public func setCameraFrame(_ frame: CameraFrame?) throws {
        let worker = try activeWorker(requireRunning: false)
        try worker.perform { ($0 as? any CameraCapability)?.setCameraFrame(frame) }
    }

    public func consumeRumbleAmplitude() throws -> Double {
        let worker = try activeWorker(requireRunning: false)
        return try worker.perform { core in
            (core as? any RumbleCapability)?.consumeRumbleAmplitude() ?? 0
        }
    }

    public func pause() throws {
        _ = try activeWorker(requireRunning: false)
        lock.withLock { _state = .paused(session.id) }
    }

    public func resume() throws {
        _ = try activeWorker(requireRunning: false)
        lock.withLock { _state = .running(session.id) }
    }

    /// Starts the game again from its boot. The cartridge keeps its battery-backed RAM through a
    /// reset, so the save stays. Stop the frame loop before calling this.
    public func restart() throws {
        let worker = try activeWorker(requireRunning: false)
        try worker.perform { core in
            try core.reset()
            _ = try (core as? any BootSkippingCapability)?.skipBootAnimation()
        }
        lock.withLock { latestFrame = nil }
    }

    public func flushBattery() throws {
        let worker = try activeWorker(requireRunning: false)
        let data = try worker.perform { try $0.persistentSaveData() }
        guard !data.isEmpty else { return }
        try files.writeDataAtomically(data, to: session.persistentSaveURL)
        lock.withLock { lastWrittenBattery = data }
    }

    /// Writes the game's battery save if it changed, checking at most once per check interval of
    /// play. Between checks it does nothing, so the frame loop can call it after every frame.
    /// Returns true when it wrote.
    @discardableResult
    public func flushBatteryIfChanged() throws -> Bool {
        let worker = try activeWorker(requireRunning: false)
        let due = lock.withLock { () -> Bool in
            guard sessionNanoseconds &- lastBatteryCheckNanoseconds >= batteryCheckIntervalNanoseconds else {
                return false
            }
            lastBatteryCheckNanoseconds = sessionNanoseconds
            return true
        }
        guard due else { return false }
        let written = lock.withLock { lastWrittenBattery }
        // A cartridge clock that only kept time isn't a save.
        let changed = try worker.perform { core in
            let data = try core.persistentSaveData()
            guard !data.isEmpty else { return false }
            return (core as? any PersistentSaveComparing)?.persistentSaveChanged(from: written, to: data) ?? (data != written)
        }
        guard changed else { return false }
        try flushBattery()
        return true
    }

    public func saveAutoState() throws {
        let worker = try activeWorker(requireRunning: false)
        let data = try worker.perform { try $0.serializeState() }
        let record = QuickPlayAutoStateRecord(
            core: try worker.perform { $0.descriptor },
            stateSerializationVersion: try worker.perform { $0.stateSerializationVersion },
            batterySHA256: session.batteryHash(files: files),
            playtimeSeconds: playtimeSeconds,
            stateSHA256: files.hashData(data)
        )
        let encoded = try JSONEncoder().encode(record)
        // The record goes first under its own name, so a state that lands without its record
        // written beside it is still matched to it when the app stops between the two writes.
        try files.writeDataAtomically(encoded, to: session.pendingAutoStateRecordURL)
        try files.writeDataAtomically(data, to: session.autoStateURL)
        try files.writeDataAtomically(encoded, to: session.autoStateRecordURL)
        try? files.removeIfExists(session.pendingAutoStateRecordURL)
    }

    public func background() throws {
        try pause()
        try SessionSaveError.attempting([flushBattery, saveAutoState])
    }

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
    public func stop(createAutoState: Bool = true) throws {
        try stop(createAutoState: createAutoState, discardUnsaved: false)
    }

    /// `discardUnsaved` ends the session without saving anything, for closing after a failed stop.
    public func stop(createAutoState: Bool, discardUnsaved: Bool) throws {
        guard lock.withLock({ worker != nil }) else {
            lock.withLock { _state = .stopped }
            return
        }
        try pause()
        if !discardUnsaved {
            try SessionSaveError.attempting(createAutoState ? [flushBattery, saveAutoState] : [flushBattery])
        }
        lock.withLock {
            worker = nil
            latestFrame = nil
            _state = .stopped
        }
    }

    private func activeWorker(requireRunning: Bool) throws -> SessionWorker {
        try lock.withLock {
            guard let worker else { throw QuickPlayRuntimeError.noActiveSession }
            if requireRunning, case .running = _state {
                return worker
            }
            if requireRunning { throw QuickPlayRuntimeError.sessionNotRunning }
            return worker
        }
    }
}

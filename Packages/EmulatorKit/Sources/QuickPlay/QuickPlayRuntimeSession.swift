import EmulationCore
import EmulatorApplication
import EmulationSession
import EmulatorDomain
import Foundation

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
    private let files: any AssetStore
    private let lock = NSLock()
    private var worker: SessionWorker?
    private var _state: QuickPlayRuntimeState = .idle
    private var latestFrame: EmulatorVideoFrame?
    private var sessionNanoseconds: UInt64 = 0
    private let batteryCheckIntervalNanoseconds: UInt64
    private var lastBatteryCheckNanoseconds: UInt64 = 0
    private var lastWrittenBattery = Data()

    public init(
        session: QuickPlaySession,
        coreRegistry: CoreRegistry,
        assetStore: any AssetStore,
        batteryCheckInterval: TimeInterval = 5
    ) {
        self.session = session
        self.registry = coreRegistry
        self.files = assetStore
        self.batteryCheckIntervalNanoseconds = UInt64(batteryCheckInterval * 1_000_000_000)
    }

    public var state: QuickPlayRuntimeState { lock.withLock { _state } }
    public var currentFrame: EmulatorVideoFrame? { lock.withLock { latestFrame } }
    public var playtimeSeconds: Double { lock.withLock { Double(sessionNanoseconds) / 1_000_000_000 } }

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

        func bootedWorker() throws -> SessionWorker {
            let worker = SessionWorker(
                core: try factory.makeCore(),
                label: "QuickPlay.RuntimeSession.\(session.id.uuidString)"
            )
            try worker.perform { try $0.loadImage(rom, system: self.session.system) }
            try worker.perform { try $0.loadPersistentSave(battery) }
            savedBattery = try worker.perform { try $0.persistentSaveData() }
            return worker
        }

        // Quick Play starts at the game, not the boot logo (docs/decisions.md).
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
           !session.batteryIsNewerThanAutoState(files: files) {
            let candidate = try bootedWorker()
            do {
                let state = try Data(contentsOf: autoStateURL, options: .mappedIfSafe)
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

        lock.withLock {
            self.worker = worker
            latestFrame = nil
            sessionNanoseconds = 0
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
    }

    @discardableResult
    public func setDisplaySettings(colorCorrection: ColorCorrection, dmgPalette: DMGPalette) throws -> EmulatorVideoFrame? {
        let worker = try activeWorker(requireRunning: false)
        let frame = try worker.perform { core in
            try (core as? any DisplaySettingsCapability)?.setDisplaySettings(colorCorrection: colorCorrection, dmgPalette: dmgPalette)
        }
        if let frame { lock.withLock { latestFrame = frame } }
        return frame
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
        let data = try worker.perform { try $0.persistentSaveData() }
        guard !data.isEmpty, data != lock.withLock({ lastWrittenBattery }) else { return false }
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
            playtimeSeconds: playtimeSeconds
        )
        try files.writeDataAtomically(data, to: session.autoStateURL)
        try files.writeDataAtomically(try JSONEncoder().encode(record), to: session.autoStateRecordURL)
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

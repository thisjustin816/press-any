import EmulationCore
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
    private let lock = NSLock()
    private var worker: SessionWorker?
    private var _state: QuickPlayRuntimeState = .idle
    private var latestFrame: EmulatorVideoFrame?
    private var sessionNanoseconds: UInt64 = 0

    public init(session: QuickPlaySession, coreRegistry: CoreRegistry) {
        self.session = session
        self.registry = coreRegistry
    }

    public var state: QuickPlayRuntimeState { lock.withLock { _state } }
    public var currentFrame: EmulatorVideoFrame? { lock.withLock { latestFrame } }
    public var playtimeSeconds: Double { lock.withLock { Double(sessionNanoseconds) / 1_000_000_000 } }

    public func start(resumeAutoState: Bool = true) throws {
        let factory: any EmulatorCoreFactory
        do {
            factory = try registry.latestFactory(system: session.system)
        } catch {
            throw QuickPlayRuntimeError.noCompatibleCore(session.system)
        }
        let core = try factory.makeCore()
        let worker = SessionWorker(core: core, label: "QuickPlay.RuntimeSession.\(session.id.uuidString)")
        let rom = try Data(contentsOf: session.imageURL, options: .mappedIfSafe)
        try worker.perform { try $0.loadImage(rom, system: self.session.system) }

        if FileManager.default.fileExists(atPath: session.persistentSaveURL.path) {
            let battery = try Data(contentsOf: session.persistentSaveURL, options: .mappedIfSafe)
            try worker.perform { try $0.loadPersistentSave(battery) }
        } else {
            try worker.perform { try $0.loadPersistentSave(nil) }
        }

        let autoStateURL = session.rootURL.appendingPathComponent("autosave.state")
        if resumeAutoState, FileManager.default.fileExists(atPath: autoStateURL.path) {
            let state = try Data(contentsOf: autoStateURL, options: .mappedIfSafe)
            try worker.perform { try $0.deserializeState(state) }
        } else {
            // Quick Play starts at the game, not the boot logo (docs/decisions.md).
            try worker.perform { core in
                _ = try (core as? any BootSkippingCapability)?.skipBootAnimation()
            }
        }

        lock.withLock {
            self.worker = worker
            latestFrame = nil
            sessionNanoseconds = 0
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
        try atomicWrite(data, to: session.persistentSaveURL)
    }

    public func saveAutoState() throws {
        let worker = try activeWorker(requireRunning: false)
        let data = try worker.perform { try $0.serializeState() }
        try atomicWrite(data, to: session.rootURL.appendingPathComponent("autosave.state"))
    }

    public func background() throws {
        try pause()
        try flushBattery()
        try saveAutoState()
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

    public func stop(createAutoState: Bool = true) throws {
        guard lock.withLock({ worker != nil }) else {
            lock.withLock { _state = .stopped }
            return
        }
        try pause()
        try flushBattery()
        if createAutoState { try saveAutoState() }
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

    private func atomicWrite(_ data: Data, to destination: URL) throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination, options: .atomic)
    }
}

import EmulationCore
import EmulatorDomain
import Foundation

enum GameplayCameraPosition: CaseIterable, Sendable {
    case rear, front
}

extension GameBoyCamera {
    /// Nil for Off.
    var position: GameplayCameraPosition? {
        switch self {
        case .rear: .rear
        case .front: .front
        case .off: nil
        }
    }

    var menuTitle: String {
        switch self {
        case .rear: "Rear Camera"
        case .front: "Front Camera"
        case .off: "Off"
        }
    }
}

@MainActor
protocol GameplayCameraSource: AnyObject {
    func requestAccess() async -> Bool
    func start(
        position: GameplayCameraPosition, rotationAngle: Double,
        receive: @escaping @Sendable (CameraFrame) -> Void,
        failure: @escaping @Sendable () -> Void
    )
    func stop()
}

/// Retains only the newest frame. A stopped or replaced capture cannot refill it.
final class CameraFrameBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = UUID()
    private var frame: CameraFrame?

    func begin() -> UUID {
        lock.withLock {
            generation = UUID()
            frame = nil
            return generation
        }
    }

    func store(_ frame: CameraFrame, generation: UUID) {
        lock.withLock {
            if self.generation == generation { self.frame = frame }
        }
    }

    var current: CameraFrame? { lock.withLock { frame } }

    func clear() { _ = begin() }
}

/// Owns the player's choice separately from capture, which runs only during active gameplay.
@MainActor
final class GameplayCamera {
    let frames = CameraFrameBuffer()
    private let source: any GameplayCameraSource
    private var request = UUID()
    private var running = false
    private var capturing = false
    private var rotationAngle = 90.0
    private(set) var position: GameplayCameraPosition?
    var onError: ((String) -> Void)?

    init(source: any GameplayCameraSource) { self.source = source }

    @discardableResult
    func select(_ position: GameplayCameraPosition?) -> Task<Void, Never>? {
        request = UUID()
        let pending = request
        self.position = nil
        stopCapture()
        guard let position else { return nil }
        return Task { [weak self] in
            guard let self else { return }
            let allowed = await source.requestAccess()
            guard request == pending else { return }
            guard allowed else {
                onError?("Camera access is off for \(AppBrand.displayName). Allow it in iPhone Settings, or set Game Boy Camera to Off.")
                return
            }
            self.position = position
            updateCapture()
        }
    }

    func setRunning(_ running: Bool, rotationAngle: Double) {
        if self.rotationAngle != rotationAngle { stopCapture() }
        self.rotationAngle = rotationAngle
        self.running = running
        updateCapture()
    }

    func close() {
        request = UUID()
        position = nil
        running = false
        stopCapture()
    }

    private func updateCapture() {
        guard running, let position else {
            stopCapture()
            return
        }
        guard !capturing else { return }
        capturing = true
        let generation = frames.begin()
        let pending = request
        source.start(position: position, rotationAngle: rotationAngle, receive: { [frames] frame in
            frames.store(frame, generation: generation)
        }, failure: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.request == pending, self.capturing,
                      self.frames.isCurrent(generation) else { return }
                self.select(nil)
                self.onError?("The camera is unavailable. Choose it again under Game Boy Camera in the game menu to try again.")
            }
        })
    }

    private func stopCapture() {
        frames.clear()
        if capturing { source.stop() }
        capturing = false
    }
}

private extension CameraFrameBuffer {
    func isCurrent(_ generation: UUID) -> Bool {
        lock.withLock { self.generation == generation }
    }
}

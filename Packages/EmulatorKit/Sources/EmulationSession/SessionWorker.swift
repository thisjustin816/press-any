import Dispatch
import EmulationCore

/// Serializes every mutating call into an emulator core.
///
/// Emulator cores are intentionally not `Sendable`: they are mutable C-backed state
/// machines. `CoreBox` is therefore confined to this queue and marked unchecked only
/// at the box boundary. Callers never receive the core instance itself.
public final class SessionWorker: @unchecked Sendable {
    private final class CoreBox: @unchecked Sendable {
        let core: any EmulatorCore
        init(core: any EmulatorCore) { self.core = core }
    }

    private let queue: DispatchQueue
    private let box: CoreBox

    public init(core: any EmulatorCore, label: String = "EmulationSession.SessionWorker") {
        self.box = CoreBox(core: core)
        self.queue = DispatchQueue(label: label, qos: .userInteractive)
    }

    public func perform<T>(_ operation: @escaping @Sendable (any EmulatorCore) throws -> T) throws -> T {
        try queue.sync {
            try operation(box.core)
        }
    }
}

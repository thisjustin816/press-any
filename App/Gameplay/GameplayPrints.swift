import EmulationCore
import Foundation

/// Where a game's prints are kept as paper comes out: the Game's Captures in library play, the
/// session's folder in Quick Play. Saving runs on its own queue, in order, so the frame loop never
/// waits on a file or the database.
final class GameplayPrints: @unchecked Sendable {
    /// The library Game whose Captures the Prints sheet links to. Nil in Quick Play.
    let gameID: UUID?
    private let save: @Sendable (PrinterSlip) throws -> Void
    private let remove: @Sendable (UUID) throws -> Void
    private let queue = DispatchQueue(label: "Gameplay.Prints", qos: .utility)
    private let lock = NSLock()
    private var reportedFailure = false
    /// Read and written on the queue only.
    private var discarded: Set<UUID> = []

    init(
        gameID: UUID?,
        save: @escaping @Sendable (PrinterSlip) throws -> Void,
        discard: @escaping @Sendable (UUID) throws -> Void = { _ in }
    ) {
        self.gameID = gameID
        self.save = save
        self.remove = discard
    }

    /// Saves each slip. The first failure in a session is reported; later ones aren't repeated.
    func keep(_ slips: [PrinterSlip], onFailure: @escaping @Sendable () -> Void) {
        guard !slips.isEmpty else { return }
        queue.async { [self] in
            for slip in slips where !discarded.contains(slip.id) {
                do { try save(slip) } catch {
                    let first = lock.withLock { () -> Bool in
                        defer { reportedFailure = true }
                        return !reportedFailure
                    }
                    if first { onFailure() }
                }
            }
        }
    }

    /// Removes a print after the saves already handed over, and saves none of it after.
    func discard(_ id: UUID, onFailure: @escaping @Sendable () -> Void) {
        queue.async { [self] in
            discarded.insert(id)
            do { try remove(id) } catch { onFailure() }
        }
    }

    /// Returns once every print handed over so far is saved.
    func finish() { queue.sync {} }
}

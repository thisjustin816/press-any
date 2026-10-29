import EmulationCore
import Foundation

/// Frames deliver output off the main thread; reset and preview actions read the same feed.
final class GameplayPrinterFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var feed = PrinterFeed()

    var slips: [PrinterSlip] { lock.withLock { feed.slips } }

    func receive(_ outputs: [PrinterOutput]) throws {
        try lock.withLock {
            var firstError: Error?
            for output in outputs {
                do { try feed.receive(output) }
                catch {
                    feed.endRoll()
                    if firstError == nil { firstError = error }
                }
            }
            if let firstError { throw firstError }
        }
    }

    func endRoll() { lock.withLock { feed.endRoll() } }

    func discard(id: UUID) { lock.withLock { feed.discard(id: id) } }

    /// The slips in `after` that are new or gained paper since `before`.
    static func changes(from before: [PrinterSlip], to after: [PrinterSlip]) -> [PrinterSlip] {
        let counts = Dictionary(before.map { ($0.id, $0.sections.count) }, uniquingKeysWith: { first, _ in first })
        return after.filter { counts[$0.id] != $0.sections.count }
    }
}

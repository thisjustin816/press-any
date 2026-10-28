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
}

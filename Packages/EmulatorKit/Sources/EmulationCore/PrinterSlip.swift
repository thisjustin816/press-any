import Foundation

public struct PrinterSlip: Identifiable, Equatable, Sendable {
    public let id: UUID
    public private(set) var sections: [PrinterOutput]
    public static let maximumFeedHeight = 2048

    public enum ValidationError: Error { case paperTooLong, noPaper }

    public init(output: PrinterOutput, id: UUID = UUID()) {
        self.id = id
        sections = [output]
    }

    /// A slip read back from storage, held to the same limits as one the printer fed.
    public init(id: UUID, sections: [PrinterOutput]) throws {
        guard let first = sections.first else { throw ValidationError.noPaper }
        var slip = PrinterSlip(output: first, id: id)
        for section in sections.dropFirst() { try slip.append(section) }
        self = slip
    }

    public var feedHeight: Int {
        sections.reduce(0) { $0 + $1.height + ($1.topMargin + $1.bottomMargin) * 8 }
    }

    public var acceptsContinuation: Bool { sections.last?.bottomMargin == 0 }

    public mutating func append(_ output: PrinterOutput) throws {
        let additional = output.height + (output.topMargin + output.bottomMargin) * 8
        guard feedHeight + additional <= Self.maximumFeedHeight else { throw ValidationError.paperTooLong }
        sections.append(output)
    }
}

/// Keeps a bounded session feed. A zero bottom margin leaves the paper attached for another command.
public struct PrinterFeed: Sendable {
    public private(set) var slips: [PrinterSlip] = []
    public static let retention = 10

    public init() {}

    public mutating func receive(_ output: PrinterOutput) throws {
        if !startsNewRoll, let last = slips.last, last.acceptsContinuation, output.topMargin == 0 {
            try slips[slips.count - 1].append(output)
        } else {
            slips.append(PrinterSlip(output: output))
            if slips.count > Self.retention { slips.removeFirst() }
        }
        startsNewRoll = false
    }

    /// Takes a slip out of the feed. Discarding the newest one ends its roll, so paper the game
    /// feeds next starts a new slip instead of joining the one before it.
    public mutating func discard(id: UUID) {
        guard let index = slips.firstIndex(where: { $0.id == id }) else { return }
        if index == slips.count - 1 { startsNewRoll = true }
        slips.remove(at: index)
    }

    /// Stops a later command from joining paper captured before a reset or disconnection.
    public mutating func endRoll() { startsNewRoll = true }
    private var startsNewRoll = false
}

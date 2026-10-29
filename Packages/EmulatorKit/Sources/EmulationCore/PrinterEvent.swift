import Foundation

/// What the printer made of the game's traffic, for a log a game's developer can read: each packet
/// with the status the game read back, and packets the printer dropped.
public struct PrinterEvent: Equatable, Sendable {
    public enum Kind: UInt8, Sendable {
        /// A packet ended. A status poll is reported only when its answer changes.
        case packet = 0
        /// Bytes came too far apart, so the packet in progress was dropped.
        case timeout = 1
        /// The printer sat idle long enough to clear data it held but hadn't printed.
        case idleReset = 2
        /// A packet didn't begin with 0x88; the printer answers 0xFF until the line goes quiet.
        case syncLost = 3
    }

    /// Seconds on the printer's own clock since it was connected.
    public let time: Double
    public let kind: Kind
    public let command: UInt8
    public let compressed: Bool
    public let length: Int
    /// The status byte the game read back.
    public let status: UInt8
    public let checksumMatched: Bool
    /// Data sent while printing, which the printer drops without flagging an error.
    public let ignoredWhilePrinting: Bool

    public init(time: Double, kind: Kind, command: UInt8, compressed: Bool, length: Int, status: UInt8,
                checksumMatched: Bool = true, ignoredWhilePrinting: Bool = false) {
        self.time = time
        self.kind = kind
        self.command = command
        self.compressed = compressed
        self.length = length
        self.status = status
        self.checksumMatched = checksumMatched
        self.ignoredWhilePrinting = ignoredWhilePrinting
    }

    /// The status bits as the printer's documentation names them, lowest first.
    public static let statusFlags: [(bit: UInt8, name: String)] = [
        (0x01, "checksum error"), (0x02, "busy"), (0x04, "image full"), (0x08, "unprocessed data"),
        (0x10, "packet error"), (0x20, "paper jam"), (0x40, "other error"), (0x80, "low battery"),
    ]
    /// Bits that mean something went wrong, rather than the printer just working.
    public static let errorBits: UInt8 = 0x01 | 0x10 | 0x20 | 0x40 | 0x80

    public var commandName: String {
        switch command {
        case 0x01: "Init"
        case 0x02: "Print"
        case 0x04: "Data"
        case 0x08: "Break"
        case 0x0F: "Status"
        default: String(format: "Command 0x%02X", command)
        }
    }

    public var statusText: String {
        let names = Self.statusFlags.filter { status & $0.bit != 0 }.map(\.name)
        let hex = String(format: "0x%02X", status)
        return names.isEmpty ? "\(hex) ready" : "\(hex) \(names.joined(separator: ", "))"
    }

    /// What went wrong, in a sentence, or nil when the printer took the packet as sent.
    public var problem: String? {
        switch kind {
        case .timeout:
            return "\(command == 0 ? "A packet" : "A \(commandName) packet") was dropped: its bytes came more than 5 ms apart."
        case .idleReset:
            return "The printer sat idle for 125 ms and cleared data it hadn’t printed."
        case .syncLost:
            return String(format: "A packet began with 0x%02X instead of 0x88; the printer answers 0xFF until the line goes quiet.", command)
        case .packet:
            if ignoredWhilePrinting { return "Data sent while printing was ignored." }
            if !checksumMatched { return "The \(commandName) packet’s checksum didn’t match." }
            if status & 0x10 != 0 { return "The printer refused the \(commandName) packet (packet error)." }
            if status & Self.errorBits != 0 { return "The printer reported \(statusText)." }
            return nil
        }
    }

    /// One line for the log: the packet, its size and the status read back.
    public var summary: String {
        switch kind {
        case .packet:
            var parts = [commandName]
            if length > 0 { parts.append("\(length) bytes\(compressed ? ", compressed" : "")") }
            return "\(parts.joined(separator: ", ")) → \(statusText)"
        case .timeout: return "Timeout"
        case .idleReset: return "Idle reset"
        case .syncLost: return "Lost sync"
        }
    }
}

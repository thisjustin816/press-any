import Foundation

/// The clock SameBoy writes after an MBC3 cartridge's RAM in a battery save, in the 48-byte layout
/// BGB and VBA share: the running clock's seconds, minutes, hours, days and high byte, each in the
/// first byte of four; the latched copy the same way; then the host time in seconds, 64-bit little
/// endian. SameBoy writes the current host time and clock on every read, so two reads of a save the
/// game never touched still differ here.
struct MBC3ClockTrailer: Equatable {
    static let byteCount = 48

    let seconds: Int
    let minutes: Int
    let hours: Int
    /// 0...511: the day counter's low byte and bit 0 of the high byte.
    let days: Int
    let halted: Bool
    /// The day counter overflowed.
    let carry: Bool
    let hostTime: UInt64

    /// The trailer at the end of `save`, or nil when it's too short to hold one.
    init?(endOf save: Data) {
        guard save.count >= Self.byteCount else { return nil }
        let bytes = [UInt8](save.suffix(Self.byteCount))
        seconds = Int(bytes[0])
        minutes = Int(bytes[4])
        hours = Int(bytes[8])
        let high = bytes[16]
        days = Int(bytes[12]) | Int(high & 1) << 8
        halted = high & 0x40 != 0
        carry = high & 0x80 != 0
        hostTime = (0..<8).reduce(UInt64(0)) { $0 | UInt64(bytes[40 + $1]) << (8 * $1) }
    }

    /// Seconds since day 0, or nil when a register holds a value the clock never counts to.
    private var elapsed: Int? {
        guard seconds < 60, minutes < 60, hours < 24 else { return nil }
        return ((days * 24 + hours) * 60 + minutes) * 60 + seconds
    }

    /// Whether `later` is this clock read again with nothing but time passing: unchanged while
    /// halted, otherwise moved on by the host time between the reads. Each read takes the clock
    /// as of its last sync, up to a second behind the host time it records, so one second either
    /// way still counts as the same clock.
    func onlyAged(into later: Self) -> Bool {
        guard halted == later.halted, carry == later.carry else { return false }
        if halted {
            return seconds == later.seconds && minutes == later.minutes && hours == later.hours && days == later.days
        }
        guard later.hostTime >= hostTime, let before = elapsed, let after = later.elapsed else { return false }
        let expected = before + Int(later.hostTime - hostTime)
        return abs(after - expected) <= 1
    }
}

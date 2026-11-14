import Foundation
@testable import SameBoyAdapter
import Testing

@Suite("MBC3 clock trailer")
struct MBC3ClockTrailerTests {
    private func save(ram: UInt8 = 0, seconds: UInt8, minutes: UInt8 = 0, hours: UInt8 = 0, days: UInt8 = 0,
                      high: UInt8 = 0, hostTime: UInt64, latchedSeconds: UInt8 = 0) -> Data {
        var trailer = [UInt8](repeating: 0, count: MBC3ClockTrailer.byteCount)
        trailer[0] = seconds; trailer[4] = minutes; trailer[8] = hours; trailer[12] = days; trailer[16] = high
        trailer[20] = latchedSeconds
        for byte in 0..<8 { trailer[40 + byte] = UInt8(truncatingIfNeeded: hostTime >> (8 * byte)) }
        return Data(repeating: ram, count: 8192) + Data(trailer)
    }

    @Test("reads the clock and host time")
    func reads() throws {
        let trailer = try #require(MBC3ClockTrailer(endOf: save(seconds: 5, minutes: 6, hours: 7, days: 8, high: 0xc1,
                                                               hostTime: 1_800_000_000)))
        #expect(trailer.seconds == 5 && trailer.minutes == 6 && trailer.hours == 7)
        #expect(trailer.days == 264 && trailer.halted && trailer.carry)
        #expect(trailer.hostTime == 1_800_000_000)
        #expect(MBC3ClockTrailer(endOf: Data(count: 47)) == nil)
    }

    @Test("a running clock that only moved with the host time is the same clock")
    func aged() throws {
        let before = try #require(MBC3ClockTrailer(endOf: save(seconds: 58, minutes: 59, hours: 23, days: 2, hostTime: 1000)))
        // Three seconds later: across a day.
        let later = try #require(MBC3ClockTrailer(endOf: save(seconds: 1, hours: 0, days: 3, hostTime: 1003)))
        #expect(before.onlyAged(into: later))
        let lagging = try #require(MBC3ClockTrailer(endOf: save(seconds: 0, hours: 0, days: 3, hostTime: 1003)))
        #expect(before.onlyAged(into: lagging), "a second behind its host time is a read that hadn't synced")
        let latched = try #require(MBC3ClockTrailer(endOf: save(seconds: 1, hours: 0, days: 3, hostTime: 1003, latchedSeconds: 40)))
        #expect(before.onlyAged(into: latched), "latching changes nothing the game keeps")
    }

    @Test("a clock the game set, halted or started is a change")
    func changed() throws {
        let before = try #require(MBC3ClockTrailer(endOf: save(seconds: 10, hostTime: 1000)))
        let set = try #require(MBC3ClockTrailer(endOf: save(seconds: 10, minutes: 30, hostTime: 1002)))
        #expect(!before.onlyAged(into: set))
        let halted = try #require(MBC3ClockTrailer(endOf: save(seconds: 12, high: 0x40, hostTime: 1002)))
        #expect(!before.onlyAged(into: halted))
        let backwards = try #require(MBC3ClockTrailer(endOf: save(seconds: 10, hostTime: 990)))
        #expect(!before.onlyAged(into: backwards), "a host clock that went back can't be told apart")
        let invalid = try #require(MBC3ClockTrailer(endOf: save(seconds: 62, hostTime: 1052)))
        #expect(!before.onlyAged(into: invalid))
    }

    @Test("a halted clock is the same clock only while it reads the same")
    func halted() throws {
        let before = try #require(MBC3ClockTrailer(endOf: save(seconds: 10, high: 0x40, hostTime: 1000)))
        let later = try #require(MBC3ClockTrailer(endOf: save(seconds: 10, high: 0x40, hostTime: 5000)))
        #expect(before.onlyAged(into: later))
        let moved = try #require(MBC3ClockTrailer(endOf: save(seconds: 11, high: 0x40, hostTime: 5000)))
        #expect(!before.onlyAged(into: moved))
    }
}

import Foundation

/// Synthetic Game Boy images for tests. No commercial ROM is ever needed.
public enum TestROM {
    /// Valid header and global checksums with a looping entry point (`jr @`). Chosen 16 KiB
    /// banks supply the image contents; without them, a 32 KiB image uses `payloadByte`. A
    /// `program` runs from 0x150 instead, after the entry point jumps there.
    public static func make(title: String, cgb: Bool = false, payloadByte: UInt8 = 0,
                            banks: [Data]? = nil, cartridgeType: UInt8 = 0,
                            ramSizeCode: UInt8 = 0, cgbFlag: UInt8? = nil, program: [UInt8] = []) -> Data {
        if let banks { precondition(banks.count >= 2 && banks.allSatisfy { $0.count == 0x4000 }) }
        var rom = banks.map { $0.reduce(into: Data()) { $0.append($1) } }
            ?? Data(repeating: payloadByte, count: 0x8000)
        for address in 0x100..<0x150 { rom[address] = 0 }
        if program.isEmpty {
            rom[0x100] = 0x18 // jr @
            rom[0x101] = 0xfe
        } else {
            rom.replaceSubrange(0x100..<0x103, with: [0xc3, 0x50, 0x01]) // jp $0150
            rom.replaceSubrange(0x150..<0x150 + program.count, with: program)
        }
        for (offset, byte) in title.utf8.prefix(15).enumerated() { rom[0x134 + offset] = byte }
        rom[0x143] = cgbFlag ?? (cgb ? 0x80 : 0x00)
        rom[0x147] = cartridgeType
        rom[0x148] = UInt8(max(0, Int(log2(Double(rom.count / 0x4000))) - 1))
        rom[0x149] = ramSizeCode

        var headerChecksum: UInt8 = 0
        for address in 0x134...0x14c { headerChecksum = headerChecksum &- rom[address] &- 1 }
        rom[0x14d] = headerChecksum

        var globalChecksum: UInt16 = 0
        for address in rom.indices where address != 0x14e && address != 0x14f {
            globalChecksum &+= UInt16(rom[address])
        }
        rom[0x14e] = UInt8(globalChecksum >> 8)
        rom[0x14f] = UInt8(globalChecksum & 0xff)
        return rom
    }
}

import Foundation

/// Synthetic Game Boy images for tests. No commercial ROM is ever needed.
public enum TestROM {
    /// A 32 KiB image with valid header and global checksums. Its entry point loops forever
    /// (`jr @`), so a core can run it indefinitely, and the rest is filled with `payloadByte`, which
    /// gives images with different content different hashes.
    public static func make(title: String, cgb: Bool = false, payloadByte: UInt8 = 0) -> Data {
        var rom = Data(repeating: payloadByte, count: 0x8000)
        for address in 0x100..<0x150 { rom[address] = 0 }
        rom[0x100] = 0x18 // jr @
        rom[0x101] = 0xfe
        for (offset, byte) in title.utf8.prefix(15).enumerated() { rom[0x134 + offset] = byte }
        rom[0x143] = cgb ? 0x80 : 0x00

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

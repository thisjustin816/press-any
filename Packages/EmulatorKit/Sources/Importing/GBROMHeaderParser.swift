import EmulatorDomain
import Foundation

public enum GBROMHeaderParser {
    public static func parse(_ rom: Data) throws -> GBROMHeader {
        guard rom.count > 0x14f else {
            throw GBROMHeaderError.fileTooSmall(actual: rom.count)
        }

        let titleBytes = rom[0x134...0x142]
        let title = String(bytes: titleBytes.prefix { $0 != 0 }, encoding: .ascii)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cgbFlag = rom[0x143]
        let system: GameSystem = (cgbFlag == 0x80 || cgbFlag == 0xc0) ? .gameBoyColor : .gameBoy

        var computedHeaderChecksum: UInt8 = 0
        for address in 0x134...0x14c {
            computedHeaderChecksum = computedHeaderChecksum &- rom[address] &- 1
        }
        let storedHeaderChecksum = rom[0x14d]

        let storedGlobalChecksum = UInt16(rom[0x14e]) << 8 | UInt16(rom[0x14f])
        let computedGlobalChecksum = globalChecksum(of: rom)

        return GBROMHeader(
            title: title,
            system: system,
            cgbFlag: cgbFlag,
            cartridgeType: rom[0x147],
            romSizeCode: rom[0x148],
            ramSizeCode: rom[0x149],
            headerChecksum: storedHeaderChecksum,
            headerChecksumValid: storedHeaderChecksum == computedHeaderChecksum,
            globalChecksum: storedGlobalChecksum,
            globalChecksumValid: storedGlobalChecksum == computedGlobalChecksum
        )
    }

    /// Sums every byte except the stored checksum itself. Quick Play parses the header on its
    /// launch path, so this walks raw bytes instead of indexing Data one byte at a time.
    private static func globalChecksum(of rom: Data) -> UInt16 {
        rom.withUnsafeBytes { bytes in
            var sum: UInt = 0
            for byte in bytes {
                sum &+= UInt(byte)
            }
            let stored = UInt(bytes[0x14e]) + UInt(bytes[0x14f])
            return UInt16(truncatingIfNeeded: sum &- stored)
        }
    }
}

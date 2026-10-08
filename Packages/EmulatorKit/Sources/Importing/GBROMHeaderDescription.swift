import Foundation

/// How a header's CGB flag (0x143) declares Game Boy Color support.
public enum GBColorSupport: Equatable, Sendable {
    case gameBoy
    case colorCompatible
    case colorOnly

    public var displayName: String {
        switch self {
        case .gameBoy: "Game Boy"
        case .colorCompatible: "Game Boy Color compatible"
        case .colorOnly: "Game Boy Color only"
        }
    }
}

/// Names for header codes, so Technical Info reads "MBC5 + RAM + Battery" rather than 0x1B.
extension GBROMHeader {
    /// Only 0x80 and 0xC0 declare color support; any other value is a plain Game Boy image, which
    /// is how `GBROMHeaderParser` assigns `system` too.
    public var colorSupport: GBColorSupport {
        switch cgbFlag {
        case 0xc0: .colorOnly
        case 0x80: .colorCompatible
        default: .gameBoy
        }
    }

    public var cartridgeTypeName: String { Self.cartridgeTypeName(for: cartridgeType) }

    /// The size the header declares, which can differ from the file's length. Nil for a code
    /// the hardware tables don't define.
    public var romSizeBytes: Int? {
        switch romSizeCode {
        case 0x00...0x08: 0x8000 << Int(romSizeCode)
        case 0x52: 72 * 0x4000
        case 0x53: 80 * 0x4000
        case 0x54: 96 * 0x4000
        default: nil
        }
    }

    /// Nil for a code the hardware tables don't define.
    public var ramSizeBytes: Int? {
        switch ramSizeCode {
        case 0x00: 0
        case 0x01: 0x800
        case 0x02: 0x2000
        case 0x03: 0x8000
        case 0x04: 0x20000
        case 0x05: 0x10000
        default: nil
        }
    }

    public var romSizeDescription: String {
        romSizeBytes.map(Self.sizeDescription) ?? String(format: "Unknown (0x%02X)", romSizeCode)
    }

    public var ramSizeDescription: String {
        guard let bytes = ramSizeBytes else { return String(format: "Unknown (0x%02X)", ramSizeCode) }
        return bytes == 0 ? "None" : Self.sizeDescription(bytes)
    }

    public static func cartridgeTypeName(for code: UInt8) -> String {
        cartridgeTypeNames[code] ?? String(format: "Unknown (0x%02X)", code)
    }

    /// "32 KB", "1 MB", "1.1 MB": binary units, as cartridge sizes are always quoted.
    static func sizeDescription(_ bytes: Int) -> String {
        if bytes >= 0x100000 {
            let megabytes = Double(bytes) / Double(0x100000)
            return megabytes == megabytes.rounded() ? "\(Int(megabytes)) MB" : String(format: "%.1f MB", megabytes)
        }
        if bytes >= 0x400 {
            let kilobytes = Double(bytes) / 1024
            return kilobytes == kilobytes.rounded() ? "\(Int(kilobytes)) KB" : String(format: "%.1f KB", kilobytes)
        }
        return "\(bytes) bytes"
    }

    private static let cartridgeTypeNames: [UInt8: String] = [
        0x00: "ROM Only",
        0x01: "MBC1",
        0x02: "MBC1 + RAM",
        0x03: "MBC1 + RAM + Battery",
        0x05: "MBC2",
        0x06: "MBC2 + Battery",
        0x08: "ROM + RAM",
        0x09: "ROM + RAM + Battery",
        0x0b: "MMM01",
        0x0c: "MMM01 + RAM",
        0x0d: "MMM01 + RAM + Battery",
        0x0f: "MBC3 + Timer + Battery",
        0x10: "MBC3 + Timer + RAM + Battery",
        0x11: "MBC3",
        0x12: "MBC3 + RAM",
        0x13: "MBC3 + RAM + Battery",
        0x19: "MBC5",
        0x1a: "MBC5 + RAM",
        0x1b: "MBC5 + RAM + Battery",
        0x1c: "MBC5 + Rumble",
        0x1d: "MBC5 + Rumble + RAM",
        0x1e: "MBC5 + Rumble + RAM + Battery",
        0x20: "MBC6",
        0x22: "MBC7 + Sensor + Rumble + RAM + Battery",
        0xfc: "Pocket Camera",
        0xfd: "Bandai TAMA5",
        0xfe: "HuC3",
        0xff: "HuC1 + RAM + Battery",
    ]
}

extension GBROMHeaderParser {
    /// Reads a stored image for display. The global checksum needs every byte, so the file is
    /// mapped rather than copied: only the header and the pages the sum touches are loaded.
    public static func parse(contentsOf url: URL) throws -> GBROMHeader {
        try parse(Data(contentsOf: url, options: .mappedIfSafe))
    }
}

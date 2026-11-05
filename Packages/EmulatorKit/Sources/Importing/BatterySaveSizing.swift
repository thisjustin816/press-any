import Foundation

/// How large an exported battery save is.
public enum SaveExportSize: Equatable, Sendable {
    /// The save as the library holds it.
    case original
    /// The smallest real cartridge RAM size that holds the save's data.
    case minimized
    /// A size that is neither the original nor the minimum: one of `SaveExportOptions.customSizes`.
    case custom(bytes: Int)
}

public enum SaveExportSizeError: Error, Equatable {
    /// The size is below the save's data, isn't a real RAM size, or isn't available for this save.
    case notOffered
}

/// The sizes a battery save can be exported at.
public struct SaveExportOptions: Equatable, Sendable {
    /// The save's length as the library holds it.
    public let originalBytes: Int
    /// Real RAM sizes below the original that hold all of the save's data, smallest first.
    /// Empty when the save can't be shrunk safely.
    public let smallerSizes: [Int]
    /// Real RAM sizes above the original that the cartridge's mapper can address, smallest first,
    /// for a chip with more RAM than the game declares. The save is padded with erased `0xFF`
    /// bytes. Empty when the save can't be grown safely.
    public let largerSizes: [Int]

    public init(originalBytes: Int, smallerSizes: [Int] = [], largerSizes: [Int] = []) {
        self.originalBytes = originalBytes
        self.smallerSizes = smallerSizes
        self.largerSizes = largerSizes
    }

    public var minimizedBytes: Int? { smallerSizes.first }

    /// Whether any size besides the original is offered.
    public var hasChoices: Bool { !smallerSizes.isEmpty || !largerSizes.isEmpty }

    /// The sizes that are neither the minimum nor the original, smallest first.
    public var customSizes: [Int] { Array(smallerSizes.dropFirst()) + largerSizes }
}

/// Which smaller sizes a battery save can be exported at. A cartridge writer sizes the save from
/// the cartridge, so a save larger than the chip wraps over its own data; a smaller export that
/// keeps all the data avoids that.
public enum BatterySaveSizing {
    /// The sizes cartridge RAM comes in that an export can use. 8 KB is one bank, the smallest
    /// size nearly every game uses.
    static let realSizes = [0x2000, 0x8000, 0x10000, 0x20000]

    /// Cartridges whose RAM isn't plain banked RAM: MBC2 and MBC7 keep their own layouts, MMM01
    /// remaps its banks, and TPP1 and HuC3 carry a clock after the RAM.
    private static let unshrinkableTypes: Set<UInt8> = [0x05, 0x06, 0x0B, 0x0C, 0x0D, 0x22, 0xBC, 0xFE]

    /// The most RAM a mapper can address, for the cartridges a save can be padded for. MBC1 and
    /// MBC3 reach four 8 KB banks and MBC5 sixteen. Any other cartridge is never grown, since its
    /// limit isn't known to be a real RAM size.
    private static func largestRAM(cartridgeType: UInt8) -> Int? {
        switch cartridgeType {
        case 0x01...0x03, 0x0F...0x13: 0x8000
        case 0x19...0x1E: 0x20000
        default: nil
        }
    }

    /// The other sizes `data` can be exported at. Only a save that is exactly the size its header
    /// declares changes size: a longer file has a clock after the RAM that a different length
    /// would misplace, and a different length means something else wrote it. Only an erased
    /// `0xFF` tail counts as unused, since that is what the core fills missing bytes with, and
    /// it is what a larger file is padded with.
    public static func options(for data: Data, header: GBROMHeader?) -> SaveExportOptions {
        let original = SaveExportOptions(originalBytes: data.count)
        guard let header,
              !unshrinkableTypes.contains(header.cartridgeType),
              [0x02, 0x03, 0x04, 0x05].contains(header.ramSizeCode),
              let declared = header.ramSizeBytes,
              declared == data.count
        else { return original }
        let used = bytesInUse(data)
        let largest = largestRAM(cartridgeType: header.cartridgeType) ?? declared
        return SaveExportOptions(
            originalBytes: data.count,
            smallerSizes: realSizes.filter { $0 >= used && $0 < declared },
            largerSizes: realSizes.filter { $0 > declared && $0 <= largest }
        )
    }

    /// `data` at `size`. A smaller size is the start of `data`, and a larger one is `data` followed
    /// by erased `0xFF` bytes.
    public static func bytes(of data: Data, size: SaveExportSize, options: SaveExportOptions) throws -> Data {
        switch size {
        case .original:
            return data
        case .minimized:
            guard let minimized = options.minimizedBytes else { throw SaveExportSizeError.notOffered }
            return Data(data.prefix(minimized))
        case .custom(let bytes):
            guard options.smallerSizes.contains(bytes) || options.largerSizes.contains(bytes) else {
                throw SaveExportSizeError.notOffered
            }
            return bytes <= data.count
                ? Data(data.prefix(bytes))
                : data + Data(repeating: 0xFF, count: bytes - data.count)
        }
    }

    /// Up to and including the last byte that isn't the erased `0xFF`; zero for an untouched save.
    private static func bytesInUse(_ data: Data) -> Int {
        guard let last = data.lastIndex(where: { $0 != 0xFF }) else { return 0 }
        return last - data.startIndex + 1
    }
}

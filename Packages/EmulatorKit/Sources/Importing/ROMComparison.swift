import EmulatorDomain
import Foundation

public struct ROMComparison: Equatable, Sendable {
    public struct BankChange: Equatable, Sendable {
        public let index: Int
        public let changedByteCount: Int

        public init(index: Int, changedByteCount: Int) {
            self.index = index
            self.changedByteCount = changedByteCount
        }
    }

    public enum HeaderChange: Equatable, Sendable {
        case title(old: String, new: String)
        case system(old: GameSystem, new: GameSystem)
        case cgbFlag(old: UInt8, new: UInt8)
        case cartridgeType(old: UInt8, new: UInt8)
        case romSizeCode(old: UInt8, new: UInt8)
        case ramSizeCode(old: UInt8, new: UInt8)
        case headerChecksum(old: UInt8, new: UInt8)
        case globalChecksum(old: UInt16, new: UInt16)
        case revisionNumber(old: UInt8, new: UInt8)
    }

    public let oldSize: Int
    public let newSize: Int
    public let changedByteCount: Int
    public let changedRanges: [Range<Int>]
    /// Bank counts include a final partial 16 KiB bank.
    public let oldBankCount: Int
    public let newBankCount: Int
    public let changedBanks: [BankChange]
    public let addedBanks: [Int]
    public let removedBanks: [Int]
    /// Nil when either header cannot be parsed; an empty array means no header fields differ.
    public let headerChanges: [HeaderChange]?

    public var addedByteCount: Int { max(0, newSize - oldSize) }
    public var removedByteCount: Int { max(0, oldSize - newSize) }
    public var isIdentical: Bool { oldSize == newSize && changedByteCount == 0 }

    public static func compare(_ old: Data, _ new: Data) -> ROMComparison {
        let bankSize = 0x4000
        func bankCount(_ size: Int) -> Int { size / bankSize + (size % bankSize == 0 ? 0 : 1) }
        let oldBankCount = bankCount(old.count)
        let newBankCount = bankCount(new.count)
        let sharedBankCount = min(oldBankCount, newBankCount)
        let sharedSize = min(old.count, new.count)
        var changedByteCount = 0
        var changedRanges: [Range<Int>] = []
        var bankChanges = [Int](repeating: 0, count: sharedBankCount)

        old.withUnsafeBytes { (oldBytes: UnsafeRawBufferPointer) in
            new.withUnsafeBytes { (newBytes: UnsafeRawBufferPointer) in
                var runStart: Int?
                for offset in 0..<sharedSize {
                    if oldBytes[offset] != newBytes[offset] {
                        changedByteCount += 1
                        bankChanges[offset / bankSize] += 1
                        if runStart == nil { runStart = offset }
                    } else if let start = runStart {
                        changedRanges.append(start..<offset)
                        runStart = nil
                    }
                }
                if let start = runStart { changedRanges.append(start..<sharedSize) }
            }
        }

        let changedBanks = bankChanges.enumerated().compactMap { index, count in
            count == 0 ? nil : BankChange(index: index, changedByteCount: count)
        }
        return ROMComparison(
            oldSize: old.count,
            newSize: new.count,
            changedByteCount: changedByteCount,
            changedRanges: changedRanges,
            oldBankCount: oldBankCount,
            newBankCount: newBankCount,
            changedBanks: changedBanks,
            addedBanks: Array(sharedBankCount..<newBankCount),
            removedBanks: Array(sharedBankCount..<oldBankCount),
            headerChanges: compareHeaders(old, new)
        )
    }

    private static func compareHeaders(_ old: Data, _ new: Data) -> [HeaderChange]? {
        guard let old = try? GBROMHeaderParser.parse(old),
              let new = try? GBROMHeaderParser.parse(new) else { return nil }
        var changes: [HeaderChange] = []
        if old.title != new.title { changes.append(.title(old: old.title, new: new.title)) }
        if old.system != new.system { changes.append(.system(old: old.system, new: new.system)) }
        if old.cgbFlag != new.cgbFlag { changes.append(.cgbFlag(old: old.cgbFlag, new: new.cgbFlag)) }
        if old.cartridgeType != new.cartridgeType {
            changes.append(.cartridgeType(old: old.cartridgeType, new: new.cartridgeType))
        }
        if old.romSizeCode != new.romSizeCode { changes.append(.romSizeCode(old: old.romSizeCode, new: new.romSizeCode)) }
        if old.ramSizeCode != new.ramSizeCode { changes.append(.ramSizeCode(old: old.ramSizeCode, new: new.ramSizeCode)) }
        if old.headerChecksum != new.headerChecksum {
            changes.append(.headerChecksum(old: old.headerChecksum, new: new.headerChecksum))
        }
        if old.globalChecksum != new.globalChecksum {
            changes.append(.globalChecksum(old: old.globalChecksum, new: new.globalChecksum))
        }
        if old.revisionNumber != new.revisionNumber {
            changes.append(.revisionNumber(old: old.revisionNumber, new: new.revisionNumber))
        }
        return changes
    }
}

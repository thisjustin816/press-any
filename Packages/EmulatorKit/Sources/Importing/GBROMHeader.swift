import EmulatorDomain
import Foundation

public struct GBROMHeader: Equatable, Sendable {
    public let title: String
    public let system: GameSystem
    public let cgbFlag: UInt8
    public let cartridgeType: UInt8
    public let romSizeCode: UInt8
    public let ramSizeCode: UInt8
    public let headerChecksum: UInt8
    public let headerChecksumValid: Bool
    public let globalChecksum: UInt16
    public let globalChecksumValid: Bool
    public let revisionNumber: UInt8

    public init(
        title: String,
        system: GameSystem,
        cgbFlag: UInt8,
        cartridgeType: UInt8,
        romSizeCode: UInt8,
        ramSizeCode: UInt8,
        headerChecksum: UInt8,
        headerChecksumValid: Bool,
        globalChecksum: UInt16,
        globalChecksumValid: Bool,
        revisionNumber: UInt8 = 0
    ) {
        self.title = title
        self.system = system
        self.cgbFlag = cgbFlag
        self.cartridgeType = cartridgeType
        self.romSizeCode = romSizeCode
        self.ramSizeCode = ramSizeCode
        self.headerChecksum = headerChecksum
        self.headerChecksumValid = headerChecksumValid
        self.globalChecksum = globalChecksum
        self.globalChecksumValid = globalChecksumValid
        self.revisionNumber = revisionNumber
    }
}

public enum GBROMHeaderError: Error, Equatable {
    case fileTooSmall(actual: Int)
}

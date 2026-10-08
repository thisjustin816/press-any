import Foundation

/// Source-image evidence keyed by immutable SHA-256 identity. Bank hashes preserve order and
/// repetitions; matching compares sets so relocating a bank keeps its evidence.
public struct ImageFingerprint: Equatable, Sendable {
    public let imageSHA256: String
    public let bankSize: Int
    public let bankHashes: [UInt64]
    public let headerTitle: String
    public let cartridgeType: UInt8
    public let ramSizeCode: UInt8
    public let cgbFlag: UInt8

    public init(imageSHA256: String, bankSize: Int, bankHashes: [UInt64], headerTitle: String,
                cartridgeType: UInt8, ramSizeCode: UInt8, cgbFlag: UInt8) {
        self.imageSHA256 = imageSHA256
        self.bankSize = bankSize
        self.bankHashes = bankHashes
        self.headerTitle = headerTitle
        self.cartridgeType = cartridgeType
        self.ramSizeCode = ramSizeCode
        self.cgbFlag = cgbFlag
    }
}

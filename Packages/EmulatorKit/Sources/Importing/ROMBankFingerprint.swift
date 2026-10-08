import EmulatorDomain
import Foundation

public enum ROMBankFingerprint {
    public static let bankSize = 16 * 1024

    public static func make(image: Data, sha256: String, header: GBROMHeader) -> ImageFingerprint {
        let hashes = image.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> [UInt64] in
            stride(from: 0, to: bytes.count - bytes.count % bankSize, by: bankSize).compactMap { start in
                let bank = bytes[start..<(start + bankSize)]
                if bank.allSatisfy({ $0 == 0 }) || bank.allSatisfy({ $0 == 0xff }) { return nil }
                // FNV-1a has a stable 64-bit representation across launches and platforms.
                return bank.reduce(UInt64(0xcbf29ce484222325)) { ($0 ^ UInt64($1)) &* 0x100000001b3 }
            }
        }
        return ImageFingerprint(imageSHA256: sha256, bankSize: bankSize, bankHashes: hashes,
            headerTitle: header.title, cartridgeType: header.cartridgeType,
            ramSizeCode: header.ramSizeCode, cgbFlag: header.cgbFlag)
    }
}

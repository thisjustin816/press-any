import Foundation

public enum PatchError: Error, Equatable {
    case malformedPatch
    case unsupportedFormat(String)
    case sourceMismatch(expectedSize: Int, actualSize: Int, expectedCRC32: UInt32, actualCRC32: UInt32)
    case targetSizeMismatch(expected: Int, actual: Int)
    case targetCRC32Mismatch(expected: UInt32, actual: UInt32)
    case patchCRC32Mismatch(expected: UInt32, actual: UInt32)
    case outOfBoundsRead
    /// The patch claims a result larger than any image it could legitimately produce.
    case targetTooLarge(Int)
}

extension PatchError {
    public var baseMismatchDescription: String? {
        guard case let .sourceMismatch(expectedSize, actualSize, expectedCRC32, actualCRC32) = self else { return nil }
        let expectedCRC = String(format: "%08X", expectedCRC32)
        let actualCRC = String(format: "%08X", actualCRC32)
        return "Patch expects: \(expectedSize) bytes, CRC32 \(expectedCRC)\nSelected input: \(actualSize) bytes, CRC32 \(actualCRC)"
    }
}

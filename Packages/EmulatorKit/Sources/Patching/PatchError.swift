import Foundation

public enum PatchError: Error, Equatable {
    case malformedPatch
    case unsupportedFormat(String)
    case sourceSizeMismatch(expected: Int, actual: Int)
    case targetSizeMismatch(expected: Int, actual: Int)
    case sourceCRC32Mismatch(expected: UInt32, actual: UInt32)
    case targetCRC32Mismatch(expected: UInt32, actual: UInt32)
    case patchCRC32Mismatch(expected: UInt32, actual: UInt32)
    case outOfBoundsRead
}

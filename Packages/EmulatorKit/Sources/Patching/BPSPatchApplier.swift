import Foundation

public struct BPSPatchApplier: Sendable {
    public init() {}

    /// With `ignoringBaseMismatch`, the source size and CRC and the resulting target CRC are not
    /// enforced, since a different base cannot produce the recorded target. The patch CRC is.
    public func apply(patch: Data, to source: Data, ignoringBaseMismatch: Bool = false) throws -> Data {
        guard patch.count >= 16, patch.prefix(4) == Data("BPS1".utf8) else {
            throw PatchError.malformedPatch
        }

        let trailerStart = patch.count - 12
        let expectedSourceCRC = try littleEndianUInt32(patch, at: trailerStart)
        let expectedTargetCRC = try littleEndianUInt32(patch, at: trailerStart + 4)
        let expectedPatchCRC = try littleEndianUInt32(patch, at: trailerStart + 8)

        let actualPatchCRC = CRC32.checksum(patch.prefix(patch.count - 4))
        guard actualPatchCRC == expectedPatchCRC else {
            throw PatchError.patchCRC32Mismatch(expected: expectedPatchCRC, actual: actualPatchCRC)
        }

        var reader = BPSReader(data: patch, limit: trailerStart, index: 4)
        let sourceSize = try reader.readInt()
        let targetSize = try reader.readInt()
        let metadataSize = try reader.readInt()

        guard ignoringBaseMismatch || sourceSize == source.count else {
            throw PatchError.sourceSizeMismatch(expected: sourceSize, actual: source.count)
        }
        guard reader.index + metadataSize <= trailerStart else { throw PatchError.malformedPatch }
        reader.index += metadataSize

        let actualSourceCRC = CRC32.checksum(source)
        guard ignoringBaseMismatch || actualSourceCRC == expectedSourceCRC else {
            throw PatchError.sourceCRC32Mismatch(expected: expectedSourceCRC, actual: actualSourceCRC)
        }

        let sourceBytes = [UInt8](source)
        var output = [UInt8]()
        output.reserveCapacity(targetSize)
        var sourceRelativeOffset: Int64 = 0
        var targetRelativeOffset: Int64 = 0

        while output.count < targetSize {
            guard reader.index < trailerStart else { throw PatchError.malformedPatch }
            let encoded = try reader.readNumber()
            let mode = Int(encoded & 3)
            guard encoded <= UInt64(Int.max) else { throw PatchError.malformedPatch }
            let length = Int((encoded >> 2) + 1)
            guard length > 0, output.count + length <= targetSize else {
                throw PatchError.malformedPatch
            }

            switch mode {
            case 0:
                let sourceOffset = output.count
                guard sourceOffset >= 0, sourceOffset + length <= sourceBytes.count else {
                    throw PatchError.outOfBoundsRead
                }
                output.append(contentsOf: sourceBytes[sourceOffset..<(sourceOffset + length)])

            case 1:
                guard reader.index + length <= trailerStart else { throw PatchError.malformedPatch }
                output.append(contentsOf: patch[reader.index..<(reader.index + length)])
                reader.index += length

            case 2:
                sourceRelativeOffset += try reader.readSignedNumber()
                guard sourceRelativeOffset >= 0 else { throw PatchError.outOfBoundsRead }
                let offset = Int(sourceRelativeOffset)
                guard offset + length <= sourceBytes.count else { throw PatchError.outOfBoundsRead }
                output.append(contentsOf: sourceBytes[offset..<(offset + length)])
                sourceRelativeOffset += Int64(length)

            case 3:
                targetRelativeOffset += try reader.readSignedNumber()
                guard targetRelativeOffset >= 0 else { throw PatchError.outOfBoundsRead }
                for _ in 0..<length {
                    let offset = Int(targetRelativeOffset)
                    guard offset < output.count else { throw PatchError.outOfBoundsRead }
                    output.append(output[offset])
                    targetRelativeOffset += 1
                }

            default:
                throw PatchError.malformedPatch
            }
        }

        guard output.count == targetSize else {
            throw PatchError.targetSizeMismatch(expected: targetSize, actual: output.count)
        }

        let result = Data(output)
        let actualTargetCRC = CRC32.checksum(result)
        guard ignoringBaseMismatch || actualTargetCRC == expectedTargetCRC else {
            throw PatchError.targetCRC32Mismatch(expected: expectedTargetCRC, actual: actualTargetCRC)
        }
        return result
    }

    private func littleEndianUInt32(_ data: Data, at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { throw PatchError.malformedPatch }
        return UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }
}

private struct BPSReader {
    let data: Data
    let limit: Int
    var index: Int

    mutating func readByte() throws -> UInt8 {
        guard index < limit else { throw PatchError.malformedPatch }
        defer { index += 1 }
        return data[index]
    }

    mutating func readNumber() throws -> UInt64 {
        var value: UInt64 = 0
        var shift: UInt64 = 1
        while true {
            let byte = try readByte()
            let product = UInt64(byte & 0x7f).multipliedReportingOverflow(by: shift)
            guard !product.overflow else { throw PatchError.malformedPatch }
            let sum = value.addingReportingOverflow(product.partialValue)
            guard !sum.overflow else { throw PatchError.malformedPatch }
            value = sum.partialValue
            if byte & 0x80 != 0 { return value }

            let shifted = shift << 7
            guard shifted > shift else { throw PatchError.malformedPatch }
            shift = shifted
            let adjusted = value.addingReportingOverflow(shift)
            guard !adjusted.overflow else { throw PatchError.malformedPatch }
            value = adjusted.partialValue
        }
    }

    mutating func readInt() throws -> Int {
        let value = try readNumber()
        guard value <= UInt64(Int.max) else { throw PatchError.malformedPatch }
        return Int(value)
    }

    mutating func readSignedNumber() throws -> Int64 {
        let value = try readNumber()
        guard value >> 1 <= UInt64(Int64.max) else { throw PatchError.malformedPatch }
        let magnitude = Int64(value >> 1)
        return value & 1 == 0 ? magnitude : -magnitude
    }
}

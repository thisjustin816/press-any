import Foundation

public struct IPSPatchApplier: Sendable {
    public init() {}

    public func apply(patch: Data, to source: Data) throws -> Data {
        let bytes = [UInt8](patch)
        guard bytes.count >= 8, Array(bytes.prefix(5)) == Array("PATCH".utf8) else {
            throw PatchError.malformedPatch
        }

        var output = [UInt8](source)
        var index = 5
        var foundEOF = false

        while index < bytes.count {
            guard index + 3 <= bytes.count else { throw PatchError.malformedPatch }
            if bytes[index] == 0x45, bytes[index + 1] == 0x4f, bytes[index + 2] == 0x46 {
                index += 3
                foundEOF = true
                break
            }

            let offset = Int(bytes[index]) << 16 | Int(bytes[index + 1]) << 8 | Int(bytes[index + 2])
            index += 3
            guard index + 2 <= bytes.count else { throw PatchError.malformedPatch }
            let size = Int(bytes[index]) << 8 | Int(bytes[index + 1])
            index += 2

            if size == 0 {
                guard index + 3 <= bytes.count else { throw PatchError.malformedPatch }
                let runLength = Int(bytes[index]) << 8 | Int(bytes[index + 1])
                let value = bytes[index + 2]
                index += 3
                guard runLength > 0 else { throw PatchError.malformedPatch }
                ensureCapacity(&output, through: offset + runLength)
                output.replaceSubrange(offset..<(offset + runLength), with: repeatElement(value, count: runLength))
            } else {
                guard index + size <= bytes.count else { throw PatchError.malformedPatch }
                ensureCapacity(&output, through: offset + size)
                output.replaceSubrange(offset..<(offset + size), with: bytes[index..<(index + size)])
                index += size
            }
        }

        guard foundEOF else { throw PatchError.malformedPatch }

        let remaining = bytes.count - index
        if remaining == 3 {
            // The trailing size only truncates, as in Lunar IPS; a larger one is ignored rather than
            // padding the image with up to 16 MB of zeros.
            let finalSize = Int(bytes[index]) << 16 | Int(bytes[index + 1]) << 8 | Int(bytes[index + 2])
            if finalSize < output.count {
                output.removeLast(output.count - finalSize)
            }
        } else if remaining != 0 {
            throw PatchError.malformedPatch
        }

        return Data(output)
    }

    private func ensureCapacity(_ bytes: inout [UInt8], through endIndex: Int) {
        guard endIndex > bytes.count else { return }
        bytes.append(contentsOf: repeatElement(0, count: endIndex - bytes.count))
    }
}

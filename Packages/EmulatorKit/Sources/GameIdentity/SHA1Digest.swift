#if canImport(CryptoKit)
import CryptoKit
#endif
import Foundation

/// SHA-1 as lowercase hex, for looking images up in No-Intro's data, which lists every dump's
/// SHA-1 but only some dumps' SHA-256. It identifies; the library's own identity stays SHA-256.
/// Apple platforms use CryptoKit; elsewhere (Linux CI) a portable implementation runs.
public enum SHA1Digest {
    public static func data(_ data: Data) -> String {
        var hasher = Hasher()
        hasher.update(data)
        return hasher.finalizeHex()
    }

    public static func file(at url: URL, chunkSize: Int = 1 << 20) throws -> String {
        precondition(chunkSize > 0)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = Hasher()
        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            hasher.update(chunk)
        }
        return hasher.finalizeHex()
    }

    #if canImport(CryptoKit)
    private struct Hasher {
        private var hasher = Insecure.SHA1()

        mutating func update(_ data: Data) {
            hasher.update(data: data)
        }

        mutating func finalizeHex() -> String {
            hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }
    }
    #else
    private typealias Hasher = SHA1Hasher
    #endif
}

private struct SHA1Hasher {
    private var state: [UInt32] = [0x6745_2301, 0xEFCD_AB89, 0x98BA_DCFE, 0x1032_5476, 0xC3D2_E1F0]
    private var pending = [UInt8]()
    private var totalBytes: UInt64 = 0
    private var schedule = [UInt32](repeating: 0, count: 80)

    mutating func update(_ data: Data) {
        totalBytes &+= UInt64(data.count)
        data.withUnsafeBytes { update($0) }
    }

    mutating func finalizeHex() -> String {
        let bitCount = totalBytes &* 8
        var tail = pending
        pending.removeAll()
        tail.append(0x80)
        while tail.count % 64 != 56 {
            tail.append(0)
        }
        tail.append(contentsOf: withUnsafeBytes(of: bitCount.bigEndian, Array.init))
        tail.withUnsafeBytes { update($0) }

        return state.map { String(format: "%08x", $0) }.joined()
    }

    /// Hashes whole blocks straight from the caller's buffer and keeps only a partial block back.
    private mutating func update(_ bytes: UnsafeRawBufferPointer) {
        var offset = 0
        if !pending.isEmpty {
            let taken = min(64 - pending.count, bytes.count)
            pending.append(contentsOf: bytes[0..<taken])
            offset = taken
            guard pending.count == 64 else { return }
            let block = pending
            pending.removeAll(keepingCapacity: true)
            block.withUnsafeBytes { process(UnsafeRawBufferPointer(rebasing: $0[0..<64])) }
        }
        while bytes.count - offset >= 64 {
            process(UnsafeRawBufferPointer(rebasing: bytes[offset..<(offset + 64)]))
            offset += 64
        }
        pending.append(contentsOf: bytes[offset...])
    }

    private mutating func process(_ block: UnsafeRawBufferPointer) {
        precondition(block.count == 64)

        for index in 0..<16 {
            let offset = index * 4
            schedule[index] =
                UInt32(block[offset]) << 24 |
                UInt32(block[offset + 1]) << 16 |
                UInt32(block[offset + 2]) << 8 |
                UInt32(block[offset + 3])
        }
        for index in 16..<80 {
            schedule[index] = rotateLeft(schedule[index - 3] ^ schedule[index - 8] ^ schedule[index - 14] ^ schedule[index - 16], by: 1)
        }

        var a = state[0]
        var b = state[1]
        var c = state[2]
        var d = state[3]
        var e = state[4]

        for index in 0..<80 {
            let mix: UInt32
            let constant: UInt32
            switch index {
            case 0..<20:
                mix = (b & c) | (~b & d)
                constant = 0x5A82_7999
            case 20..<40:
                mix = b ^ c ^ d
                constant = 0x6ED9_EBA1
            case 40..<60:
                mix = (b & c) | (b & d) | (c & d)
                constant = 0x8F1B_BCDC
            default:
                mix = b ^ c ^ d
                constant = 0xCA62_C1D6
            }
            let temp = rotateLeft(a, by: 5) &+ mix &+ e &+ constant &+ schedule[index]
            e = d
            d = c
            c = rotateLeft(b, by: 30)
            b = a
            a = temp
        }

        state[0] &+= a
        state[1] &+= b
        state[2] &+= c
        state[3] &+= d
        state[4] &+= e
    }

    private func rotateLeft(_ value: UInt32, by amount: UInt32) -> UInt32 {
        (value << amount) | (value >> (32 - amount))
    }
}

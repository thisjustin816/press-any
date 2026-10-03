#if canImport(CryptoKit)
import CryptoKit
#endif
import Foundation

/// SHA-256 as lowercase hex. Apple platforms use CryptoKit, which is hardware-accelerated and keeps
/// Quick Play's launch hash to milliseconds; elsewhere (Linux CI) a portable implementation runs.
public enum SHA256Digest {
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
        private var hasher = CryptoKit.SHA256()

        mutating func update(_ data: Data) {
            hasher.update(data: data)
        }

        mutating func finalizeHex() -> String {
            hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }
    }
    #else
    private typealias Hasher = SHA256Hasher
    #endif
}

private struct SHA256Hasher {
    private static let initialState: [UInt32] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ]

    private static let roundConstants: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
        0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
        0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
        0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
        0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    private var state = initialState
    private var pending = [UInt8]()
    private var totalBytes: UInt64 = 0
    private var schedule = [UInt32](repeating: 0, count: 64)

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
            let needed = 64 - pending.count
            let taken = min(needed, bytes.count)
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

        for index in 16..<64 {
            let s0 = rotateRight(schedule[index - 15], by: 7)
                ^ rotateRight(schedule[index - 15], by: 18)
                ^ (schedule[index - 15] >> 3)
            let s1 = rotateRight(schedule[index - 2], by: 17)
                ^ rotateRight(schedule[index - 2], by: 19)
                ^ (schedule[index - 2] >> 10)
            schedule[index] = schedule[index - 16] &+ s0 &+ schedule[index - 7] &+ s1
        }

        var a = state[0]
        var b = state[1]
        var c = state[2]
        var d = state[3]
        var e = state[4]
        var f = state[5]
        var g = state[6]
        var h = state[7]

        for index in 0..<64 {
            let bigSigma1 = rotateRight(e, by: 6) ^ rotateRight(e, by: 11) ^ rotateRight(e, by: 25)
            let choose = (e & f) ^ ((~e) & g)
            let temp1 = h &+ bigSigma1 &+ choose &+ Self.roundConstants[index] &+ schedule[index]
            let bigSigma0 = rotateRight(a, by: 2) ^ rotateRight(a, by: 13) ^ rotateRight(a, by: 22)
            let majority = (a & b) ^ (a & c) ^ (b & c)
            let temp2 = bigSigma0 &+ majority

            h = g
            g = f
            f = e
            e = d &+ temp1
            d = c
            c = b
            b = a
            a = temp1 &+ temp2
        }

        state[0] &+= a
        state[1] &+= b
        state[2] &+= c
        state[3] &+= d
        state[4] &+= e
        state[5] &+= f
        state[6] &+= g
        state[7] &+= h
    }

    private func rotateRight(_ value: UInt32, by amount: UInt32) -> UInt32 {
        (value >> amount) | (value << (32 - amount))
    }
}

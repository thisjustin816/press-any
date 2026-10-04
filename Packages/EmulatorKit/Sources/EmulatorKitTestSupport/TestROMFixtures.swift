import Foundation

/// The original test ROMs checked in under `TestROMs/` at the repository root, read through its
/// `manifest.json`. `TestROMs/README.md` describes each one.
public enum TestROMFixtures {
    public struct ROM: Decodable, Sendable {
        public let filename: String
        public let name: String
        /// `GB` or `GBC`.
        public let system: String
        public let sdk: String
        public let sdkVersion: String
        public let mapper: String
        /// Hex, as in `0x1E`.
        public let cartridgeType: String
        /// Hex, as in `0xC0`.
        public let cgbFlag: String
        public let sha256: String
        public let size: Int
        public let headerChecksumOk: Bool
        public let hero: Bool
        public let tags: [String]
    }

    public struct Patch: Decodable, Sendable {
        public let filename: String
        public let format: String
        public let source: String
        public let target: String
        public let sourceSha256: String
        public let targetSha256: String
    }

    public struct Manifest: Decodable, Sendable {
        public let roms: [ROM]
        public let patches: [Patch]
    }

    /// This file is `Packages/EmulatorKit/Sources/EmulatorKitTestSupport/TestROMFixtures.swift`.
    public static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("TestROMs", isDirectory: true)

    public static func manifest() throws -> Manifest {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Manifest.self, from: Data(contentsOf: directory.appendingPathComponent("manifest.json")))
    }

    public static func rom(_ filename: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent("roms").appendingPathComponent(filename))
    }

    public static func patch(_ filename: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent("patches").appendingPathComponent(filename))
    }

    /// Parses the manifest's `0x`-prefixed hex bytes.
    public static func byte(_ hex: String) -> UInt8? {
        guard hex.hasPrefix("0x") else { return nil }
        return UInt8(hex.dropFirst(2), radix: 16)
    }
}

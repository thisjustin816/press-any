import EmulatorDomain
import Foundation

/// Finds the Builds a BPS patch was made for: those whose image has the size and CRC32 the patch
/// records. Only images of that size are read. An IPS patch records neither, so it matches nothing.
public enum PatchBaseMatcher {
    public static func builds(
        matchingPatch patch: Data,
        among candidates: [(build: Build, byteLength: Int64)],
        image: (Build) throws -> Data
    ) -> [Build] {
        guard let source = BPSPatchApplier.expectedSource(of: patch) else { return [] }
        return candidates.filter { $0.byteLength == Int64(source.size) }.compactMap { candidate in
            guard let data = try? image(candidate.build), CRC32.checksum(data) == source.crc32 else { return nil }
            return candidate.build
        }
    }
}

import EmulatorDomain
import Foundation
import Patching
import XCTest

final class PatchBaseMatcherTests: XCTestCase {
    private func build(_ name: String) -> Build {
        Build(
            id: UUID(), gameID: UUID(), system: .gameBoy, displayName: name, imageAssetID: UUID(),
            imageSHA256: name, sourceKind: .importedImage, createdAt: .now, modifiedAt: .now
        )
    }

    func testABPSFindsTheBuildWithItsSourceSizeAndCRCAndReadsOnlyThatSize() throws {
        let base = Data(repeating: 1, count: 64)
        let sameSize = Data(repeating: 2, count: 64)
        let patch = bps(source: base, target: Data(repeating: 3, count: 128))
        XCTAssertEqual(BPSPatchApplier.expectedSource(of: patch)?.size, 64)
        XCTAssertEqual(BPSPatchApplier.expectedSource(of: patch)?.crc32, CRC32.checksum(base))

        let original = build("Original")
        let other = build("Other")
        let larger = build("Larger")
        var read: [String] = []
        let images = [original.id: base, other.id: sameSize]
        let matches = PatchBaseMatcher.builds(
            matchingPatch: patch,
            among: [(original, 64), (other, 64), (larger, 128)],
            image: { build in
                read.append(build.displayName)
                return try XCTUnwrap(images[build.id])
            }
        )
        XCTAssertEqual(matches.map(\.id), [original.id])
        XCTAssertEqual(read, ["Original", "Other"], "a Build of another size is never read")
    }

    func testIPSAndDamagedBPSMatchNothing() {
        let base = Data(repeating: 1, count: 64)
        var damaged = bps(source: base, target: base)
        damaged[damaged.count - 1] ^= 0xff
        let ips = Data("PATCH".utf8) + Data("EOF".utf8)
        for patch in [damaged, ips] {
            XCTAssertNil(BPSPatchApplier.expectedSource(of: patch))
            XCTAssertTrue(PatchBaseMatcher.builds(matchingPatch: patch, among: [(build("Original"), 64)], image: { _ in base }).isEmpty)
        }
    }

    /// A BPS patch that writes `target` wholesale and records `source` as its base.
    private func bps(source: Data, target: Data) -> Data {
        func number(_ value: Int) -> [UInt8] {
            var data = UInt64(value)
            var bytes: [UInt8] = []
            while true {
                let low = UInt8(data & 0x7f)
                data >>= 7
                if data == 0 {
                    bytes.append(0x80 | low)
                    return bytes
                }
                bytes.append(low)
                data -= 1
            }
        }
        func littleEndian(_ value: UInt32) -> [UInt8] {
            (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
        }
        var patch = Data("BPS1".utf8)
        patch.append(contentsOf: number(source.count))
        patch.append(contentsOf: number(target.count))
        patch.append(contentsOf: number(0))
        patch.append(contentsOf: number(((target.count - 1) << 2) | 1))
        patch.append(target)
        patch.append(contentsOf: littleEndian(CRC32.checksum(source)))
        patch.append(contentsOf: littleEndian(CRC32.checksum(target)))
        patch.append(contentsOf: littleEndian(CRC32.checksum(patch)))
        return patch
    }
}

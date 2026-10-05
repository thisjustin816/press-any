import Foundation
import XCTest
@testable import Patching

final class BPSPatchApplierTests: XCTestCase {
    func testBPSReplacesSingleByteAndValidatesCRCs() throws {
        let source = Data("ABC".utf8)
        let patch = try XCTUnwrap(Data(hex: "4250533183838080815880480383a393f9ae1348dc32ee"))

        XCTAssertEqual(try BPSPatchApplier().apply(patch: patch, to: source), Data("AXC".utf8))
    }

    func testBPSAppliesAPatchAndSourceThatAreSlices() throws {
        let patch = try XCTUnwrap(Data(hex: "4250533183838080815880480383a393f9ae1348dc32ee"))
        let framedPatch = Data([0xff, 0xff, 0xff]) + patch + Data([0xff])
        let framedSource = Data("--ABC".utf8)

        XCTAssertEqual(
            try BPSPatchApplier().apply(patch: framedPatch[3..<(3 + patch.count)], to: framedSource[2...]),
            Data("AXC".utf8)
        )
    }

    func testBPSRejectsWrongSourceCRC() throws {
        let source = Data("ZBC".utf8)
        let patch = try XCTUnwrap(Data(hex: "4250533183838080815880480383a393f9ae1348dc32ee"))

        XCTAssertThrowsError(try BPSPatchApplier().apply(patch: patch, to: source)) { error in
            guard case .sourceCRC32Mismatch = error as? PatchError else {
                return XCTFail("Expected source CRC mismatch, got \(error)")
            }
        }
    }

    func testApplyAnywayAppliesToADifferentBaseButStillChecksThePatch() throws {
        let patch = try XCTUnwrap(Data(hex: "4250533183838080815880480383a393f9ae1348dc32ee"))

        XCTAssertEqual(
            try BPSPatchApplier().apply(patch: patch, to: Data("ZBC".utf8), ignoringBaseMismatch: true),
            Data("ZXC".utf8)
        )

        var corrupt = patch
        corrupt[5] ^= 0xff
        XCTAssertThrowsError(try BPSPatchApplier().apply(patch: corrupt, to: Data("ZBC".utf8), ignoringBaseMismatch: true)) { error in
            guard case .patchCRC32Mismatch = error as? PatchError else {
                return XCTFail("Expected patch CRC mismatch, got \(error)")
            }
        }
    }

    func testCraftedSizesAndOffsetsAreRejectedRatherThanCrashing() {
        let source = Data("ABC".utf8)
        func expectRejection(_ patch: Data, _ expected: PatchError, line: UInt = #line) {
            XCTAssertThrowsError(try BPSPatchApplier().apply(patch: patch, to: source), line: line) { error in
                XCTAssertEqual(error as? PatchError, expected, line: line)
            }
        }

        expectRejection(
            craftedBPS(source: source, targetSize: 1 << 40, metadataSize: 0, actions: []),
            .targetTooLarge(1 << 40)
        )
        expectRejection(
            craftedBPS(source: source, targetSize: 3, metadataSize: 1 << 62, actions: []),
            .malformedPatch
        )
        // SourceCopy of one byte from a relative offset of 2^61.
        expectRejection(
            craftedBPS(source: source, targetSize: 3, metadataSize: 0, actions: bpsNumber(2) + bpsNumber(UInt64(1) << 62)),
            .outOfBoundsRead
        )
    }

    func testCRC32KnownVector() {
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xcbf43926)
    }
}

private func bpsNumber(_ value: UInt64) -> [UInt8] {
    var data = value
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

/// A BPS patch with the given header values and actions, and a valid patch CRC so the applier
/// gets past its integrity check to the values under test.
private func craftedBPS(source: Data, targetSize: UInt64, metadataSize: UInt64, actions: [UInt8]) -> Data {
    func littleEndian(_ value: UInt32) -> [UInt8] {
        (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
    }
    var patch = Data("BPS1".utf8)
    patch.append(contentsOf: bpsNumber(UInt64(source.count)))
    patch.append(contentsOf: bpsNumber(targetSize))
    patch.append(contentsOf: bpsNumber(metadataSize))
    patch.append(contentsOf: actions)
    patch.append(contentsOf: littleEndian(CRC32.checksum(source)))
    patch.append(contentsOf: littleEndian(0))
    patch.append(contentsOf: littleEndian(CRC32.checksum(patch)))
    return patch
}

private extension Data {
    init?(hex: String) {
        guard hex.count.isMultiple(of: 2) else { return nil }
        self.init()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            append(byte)
            index = next
        }
    }
}

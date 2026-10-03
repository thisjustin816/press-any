import Foundation
import XCTest
@testable import Patching

final class BPSPatchApplierTests: XCTestCase {
    func testBPSReplacesSingleByteAndValidatesCRCs() throws {
        let source = Data("ABC".utf8)
        let patch = try XCTUnwrap(Data(hex: "4250533183838080815880480383a393f9ae1348dc32ee"))

        XCTAssertEqual(try BPSPatchApplier().apply(patch: patch, to: source), Data("AXC".utf8))
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

    func testCRC32KnownVector() {
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xcbf43926)
    }
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

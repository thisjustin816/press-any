import EmulatorApplication
import Foundation
import XCTest
@testable import Patching

final class PatchStackApplierTests: XCTestCase {
    func testPatchStackAppliesEnabledItemsInOrder() throws {
        let first = Data([
            0x50, 0x41, 0x54, 0x43, 0x48,
            0x00, 0x00, 0x00, 0x00, 0x01, 0x58,
            0x45, 0x4f, 0x46,
        ])
        let second = Data([
            0x50, 0x41, 0x54, 0x43, 0x48,
            0x00, 0x00, 0x01, 0x00, 0x01, 0x59,
            0x45, 0x4f, 0x46,
        ])
        let items = [
            PatchStackItem(data: first, fileExtension: "ips", enabled: true),
            PatchStackItem(data: Data([0]), fileExtension: "ips", enabled: false),
            PatchStackItem(data: second, fileExtension: ".IPS", enabled: true),
        ]

        XCTAssertEqual(try PatchStackApplier().apply(items: items, to: Data("ABC".utf8)), Data("XYC".utf8))
    }

    func testAPatchOverTheSizeLimitIsNotApplied() {
        let oversized = Data(count: Int(ImportSizeLimit.patch.bytes) + 1)
        XCTAssertThrowsError(
            try PatchStackApplier().apply(patch: oversized, fileExtension: "ips", to: Data(), ignoringBaseMismatch: false)
        ) { XCTAssertEqual($0 as? ImportSizeError, .fileTooLarge(limit: ImportSizeLimit.patch.bytes)) }
    }

    func testUnsupportedPatchFormatIsExplicit() {
        XCTAssertThrowsError(
            try PatchStackApplier().apply(
                items: [PatchStackItem(data: Data(), fileExtension: "xdelta")],
                to: Data()
            )
        ) { error in
            XCTAssertEqual(error as? PatchError, .unsupportedFormat("xdelta"))
        }
    }
}

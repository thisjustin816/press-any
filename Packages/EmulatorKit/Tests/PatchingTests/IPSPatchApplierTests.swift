import Foundation
import XCTest
@testable import Patching

final class IPSPatchApplierTests: XCTestCase {
    func testIPSReplacesSingleByte() throws {
        let source = Data("ABC".utf8)
        let patch = Data([
            0x50, 0x41, 0x54, 0x43, 0x48,
            0x00, 0x00, 0x01,
            0x00, 0x01,
            0x58,
            0x45, 0x4f, 0x46,
        ])

        XCTAssertEqual(try IPSPatchApplier().apply(patch: patch, to: source), Data("AXC".utf8))
    }

    func testIPSAppliesRLEAndExtendsOutput() throws {
        let source = Data([0x00])
        let patch = Data([
            0x50, 0x41, 0x54, 0x43, 0x48,
            0x00, 0x00, 0x02,
            0x00, 0x00,
            0x00, 0x03,
            0x7f,
            0x45, 0x4f, 0x46,
        ])

        XCTAssertEqual(try IPSPatchApplier().apply(patch: patch, to: source), Data([0x00, 0x00, 0x7f, 0x7f, 0x7f]))
    }

    func testIPSOptionalFinalSizeTruncatesOutput() throws {
        let source = Data("ABCDE".utf8)
        let patch = Data([
            0x50, 0x41, 0x54, 0x43, 0x48,
            0x45, 0x4f, 0x46,
            0x00, 0x00, 0x03,
        ])

        XCTAssertEqual(try IPSPatchApplier().apply(patch: patch, to: source), Data("ABC".utf8))
    }

    func testIPSRejectsMalformedPatch() {
        XCTAssertThrowsError(try IPSPatchApplier().apply(patch: Data("PATCH".utf8), to: Data())) { error in
            XCTAssertEqual(error as? PatchError, .malformedPatch)
        }
    }
}

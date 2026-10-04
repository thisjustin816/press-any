import EmulatorKitTestSupport
import Foundation
import Patching
import XCTest

/// The patches in `TestROMs/` were made by their own tool, so applying them here checks both
/// that tool and these appliers against the target ROM it recorded.
final class TestROMPatchTests: XCTestCase {
    func testEachPatchTurnsItsSourceIntoItsTarget() throws {
        let patches = try TestROMFixtures.manifest().patches
        XCTAssertEqual(Set(patches.map(\.format)), ["IPS", "BPS"])
        for patch in patches {
            let source = try TestROMFixtures.rom(patch.source)
            let data = try TestROMFixtures.patch(patch.filename)
            let result = switch patch.format {
            case "IPS": try IPSPatchApplier().apply(patch: data, to: source)
            default: try BPSPatchApplier().apply(patch: data, to: source)
            }
            XCTAssertEqual(result, try TestROMFixtures.rom(patch.target), patch.filename)
        }
    }
}

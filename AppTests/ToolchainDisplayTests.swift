import EmulatorDomain
import XCTest
@testable import PressAny

final class ToolchainDisplayTests: XCTestCase {
    private func shown(_ kind: ToolchainComponentKind, _ name: String, _ version: String?) -> ToolchainDisplay {
        ToolchainDisplay(DetectedToolchainComponent(kind: kind, name: name, version: version, evidence: []))
    }

    func testNamesAreSpelledAsTheirProjectsSpellThem() {
        XCTAssertEqual(shown(.engine, "GBStudio", "4.3.0+"), ToolchainDisplay(name: "GB Studio", version: "4.3.0 or later", variant: nil))
        XCTAssertEqual(shown(.engine, "ZGB", nil), ToolchainDisplay(name: "ZGB", version: nil, variant: nil))
    }

    func testGBDK2020VersionsDropTheDetectorsYearPrefix() {
        XCTAssertEqual(shown(.toolchain, "GBDK", "2020.4.3.0+"), ToolchainDisplay(name: "GBDK-2020", version: "4.3.0 or later", variant: nil))
        XCTAssertEqual(shown(.toolchain, "GBDK", "2020.4.1.0 - 2020.4.1.1"), ToolchainDisplay(name: "GBDK-2020", version: "4.1.0 to 4.1.1", variant: nil))
        XCTAssertEqual(shown(.toolchain, "GBDK", "2.9.5 - 2020.3.1.0"), ToolchainDisplay(name: "GBDK", version: "2.9.5 to 2020.3.1.0", variant: nil))
        XCTAssertEqual(shown(.toolchain, "GBDK", "2.0.18 - 2.1.5"), ToolchainDisplay(name: "GBDK", version: "2.0.18 to 2.1.5", variant: nil))
        XCTAssertEqual(shown(.toolchain, "GBDK", "Unknown"), ToolchainDisplay(name: "GBDK", version: nil, variant: nil))
    }

    func testAudioDriverEditionsAreVariantsNotVersions() {
        XCTAssertEqual(shown(.musicDriver, "hUGETracker", "SuperDisk"), ToolchainDisplay(name: "hUGETracker", version: nil, variant: "SuperDisk"))
        XCTAssertEqual(shown(.musicDriver, "DevSound", "X2"), ToolchainDisplay(name: "DevSound", version: nil, variant: "X2"))
        XCTAssertEqual(shown(.engine, "GBBasic", "Alpha3"), ToolchainDisplay(name: "GB BASIC", version: "Alpha3", variant: nil))
        XCTAssertEqual(shown(.musicDriver, "MPlay", "2"), ToolchainDisplay(name: "MPlay", version: "2", variant: nil))
    }
}

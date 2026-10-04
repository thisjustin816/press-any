import EmulatorDomain
import Foundation
import XCTest
@testable import ToolchainDetection

/// Compares the Swift port with the gbtoolsid C tool on a corpus built by
/// Scripts/test-toolchain-detection-differential.sh, which sets GBTOOLSID_DIFFERENTIAL_CORPUS.
/// Without that variable there is nothing to compare against, so the test is skipped; the
/// toolchain-detection CI job always sets it.
final class GBToolsIDDifferentialTests: XCTestCase {
    func testMatchesGBToolsIDOnCorpus() throws {
        guard let path = ProcessInfo.processInfo.environment["GBTOOLSID_DIFFERENTIAL_CORPUS"] else {
            throw XCTSkip("GBTOOLSID_DIFFERENTIAL_CORPUS is not set; run Scripts/test-toolchain-detection-differential.sh")
        }
        let directory = URL(fileURLWithPath: path)
        let roms = try FileManager.default.contentsOfDirectory(atPath: path)
            .filter { !$0.hasSuffix(".txt") }
            .sorted()
        XCTAssertGreaterThan(roms.count, 0, "empty corpus at \(path)")

        var mismatches: [String] = []
        for rom in roms {
            let image = try Data(contentsOf: directory.appendingPathComponent(rom))
            for (strict, suffix) in [(false, "expected.txt"), (true, "expected-strict.txt")] {
                let expected = try String(contentsOf: directory.appendingPathComponent("\(rom).\(suffix)"), encoding: .utf8)
                let actual = render(GBToolsIDDetector(strictMode: strict).detect(image: image))
                if actual != expected {
                    mismatches.append("\(rom) [\(suffix)]\n--- gbtoolsid\n\(expected)--- port\n\(actual)")
                }
            }
        }

        XCTAssertTrue(
            mismatches.isEmpty,
            "\(mismatches.count) of \(roms.count * 2) results differ from gbtoolsid:\n\n" + mismatches.prefix(15).joined(separator: "\n")
        )
    }

    /// gbtoolsid's default text output (display.c, render_entry_default) without the File: line.
    private func render(_ report: ToolchainDetectionReport) -> String {
        var lines: [String] = []
        let groups: [(String, ToolchainComponentKind)] = [
            ("Tools", .toolchain), ("Engine", .engine), ("Music", .musicDriver), ("SoundFX", .soundEffectsDriver),
        ]
        for (label, kind) in groups {
            let components = report.components(of: kind)
            if components.isEmpty, kind == .toolchain {
                lines.append("\(label): <unknown>")
            }
            for component in components {
                lines.append("\(label): \(component.name)" + (component.version.map { ", Version: \($0)" } ?? ""))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

import EmulatorDomain
import Foundation
import XCTest
@testable import ToolchainDetection

/// Synthetic images that plant gbtoolsid's own signatures, so no game content is needed.
final class GBToolsIDDetectorTests: XCTestCase {
    private typealias D = GBToolsIDData

    func testEmptyAndUnrecognizedImagesReportNothing() {
        XCTAssertEqual(detect([]).components, [])
        XCTAssertEqual(detect([UInt8](repeating: 0, count: 0x8000)).components, [])
    }

    func testGBStudioOnGBDKReportsEachLayer() throws {
        var image = blankImage()
        plantGBDK430(&image)
        plant(&image, 0x2000, D.sig_gbs_math_c_sinetable_3_0_0_alpha1_plus.bytes)
        plant(&image, 0x3000, D.sig_gbs_vminstruct_4_0_0_plus.bytes)
        plant(&image, 0x3800, D.sig_gbs_iotafmt_4_2_0_plus.bytes)
        plant(&image, 0x4000, D.sig_hugetracker_fx_vol_slide_base_v1.bytes)
        plant(&image, 0x5000, D.sig_vgm2gbsfx_aud3waveram_load.bytes)

        let report = detect(image)
        XCTAssertEqual(report.components.map(\.kind), [.toolchain, .engine, .musicDriver, .soundEffectsDriver])
        XCTAssertEqual(report.components.map(\.name), ["GBDK", "GBStudio", "hUGETracker", "VGM2GBSFX"])
        XCTAssertEqual(report.components.map(\.version), ["2020.4.3.0+", "4.1.0+", "SuperDisk", nil])

        // Each component carries the signatures its own check matched.
        let gbdk = try XCTUnwrap(report.components.first)
        XCTAssertTrue(gbdk.evidence.allSatisfy { $0.signature.hasPrefix("sig_gbdk_") })
        let music = report.components(of: .musicDriver)
        XCTAssertEqual(music.first?.evidence, [ToolchainEvidence(signature: "sig_hugetracker_fx_vol_slide_base_v1", offset: 0x4000)])
    }

    func testStrictModeTestsEnginesOnlyAfterGBDK() {
        // GBBasic's marker sits at 0x20000, so the image must be at least 160 KB.
        var image = [UInt8](repeating: 0, count: 0x28000)
        plant(&image, D.sig_gbbasic_magic_v11_at, D.sig_gbbasic_magic_v11.bytes)

        XCTAssertEqual(detect(image).components.map(\.name), ["GBBasic"])
        XCTAssertEqual(GBToolsIDDetector(strictMode: true).detect(image: Data(image)).components, [])
    }

    func testQuickThunderIgnoresTheLastByteOfItsPattern() {
        // gbtoolsid searches this byte buffer with its string macro, which drops the final byte.
        var image = blankImage()
        let pattern = D.sig_quickthunder_audio_arts_ch2.bytes
        plant(&image, 0x1000, Array(pattern.dropLast()))
        image[0x1000 + pattern.count - 1] = pattern.last! ^ 0xFF

        XCTAssertEqual(detect(image).components(of: .musicDriver).map(\.name), ["QuickThunder"])
    }

    func testTurboRascalHeaderIncludesItsTerminator() {
        var image = blankImage()
        plant(&image, 0x134, Array("TRSE GB".utf8) + [0])
        XCTAssertEqual(detect(image).components.map(\.name), ["Turbo Rascal Syntax Error"])

        // Without the NUL that C's sizeof() includes, gbtoolsid does not match.
        image[0x13B] = 0x20
        XCTAssertEqual(detect(image).components, [])
    }

    func testRegistryRunsDetectorsForSupportedSystemsAndReportsRoundTrip() throws {
        var image = blankImage()
        plantGBDK430(&image)

        let reports = ToolchainDetectorRegistry.standard.detect(image: Data(image), system: .gameBoyColor)
        let report = try XCTUnwrap(reports.first)
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(report.detector, "gbtoolsid")
        XCTAssertEqual(report.corpusRevision, D.upstreamRevision)

        let decoded = try JSONDecoder().decode(ToolchainDetectionReport.self, from: JSONEncoder().encode(report))
        XCTAssertEqual(decoded, report)
    }

    // MARK: Helpers

    private func detect(_ image: [UInt8]) -> ToolchainDetectionReport {
        GBToolsIDDetector().detect(image: Data(image))
    }

    private func blankImage() -> [UInt8] {
        [UInt8](repeating: 0, count: 0x8000)
    }

    private func plant(_ image: inout [UInt8], _ offset: Int, _ bytes: [UInt8]) {
        image.replaceSubrange(offset..<(offset + bytes.count), with: bytes)
    }

    /// The fixed-address crt0 signatures sig_gbdk.c walks to reach "2020.4.3.0+".
    private func plantGBDK430(_ image: inout [UInt8]) {
        plant(&image, D.sig_gbdk_0x20_at, D.sig_gbdk_0x20_GBDK_2020_401_plus_0x20.bytes)
        plant(&image, D.sig_gbdk_0x28_at, D.sig_gbdk_0x20_GBDK_2020_401_plus_0x28.bytes)
        plant(&image, D.sig_gbdk_0x30_at, D.sig_gbdk_0x30_GBDK_2020_401_plus.bytes)
        plant(&image, D.sig_gbdk_0x157_GBDK_2020_405_plus_at, D.sig_gbdk_0x157_GBDK_2020_405_plus.bytes)
        plant(&image, D.sig_gbdk_clear_WRAM_tail_GBDK_2020_420_at, D.sig_gbdk_clear_WRAM_tail_GBDK_2020_420.bytes)
        plant(&image, D.sig_gbdk_clear_WRAM_tail_GBDK_2020_430_plus_at, D.sig_gbdk_clear_WRAM_tail_GBDK_2020_430_plus.bytes)
    }
}

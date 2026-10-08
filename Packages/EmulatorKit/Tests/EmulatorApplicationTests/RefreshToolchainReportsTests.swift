import AssetStorage
import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import XCTest

final class RefreshToolchainReportsTests: XCTestCase {
    func testDetectsABuildWithNoReportAndKeepsAnUnchangedOneAsIs() throws {
        let fixture = try Fixture()
        let refresh = fixture.refresh { [unowned fixture] in
            fixture.detections += 1
            return [report(fixture.found)]
        }

        XCTAssertEqual(try refresh.execute(build: fixture.build), [report("GBDK")])
        XCTAssertEqual(fixture.reports.saves, 1)

        XCTAssertEqual(try refresh.execute(build: fixture.build), [report("GBDK")])
        XCTAssertEqual(fixture.reports.saves, 1, "an unchanged report isn't written again")

        fixture.found = "ZGB"
        XCTAssertEqual(try refresh.execute(build: fixture.build), [report("ZGB")])
        XCTAssertEqual(fixture.reports.saves, 2)
        XCTAssertEqual(fixture.detections, 3, "every refresh reads the image again")
    }
}

private func report(_ name: String) -> ToolchainDetectionReport {
    ToolchainDetectionReport(
        detector: "gbtoolsid",
        detectorVersion: "1",
        corpusRevision: "v1.5.5-14-g5ff49ad",
        components: [DetectedToolchainComponent(kind: .toolchain, name: name, version: nil, evidence: [])]
    )
}

private final class Fixture: @unchecked Sendable {
    let store: ManagedFileStore
    let reports = CountingReports()
    let build: Build
    let imageURL: URL
    var detections = 0
    var found = "GBDK"

    init() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Refresh-\(UUID().uuidString)")
        store = try ManagedFileStore(rootURL: root)
        imageURL = root.appendingPathComponent("image.gb")
        try TestROM.make(title: "REFRESH").write(to: imageURL)
        let now = Date(timeIntervalSince1970: 0)
        build = Build(
            id: UUID(),
            gameID: UUID(),
            system: .gameBoy,
            displayName: "Original",
            imageAssetID: UUID(),
            imageSHA256: "hash",
            sourceKind: .importedImage,
            createdAt: now,
            modifiedAt: now
        )
    }

    func refresh(_ detect: @escaping @Sendable () -> [ToolchainDetectionReport]) -> RefreshToolchainReports {
        RefreshToolchainReports(
            reports: reports,
            images: FixedImage(url: imageURL),
            assetStore: store,
            detect: { _, _ in detect() }
        )
    }
}

private struct FixedImage: BuildImageResolving {
    let url: URL
    func resolveImageURL(buildID: UUID) throws -> URL { url }
}

/// Counts writes, so a test can tell an unchanged report wasn't saved again.
private final class CountingReports: ToolchainReportRepository, @unchecked Sendable {
    private let inner = InMemoryToolchainReportRepository()
    private(set) var saves = 0

    func saveReport(_ report: ToolchainDetectionReport, buildID: UUID, detectedAt: Date) throws {
        saves += 1
        try inner.saveReport(report, buildID: buildID, detectedAt: detectedAt)
    }

    func fetchAllReports() throws -> [UUID: [ToolchainDetectionReport]] { try inner.fetchAllReports() }

    func fetchReports(buildID: UUID) throws -> [ToolchainDetectionReport] {
        try inner.fetchReports(buildID: buildID)
    }
}

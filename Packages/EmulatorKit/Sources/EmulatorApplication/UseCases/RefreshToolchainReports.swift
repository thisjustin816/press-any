import EmulatorDomain
import Foundation

/// Keeps a Build's toolchain reports current. It detects the Build's image again and stores each
/// report that differs from the one kept, which covers a Build imported before detection ran and a
/// detector or signature corpus that has changed since.
public struct RefreshToolchainReports: Sendable {
    public typealias Detect = @Sendable (_ image: Data, _ system: GameSystem) -> [ToolchainDetectionReport]

    private let reports: any ToolchainReportRepository
    private let images: any BuildImageResolving
    private let detect: Detect
    private let now: @Sendable () -> Date

    public init(
        reports: any ToolchainReportRepository,
        images: any BuildImageResolving,
        detect: @escaping Detect,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.reports = reports
        self.images = images
        self.detect = detect
        self.now = now
    }

    public func execute(build: Build) throws -> [ToolchainDetectionReport] {
        let image = try images.readImage(buildID: build.id)
        let fresh = detect(image, build.system)
        let kept = Dictionary(uniqueKeysWithValues: try reports.fetchReports(buildID: build.id).map { ($0.detector, $0) })
        let timestamp = now()
        for report in fresh where kept[report.detector] != report {
            try reports.saveReport(report, buildID: build.id, detectedAt: timestamp)
        }
        return try reports.fetchReports(buildID: build.id)
    }
}

import EmulatorApplication
import EmulatorDomain
import Foundation
import GameIdentity
import ToolchainDetection

/// Clears a Revision that import took from the ROM header of a Build made with GBDK, GB Studio or
/// ZGB, where the header byte is the toolchain's default (see `BuildImportMetadata.headerRevision`).
/// A Revision the player set, or that No-Intro or the filename gave, stays. The cleared field keeps
/// a ROM Header provenance row offering no value, so Metadata Details still shows where it came from.
/// It only touches Builds still holding a header Revision, so running it again changes nothing.
public struct ClearGBDKHeaderRevisions: Sendable {
    private let builds: any BuildRepository
    private let assets: any ManagedAssetRepository
    private let reports: any ToolchainReportRepository
    private let images: any BuildImageResolving
    private let refreshReports: RefreshToolchainReports
    private let knownDumps: KnownDumpIndex?
    private let transactions: any LibraryTransactionRunner
    private let now: @Sendable () -> Date

    public init(
        builds: any BuildRepository,
        assets: any ManagedAssetRepository,
        reports: any ToolchainReportRepository,
        images: any BuildImageResolving,
        knownDumps: KnownDumpIndex?,
        detect: @escaping RefreshToolchainReports.Detect = { ToolchainDetectorRegistry.standard.detect(image: $0, system: $1) },
        transactions: any LibraryTransactionRunner = PassthroughTransactionRunner(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.builds = builds
        self.assets = assets
        self.reports = reports
        self.images = images
        refreshReports = RefreshToolchainReports(reports: reports, images: images, detect: detect, now: now)
        self.knownDumps = knownDumps
        self.transactions = transactions
        self.now = now
    }

    /// Returns the IDs of the Builds it cleared. A Build whose image can't be read is left for the
    /// next run rather than stopping the others.
    @discardableResult
    public func execute() throws -> [UUID] {
        try builds.fetchImportedBuilds().filter { build in
            build.revision != nil && (try? clearIfFromGBDKHeader(build)) == true
        }.map(\.id)
    }

    private func clearIfFromGBDKHeader(_ build: Build) throws -> Bool {
        guard try revisionCameFromHeader(build) else { return false }
        var detected = try reports.fetchReports(buildID: build.id)
        if detected.isEmpty { detected = try refreshReports.execute(build: build) }
        guard detected.isBuiltWithGBDK else { return false }
        let timestamp = now()
        try transactions.run {
            var updated = build
            updated.revision = nil
            updated.modifiedAt = timestamp
            try builds.updateBuildMetadata(updated)
            try builds.saveMetadataProvenance(MetadataProvenance(field: .revision, source: .romHeader,
                providedValue: nil, recordedAt: timestamp), ownerID: build.id)
        }
        return true
    }

    private func revisionCameFromHeader(_ build: Build) throws -> Bool {
        if let row = try builds.fetchMetadataProvenance(ownerID: build.id).first(where: { $0.field == .revision }) {
            return row.source == .romHeader && row.providedValue == build.revision
        }
        // With no provenance row, the Revision came from the header only if it is the header's
        // byte, and neither No-Intro nor the imported filename names a revision.
        if let sha1 = build.imageSHA1, knownDumps?.dump(sha1: sha1) != nil { return false }
        let header = try GBROMHeaderParser.parse(images.readImage(buildID: build.id))
        guard header.revisionNumber > 0, String(header.revisionNumber) == build.revision,
              let filename = try assets.fetchAsset(id: build.imageAssetID)?.originalFilename else { return false }
        return FilenameMetadataParser.parse(filename: filename).buildMetadata.revision == nil
    }
}

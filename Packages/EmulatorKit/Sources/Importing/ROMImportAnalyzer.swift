import EmulatorApplication
import Foundation
import GameIdentity
import ToolchainDetection

public struct ROMImportAnalyzer: Sendable {
    private let builds: any BuildRepository
    private let assetStore: any AssetStore
    private let detectors: ToolchainDetectorRegistry
    private let knownDumps: KnownDumpIndex?
    private let makeTransactionID: @Sendable () -> UUID

    public init(
        builds: any BuildRepository,
        assetStore: any AssetStore,
        detectors: ToolchainDetectorRegistry = .standard,
        knownDumps: KnownDumpIndex? = nil,
        makeTransactionID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.builds = builds
        self.assetStore = assetStore
        self.detectors = detectors
        self.knownDumps = knownDumps
        self.makeTransactionID = makeTransactionID
    }

    public func analyzeROM(at sourceURL: URL, targetGameID: UUID?, originalFilename: String? = nil) throws -> ROMImportAnalysis {
        try ImportSizeLimit.rom.check(fileAt: sourceURL)
        let transactionID = makeTransactionID()
        let stagedURL = try assetStore.stageCopy(from: sourceURL, transactionID: transactionID)
        do {
            let data = try Data(contentsOf: stagedURL, options: .mappedIfSafe)
            let sha256 = try assetStore.hashFile(at: stagedURL)
            let sha1 = SHA1Digest.data(data)
            let header = try GBROMHeaderParser.parse(data)
            let existing = try builds.fetchBuild(imageSHA256: sha256)
            let suppliedFilename = originalFilename ?? sourceURL.lastPathComponent
            let visibleFilename = suppliedFilename.removingPercentEncoding ?? suppliedFilename
            let knownDump = knownDumps?.dump(sha1: sha1)
            // A known dump is named from No-Intro's own fields, keeping the file's extension.
            let fileExtension = URL(fileURLWithPath: visibleFilename).pathExtension.lowercased()
            let naming = knownDump.map {
                FilenameMetadata(knownDump: $0, fileExtension: fileExtension.isEmpty ? $0.system.rawValue : fileExtension)
            } ?? FilenameMetadataParser.parse(filename: visibleFilename)
            let familyGameIDs = try knownDump.map(familyGameIDs(of:)) ?? []
            return ROMImportAnalysis(
                transactionID: transactionID,
                stagedURL: stagedURL,
                originalFilename: visibleFilename,
                sha256: sha256,
                byteLength: Int64(data.count),
                header: header,
                filenameMetadata: naming,
                exactExistingBuildID: existing?.id,
                suggestedGameID: targetGameID ?? existing?.gameID ?? (familyGameIDs.count == 1 ? familyGameIDs[0] : nil),
                toolchainReports: detectors.detect(image: data, system: header.system),
                imageSHA1: sha1,
                knownDump: knownDump,
                knownFile: knownDumps?.file(sha1: sha1),
                familyGameIDs: familyGameIDs
            )
        } catch {
            try? assetStore.removeIfExists(stagedURL.deletingLastPathComponent())
            throw error
        }
    }

    /// The Games already holding a Build from any file of the dump's No-Intro family, bad copies
    /// included, in the order their first such Build arrived.
    private func familyGameIDs(of dump: KnownDump) throws -> [UUID] {
        guard let knownDumps else { return [] }
        var seen = Set<UUID>()
        return try builds.fetchBuilds(imageSHA1s: knownDumps.family(of: dump).flatMap(\.files).map(\.sha1))
            .map(\.gameID)
            .filter { seen.insert($0).inserted }
    }
}

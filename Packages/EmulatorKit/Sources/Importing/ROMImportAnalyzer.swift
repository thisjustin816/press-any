import EmulatorApplication
import EmulatorDomain
import Foundation
import GameIdentity
import ToolchainDetection

public struct ROMImportAnalyzer: Sendable {
    private let builds: any BuildRepository
    private let games: (any GameRepository)?
    private let fingerprints: any ImageFingerprintRepository
    private let toolchainReports: any ToolchainReportRepository
    private let assetStore: any AssetStore
    private let detectors: ToolchainDetectorRegistry
    private let knownDumps: KnownDumpIndex?
    private let makeTransactionID: @Sendable () -> UUID

    public init(
        builds: any BuildRepository,
        games: (any GameRepository)? = nil,
        fingerprints: any ImageFingerprintRepository,
        toolchainReports: any ToolchainReportRepository,
        assetStore: any AssetStore,
        detectors: ToolchainDetectorRegistry = .standard,
        knownDumps: KnownDumpIndex? = nil,
        makeTransactionID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.builds = builds
        self.games = games
        self.fingerprints = fingerprints
        self.toolchainReports = toolchainReports
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
            let lineageIDs = try knownDump.map(lineageGameIDs(of:)) ?? []
            var familyGameIDs = try knownDump.map(familyGameIDs(of:)) ?? []
            for id in lineageIDs where !familyGameIDs.contains(id) { familyGameIDs.append(id) }
            let fingerprint = ROMBankFingerprint.make(image: data, sha256: sha256, header: header)
            let reports = detectors.detect(image: data, system: header.system)
            let candidates = existing == nil && knownDump == nil
                ? try developmentCandidates(fingerprint: fingerprint, naming: naming, reports: reports) : []
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
                toolchainReports: reports,
                imageSHA1: sha1,
                knownDump: knownDump,
                knownFile: knownDumps?.file(sha1: sha1),
                familyGameIDs: familyGameIDs,
                familyTitles: knownDump.flatMap { knownDumps?.family(of: $0).map(\.title) } ?? [],
                baseLineageGameIDs: lineageIDs,
                fingerprint: fingerprint,
                developmentCandidates: candidates
            )
        } catch {
            try? assetStore.removeIfExists(stagedURL.deletingLastPathComponent())
            throw error
        }
    }

    private func lineageGameIDs(of dump: KnownDump) throws -> [UUID] {
        guard let games, let knownDumps else { return [] }
        return try games.fetchGames().filter { game in
            try builds.fetchBuilds(gameID: game.id).contains { build in
                build.baseGameReference.map { knownDumps.matches($0, familyOf: dump) } == true
            }
        }.map(\.id)
    }

    private func developmentCandidates(fingerprint: ImageFingerprint, naming: FilenameMetadata,
                                       reports: [ToolchainDetectionReport]) throws -> [DevelopmentBuildMatcher.Candidate] {
        guard let games else { return [] }
        let imported = try builds.fetchAllBuilds().filter { $0.sourceKind == .importedImage }
        let stored = try fingerprints.fetchFingerprints(imageSHA256s: imported.map(\.imageSHA256))
        let storedReports = try toolchainReports.fetchAllReports()
        let grouped = Dictionary(grouping: imported, by: \.gameID)
        return DevelopmentBuildMatcher.match(arriving: .init(fingerprint: fingerprint, filenameMetadata: naming, reports: reports),
            games: try games.fetchGames().map { game in
                .init(game: game, builds: (grouped[game.id] ?? []).map {
                    .init(fingerprint: stored[$0.imageSHA256], reports: storedReports[$0.id] ?? [])
                })
            })
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

import EmulatorApplication
import Foundation
import ToolchainDetection

public struct ROMImportAnalyzer: Sendable {
    private let builds: any BuildRepository
    private let assetStore: any AssetStore
    private let detectors: ToolchainDetectorRegistry
    private let makeTransactionID: @Sendable () -> UUID

    public init(
        builds: any BuildRepository,
        assetStore: any AssetStore,
        detectors: ToolchainDetectorRegistry = .standard,
        makeTransactionID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.builds = builds
        self.assetStore = assetStore
        self.detectors = detectors
        self.makeTransactionID = makeTransactionID
    }

    public func analyzeROM(at sourceURL: URL, targetGameID: UUID?) throws -> ROMImportAnalysis {
        let transactionID = makeTransactionID()
        let stagedURL = try assetStore.stageCopy(from: sourceURL, transactionID: transactionID)
        do {
            let data = try Data(contentsOf: stagedURL, options: .mappedIfSafe)
            let sha256 = try assetStore.hashFile(at: stagedURL)
            let header = try GBROMHeaderParser.parse(data)
            let existing = try builds.fetchBuild(imageSHA256: sha256)
            return ROMImportAnalysis(
                transactionID: transactionID,
                stagedURL: stagedURL,
                originalFilename: sourceURL.lastPathComponent,
                sha256: sha256,
                byteLength: Int64(data.count),
                header: header,
                filenameMetadata: FilenameMetadataParser.parse(filename: sourceURL.lastPathComponent),
                exactExistingBuildID: existing?.id,
                suggestedGameID: targetGameID ?? existing?.gameID,
                toolchainReports: detectors.detect(image: data, system: header.system)
            )
        } catch {
            try? assetStore.removeIfExists(stagedURL.deletingLastPathComponent())
            throw error
        }
    }
}

import EmulatorApplication
import Foundation
import Importing
import UniformTypeIdentifiers

@MainActor
final class ImportCoordinator {
    let analyzer: ROMImportAnalyzer
    let committer: ImportCommitter
    private let assetStore: any AssetStore

    init(analyzer: ROMImportAnalyzer, committer: ImportCommitter, assetStore: any AssetStore) {
        self.analyzer = analyzer
        self.committer = committer
        self.assetStore = assetStore
    }

    func analyzeROM(at url: URL, targetGameID: UUID? = nil) throws -> ROMImportAnalysis {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try analyzer.analyzeROM(at: url, targetGameID: targetGameID)
    }

    func discard(_ analysis: ROMImportAnalysis) {
        try? assetStore.removeIfExists(analysis.stagedURL.deletingLastPathComponent())
    }
}

extension UTType {
    static let gameBoyROM = UTType(filenameExtension: "gb") ?? .data
    static let gameBoyColorROM = UTType(filenameExtension: "gbc") ?? .data
    static let gameBoySave = UTType(filenameExtension: "sav") ?? .data
    static let ipsPatch = UTType(filenameExtension: "ips") ?? .data
    static let bpsPatch = UTType(filenameExtension: "bps") ?? .data
}

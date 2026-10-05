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
    static let gameBoyROM = UTType(importedAs: "com.thisjustin816.emulator.rom.gb", conformingTo: .data)
    static let gameBoyColorROM = UTType(importedAs: "com.thisjustin816.emulator.rom.gbc", conformingTo: .data)
    static let gameBoySave = UTType(filenameExtension: "sav") ?? .data
    static let ipsPatch = UTType(importedAs: "com.thisjustin816.emulator.patch.ips", conformingTo: .data)
    static let bpsPatch = UTType(importedAs: "com.thisjustin816.emulator.patch.bps", conformingTo: .data)
}

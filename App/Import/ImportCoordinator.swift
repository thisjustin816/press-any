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
    static let gameBoySave = UTType(importedAs: "com.thisjustin816.emulator.save", conformingTo: .data)
    static let ipsPatch = UTType(importedAs: "com.thisjustin816.emulator.patch.ips", conformingTo: .data)
    static let bpsPatch = UTType(importedAs: "com.thisjustin816.emulator.patch.bps", conformingTo: .data)

    /// What the file picker accepts. Another installed app can export its own type for an
    /// extension, and Files then labels the file with that type instead, so the type the system
    /// resolves for each extension is accepted too.
    static let romFileTypes = withResolvedTypes([.gameBoyROM, .gameBoyColorROM], extensions: ["gb", "gbc"])
    static let patchFileTypes = withResolvedTypes([.ipsPatch, .bpsPatch], extensions: ["ips", "bps"])
    /// Battery saves: `.sav`, and `.srm` as RetroArch names them.
    static let saveFileTypes = withResolvedTypes([.gameBoySave], extensions: ["sav", "srm"])
    /// Everything Import Files accepts: ROMs, patches, saves, and zips holding them.
    static let importFileTypes = romFileTypes + patchFileTypes + saveFileTypes
        + withResolvedTypes([.zip], extensions: ["zip"])

    private static func withResolvedTypes(_ own: [UTType], extensions: [String]) -> [UTType] {
        var types = own
        for type in extensions.compactMap({ UTType(filenameExtension: $0) }) where !types.contains(type) {
            types.append(type)
        }
        return types
    }
}

import EmulatorDomain
import Foundation
import Importing

struct PatchMetadataProvenance {
    let naming: [FilenameMetadata]
    let offeredMetadata: BuildImportMetadata
    let offeredName: String

    init(input: CreatePatchedBuild.Input, gameTitle: String) {
        naming = input.patches.map { FilenameMetadataParser.parse(filename: $0.url.lastPathComponent) }
        offeredMetadata = naming.count == 1 ? BuildNaming.patchMetadata(for: naming[0]) : BuildImportMetadata()
        if let suggested = input.suggestedDisplayName {
            offeredName = suggested
        } else if naming.count == 1 {
            offeredName = BuildNaming.patchBuildName(for: naming[0], gameTitle: gameTitle)
        } else {
            offeredName = input.patches.map { $0.url.deletingPathExtension().lastPathComponent }.joined(separator: " + ")
        }
    }

    func buildRows(build: Build, game: Game, inheritedTitle: MetadataProvenance?, at date: Date) -> [MetadataProvenance] {
        MetadataField.allCases.filter { $0 != .title }.compactMap { field in
            let value = field.value(in: build)
            let offered: String?
            switch field {
            case .displayName: offered = offeredName
            case .baseTitle: offered = offeredMetadata.baseTitle ?? game.primaryTitle
            default: offered = offeredMetadata.value(for: field)
            }
            guard value != nil || offered != nil else { return nil }
            if field == .baseTitle, offeredMetadata.baseTitle == nil, value == game.primaryTitle {
                // An inherited title without provenance remains unrecorded on its Build.
                guard let inheritedTitle else { return nil }
                return MetadataProvenance(field: field, source: inheritedTitle.source, confidence: inheritedTitle.confidence,
                    providedValue: game.primaryTitle, recordedAt: date)
            }
            let edited = value != offered
            return MetadataProvenance(field: field, source: edited ? .player : .patch,
                confidence: edited ? nil : naming.first.map { MetadataConfidence($0.confidence) },
                providedValue: offered ?? value, recordedAt: date)
        }
    }

    func titleRow(value: String, previous: MetadataProvenance?, at date: Date) -> MetadataProvenance {
        let offered = offeredMetadata.hackTitle
        guard value == offered else {
            return previous?.playerOverride(recordedAt: date)
                ?? MetadataProvenance(field: .title, source: .player, providedValue: offered ?? value, recordedAt: date)
        }
        return MetadataProvenance(field: .title, source: .patch,
            confidence: naming.first.map { MetadataConfidence($0.confidence) }, providedValue: offered, recordedAt: date)
    }
}

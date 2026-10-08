import EmulatorDomain
import Foundation

extension MetadataConfidence {
    public init(_ confidence: NamingSuggestionConfidence) {
        switch confidence {
        case .low: self = .low
        case .medium: self = .medium
        case .high: self = .high
        }
    }
}

extension BuildImportMetadata {
    public func value(for field: MetadataField) -> String? {
        switch field {
        case .title, .displayName: nil
        case .region: region
        case .language: language
        case .revision: revision
        case .versionString: versionString
        case .baseTitle: baseTitle
        case .hackTitle: hackTitle
        case .author: author
        case .translation: translation
        case .status: status
        }
    }
}

extension ROMImportPlan {
    public func titleProvenance(value: String, proposed: Bool = false, at date: Date) -> MetadataProvenance {
        let naming = analysis.filenameMetadata
        let suggestedTitle = naming.suggestedTitle.isEmpty ? analysis.header.title : naming.suggestedTitle
        let offered: String?
        if proposed {
            offered = proposedGameTitleIsPlayers ? naming.buildMetadata.hackTitle ?? suggestedTitle : proposedGameTitle
        } else {
            offered = suggestedTitle
        }
        let isPlayer = proposed ? proposedGameTitleIsPlayers : hasPlayerTitle || value != offered
        let source: MetadataSource
        if analysis.knownDump != nil { source = .noIntro }
        else { source = naming.suggestedTitle.isEmpty ? .romHeader : .filename }
        return MetadataProvenance(field: .title, source: isPlayer ? .player : source,
            confidence: isPlayer ? nil : analysis.metadataConfidence(for: source),
            providedValue: offered, recordedAt: date)
    }

    public func buildProvenance(at date: Date) -> [MetadataProvenance] {
        var offered = BuildImportMetadata(analysis: analysis)
        if let baseGameReference { offered.baseTitle = baseGameReference.title }
        if baseGameReference != nil, metadata.hackTitle != nil, offered.hackTitle == nil {
            offered.hackTitle = analysis.filenameMetadata.suggestedTitle
        }
        return MetadataField.allCases.filter { $0 != .title }.compactMap { field in
            let offeredValue = field == .displayName ? suggestedBuildDisplayName : offered.value(for: field)
            let value = field == .displayName ? buildDisplayName : metadata.value(for: field)
            guard offeredValue != nil || value != nil else { return nil }
            let isPlayer = value != offeredValue
            let fromHeader = field == .revision && analysis.filenameMetadata.buildMetadata.revision == nil
                && offeredValue != nil
            let source: MetadataSource
            if field == .baseTitle, let baseGameReference {
                source = baseGameReference.releaseName == nil ? .player : .noIntro
            } else if fromHeader {
                source = .romHeader
            } else {
                source = analysis.knownDump != nil ? .noIntro : .filename
            }
            return MetadataProvenance(field: field, source: isPlayer ? .player : source,
                confidence: isPlayer ? nil : analysis.metadataConfidence(for: source),
                providedValue: offeredValue ?? value, recordedAt: date)
        }
    }
}

extension ROMImportAnalysis {
    func metadataConfidence(for source: MetadataSource) -> MetadataConfidence? {
        switch source {
        case .noIntro: .high
        case .filename: MetadataConfidence(filenameMetadata.confidence)
        case .romHeader, .patch, .player: nil
        }
    }
}

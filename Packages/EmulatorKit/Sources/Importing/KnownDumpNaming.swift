import Foundation
import GameIdentity

extension FilenameMetadata {
    /// The naming a known dump gets from the fields No-Intro records apart from its name, so
    /// nothing has to be read back out of the canonical name. Aftermarket and Unl stay out of the
    /// status and the Build name: every new homebrew release carries both, so they tell nothing
    /// about a Build.
    init(knownDump dump: KnownDump, fileExtension: String) {
        let metadata = BuildImportMetadata(knownDump: dump)
        let kind: FilenameReleaseKind = metadata.versionString == nil && dump.status == nil ? .standard : .development
        let filename = fileExtension.isEmpty ? dump.name : "\(dump.name).\(fileExtension)"
        let parsed = FilenameMetadataParser.parse(filename: filename)
        self.init(
            originalBaseName: dump.name,
            suggestedTitle: dump.title,
            suggestedBuildName: FilenameMetadataParser.buildName(for: kind, metadata: metadata),
            normalizedFilename: filename,
            releaseKind: kind,
            confidence: .high,
            parentheticalGroups: parsed.parentheticalGroups,
            bracketGroups: parsed.bracketGroups,
            unknownGroups: [],
            buildMetadata: metadata
        )
    }
}

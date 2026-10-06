import Foundation
import GameIdentity

extension FilenameMetadata {
    /// The naming a known dump gets from the fields No-Intro records apart from its name, so
    /// nothing has to be read back out of the canonical name. Aftermarket and Unl stay out of the
    /// status and the Build name: every new homebrew release carries both, so they tell nothing
    /// about a Build.
    init(knownDump dump: KnownDump, fileExtension: String) {
        var revision: String?
        var versionString: String?
        if let version = dump.version {
            if version.lowercased().hasPrefix("rev ") {
                revision = String(version.dropFirst(4))
            } else if version.lowercased().hasPrefix("v") {
                versionString = String(version.dropFirst())
            } else {
                versionString = version
            }
        }
        // No-Intro writes "En,Fr"; Build Details spell it as the filename parser does, "En, Fr".
        let language = dump.languages.map {
            $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: ", ")
        }
        let metadata = BuildImportMetadata(
            region: dump.region,
            language: language,
            revision: revision,
            versionString: versionString,
            status: dump.status
        )
        let kind: FilenameReleaseKind = versionString == nil && dump.status == nil ? .standard : .development
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

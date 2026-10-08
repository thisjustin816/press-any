import EmulatorDomain
import Foundation
import GameIdentity

/// Reviewable presentation metadata, independent of the image's immutable identity.
public struct BuildImportMetadata: Equatable, Sendable {
    public var region: String?
    public var language: String?
    public var revision: String?
    public var versionString: String?
    public var baseTitle: String?
    public var hackTitle: String?
    public var author: String?
    public var translation: String?
    public var status: String?

    public init(
        region: String? = nil,
        language: String? = nil,
        revision: String? = nil,
        versionString: String? = nil,
        baseTitle: String? = nil,
        hackTitle: String? = nil,
        author: String? = nil,
        translation: String? = nil,
        status: String? = nil
    ) {
        func cleaned(_ value: String?) -> String? {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return value
        }
        self.region = cleaned(region)
        self.language = cleaned(language)
        self.revision = cleaned(revision)
        self.versionString = cleaned(versionString)
        self.baseTitle = cleaned(baseTitle)
        self.hackTitle = cleaned(hackTitle)
        self.author = cleaned(author)
        self.translation = cleaned(translation)
        self.status = cleaned(status)
    }

    public init(analysis: ROMImportAnalysis) {
        if let dump = analysis.knownDump {
            self.init(knownDump: dump)
            return
        }
        let filename = analysis.filenameMetadata.buildMetadata
        self.init(
            region: filename.region,
            language: filename.language,
            revision: filename.revision ?? (analysis.header.revisionNumber > 0 ? String(analysis.header.revisionNumber) : nil),
            versionString: filename.versionString,
            baseTitle: filename.baseTitle,
            hackTitle: filename.hackTitle,
            author: filename.author,
            translation: filename.translation,
            status: filename.status
        )
    }

    public var versionSortKey: String? {
        Build.versionSortKey(for: versionString)
    }
}

extension BuildImportMetadata {
    public init(knownDump dump: KnownDump) {
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
        self.init(
            region: dump.region,
            language: language,
            revision: revision,
            versionString: versionString,
            status: dump.status
        )
    }
}

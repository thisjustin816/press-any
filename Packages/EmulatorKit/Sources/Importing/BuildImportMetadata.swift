import Foundation

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

    /// Fixed-width components let SQLite sort numeric releases as text.
    public var versionSortKey: String? {
        guard let versionString else { return nil }
        let parts = versionString.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count), parts.allSatisfy({
            !$0.isEmpty && $0.count <= 10 && $0.utf8.allSatisfy { (48...57).contains($0) }
        }) else { return nil }
        let padded = parts.map { String(repeating: "0", count: 10 - $0.count) + $0 }
        return (padded + Array(repeating: String(repeating: "0", count: 10), count: 4 - parts.count)).joined(separator: ".")
    }
}

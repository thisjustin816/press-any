import Foundation

/// Reviewable presentation metadata, independent of the image's immutable identity.
public struct BuildImportMetadata: Equatable, Sendable {
    public var region: String?
    public var language: String?
    public var revision: String?
    public var versionString: String?

    public init(region: String? = nil, language: String? = nil, revision: String? = nil, versionString: String? = nil) {
        func cleaned(_ value: String?) -> String? {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return value
        }
        self.region = cleaned(region)
        self.language = cleaned(language)
        self.revision = cleaned(revision)
        self.versionString = cleaned(versionString)
    }

    public init(analysis: ROMImportAnalysis) {
        let filename = analysis.filenameMetadata.buildMetadata
        self.init(
            region: filename.region,
            language: filename.language,
            revision: filename.revision ?? (analysis.header.revisionNumber > 0 ? String(analysis.header.revisionNumber) : nil),
            versionString: filename.versionString
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

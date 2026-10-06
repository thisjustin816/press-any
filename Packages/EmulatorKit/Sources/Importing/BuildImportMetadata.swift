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

    /// Fixed-width components let SQLite sort numeric releases as text. Prereleases sort before
    /// their release, as in semver: "~" marks a release and follows every identifier character, and
    /// numeric prerelease parts are padded so "beta.9" comes before "beta.10". Build metadata such
    /// as "+deferred6" follows, so builds of one version sort together.
    public var versionSortKey: String? {
        guard let versionString else { return nil }
        let buildStart = versionString.firstIndex(of: "+") ?? versionString.endIndex
        let build = versionString[buildStart...]
        let main = versionString[..<buildStart]
        let prereleaseStart = main.firstIndex(of: "-") ?? main.endIndex
        let prerelease = main[prereleaseStart...].dropFirst()
        let parts = main[..<prereleaseStart].split(separator: ".", omittingEmptySubsequences: false)
        func isNumber(_ part: Substring) -> Bool {
            !part.isEmpty && part.count <= 10 && part.utf8.allSatisfy { (48...57).contains($0) }
        }
        func padded(_ part: Substring) -> String { String(repeating: "0", count: 10 - part.count) + part }
        guard (1...4).contains(parts.count), parts.allSatisfy(isNumber) else { return nil }
        let core = (parts.map(padded) + Array(repeating: String(repeating: "0", count: 10), count: 4 - parts.count))
            .joined(separator: ".")
        let precedence = prerelease.isEmpty
            ? "~"
            : "-" + prerelease.split(separator: ".", omittingEmptySubsequences: false)
                .map { isNumber($0) ? padded($0) : String($0) }
                .joined(separator: ".")
        return core + precedence + build
    }
}

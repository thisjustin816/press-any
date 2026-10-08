import Foundation

extension Build {
    /// Fixed-width components let SQLite sort numeric releases as text. Prereleases sort before
    /// their release, as in semver: "~" marks a release and follows every identifier character, and
    /// numeric prerelease parts are padded so "beta.9" comes before "beta.10". Build metadata such
    /// as "+deferred6" follows, so builds of one version sort together.
    public static func versionSortKey(for versionString: String?) -> String? {
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

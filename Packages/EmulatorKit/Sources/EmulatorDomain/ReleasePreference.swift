import Foundation

public struct ReleaseTitle: Equatable, Sendable {
    public let title: String
    public let region: String?
    public let language: String?

    public init(title: String, region: String?, language: String?) {
        self.title = title
        self.region = region
        self.language = language
    }
}

public struct ReleasePreference: Codable, Equatable, Sendable {
    public var regions: [String]
    public var languages: [String]

    public init(regions: [String] = ["USA", "Europe", "Japan"], languages: [String] = ["En", "Fr", "De", "Es", "It", "Ja"]) {
        self.regions = regions
        self.languages = languages
    }

    public func prefers(region: String?, language: String?, overRegion: String?, overLanguage: String?) -> Bool {
        let lhs = rank(region, order: regions), rhs = rank(overRegion, order: regions)
        if lhs != rhs { return lhs < rhs }
        return rank(language, order: languages) < rank(overLanguage, order: languages)
    }

    /// Equal ranks keep the current title when available, otherwise the first release wins.
    public func preferredTitle(among releases: [ReleaseTitle], currentTitle: String) -> ReleaseTitle? {
        let ordered = releases.filter { $0.title == currentTitle } + releases.filter { $0.title != currentTitle }
        guard var best = ordered.first else { return nil }
        for release in ordered.dropFirst() {
            if prefers(region: release.region, language: release.language, overRegion: best.region, overLanguage: best.language) {
                best = release
            }
        }
        return best
    }

    private func rank(_ value: String?, order: [String]) -> Int {
        let tags = (value ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        if tags.contains("world") { return 0 }
        return order.firstIndex { tags.contains($0.lowercased()) } ?? order.count
    }
}

import Foundation

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

    private func rank(_ value: String?, order: [String]) -> Int {
        let tags = (value ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        if tags.contains("world") { return 0 }
        return order.firstIndex { tags.contains($0.lowercased()) } ?? order.count
    }
}

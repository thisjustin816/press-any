import Foundation

public struct FilenameMetadata: Equatable, Sendable {
    public let originalBaseName: String
    public let suggestedTitle: String
    public let parentheticalGroups: [String]
    public let bracketGroups: [String]
    public let buildMetadata: BuildImportMetadata

    public init(
        originalBaseName: String,
        suggestedTitle: String,
        parentheticalGroups: [String],
        bracketGroups: [String],
        buildMetadata: BuildImportMetadata = BuildImportMetadata()
    ) {
        self.originalBaseName = originalBaseName
        self.suggestedTitle = suggestedTitle
        self.parentheticalGroups = parentheticalGroups
        self.bracketGroups = bracketGroups
        self.buildMetadata = buildMetadata
    }
}

public enum FilenameMetadataParser {
    public static func parse(filename: String) -> FilenameMetadata {
        let base = (filename as NSString).deletingPathExtension
        let parenthetical = captures(in: base, pattern: #"\(([^()]*)\)"#)
        let bracketed = captures(in: base, pattern: #"\[([^\[\]]*)\]"#)
        let metadataStart = [base.firstIndex(of: "("), base.firstIndex(of: "[")]
            .compactMap { $0 }
            .min()
        let rawTitle = metadataStart.map { String(base[..<$0]) } ?? base
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        // Only recognize explicit tags. Raw groups remain available for future richer parsing.
        let regions: Set<String> = ["World", "USA", "Europe", "Japan", "Australia", "Asia", "Canada", "China", "France", "Germany", "Italy", "Korea", "Netherlands", "Spain", "Sweden", "Taiwan", "United Kingdom", "Brazil"]
        let languages: Set<String> = ["En", "Ja", "Fr", "De", "Es", "It", "Nl", "Pt", "Sv", "Da", "No", "Fi", "Ko", "Zh", "Ru", "Pl", "Cs", "Hu", "Tr"]
        var region: String?
        var language: String?
        var revision: String?
        var version: String?
        for group in parenthetical + bracketed {
            let tokens = group.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if !tokens.isEmpty && tokens.allSatisfy({ regions.contains($0) }) {
                region = region ?? tokens.joined(separator: ", ")
            } else if !tokens.isEmpty && tokens.allSatisfy({ languages.contains($0) }) {
                language = language ?? tokens.joined(separator: ", ")
            }
            revision = revision ?? captures(in: group, pattern: #"(?i)^\s*Rev(?:ision)?\s+([0-9]+|[A-Z])\s*$"#).first
            version = version ?? captures(in: group, pattern: #"(?i)^\s*v(?:ersion)?\s*([0-9]+(?:\.[0-9]+){0,3})\s*$"#).first
        }
        // Homebrew releases commonly put an explicit numeric version at the end of the title.
        let cleanTitle: String
        if let suffixRange = title.range(of: #"(?i)\s+v[0-9]+(?:\.[0-9]+){0,3}$"#, options: .regularExpression) {
            let suffix = title[suffixRange].trimmingCharacters(in: .whitespacesAndNewlines)
            version = version ?? String(suffix.dropFirst())
            cleanTitle = String(title[..<suffixRange.lowerBound])
        } else {
            cleanTitle = title
        }

        return FilenameMetadata(
            originalBaseName: base,
            suggestedTitle: cleanTitle.isEmpty ? base : cleanTitle,
            parentheticalGroups: parenthetical,
            bracketGroups: bracketed,
            buildMetadata: BuildImportMetadata(region: region, language: language, revision: revision, versionString: version)
        )
    }

    private static func captures(in value: String, pattern: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.matches(in: value, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let captureRange = Range(match.range(at: 1), in: value) else { return nil }
            return String(value[captureRange])
        }
    }
}

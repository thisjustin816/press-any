import Foundation

public struct FilenameMetadata: Equatable, Sendable {
    public let originalBaseName: String
    public let suggestedTitle: String
    public let parentheticalGroups: [String]
    public let bracketGroups: [String]

    public init(
        originalBaseName: String,
        suggestedTitle: String,
        parentheticalGroups: [String],
        bracketGroups: [String]
    ) {
        self.originalBaseName = originalBaseName
        self.suggestedTitle = suggestedTitle
        self.parentheticalGroups = parentheticalGroups
        self.bracketGroups = bracketGroups
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

        return FilenameMetadata(
            originalBaseName: base,
            suggestedTitle: title.isEmpty ? base : title,
            parentheticalGroups: parenthetical,
            bracketGroups: bracketed
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

import Foundation

public enum FilenameReleaseKind: String, Equatable, Sendable {
    case standard
    case development
    case romHack
}

public enum NamingSuggestionConfidence: String, Equatable, Sendable {
    case low
    case medium
    case high

    public var displayName: String { rawValue.capitalized }
}

public struct FilenameMetadata: Equatable, Sendable {
    public let originalBaseName: String
    public let suggestedTitle: String
    public let suggestedBuildName: String
    public let normalizedFilename: String
    public let releaseKind: FilenameReleaseKind
    public let confidence: NamingSuggestionConfidence
    public let parentheticalGroups: [String]
    public let bracketGroups: [String]
    public let unknownGroups: [String]
    public let buildMetadata: BuildImportMetadata

    public init(
        originalBaseName: String,
        suggestedTitle: String,
        suggestedBuildName: String,
        normalizedFilename: String,
        releaseKind: FilenameReleaseKind,
        confidence: NamingSuggestionConfidence,
        parentheticalGroups: [String],
        bracketGroups: [String],
        unknownGroups: [String],
        buildMetadata: BuildImportMetadata = BuildImportMetadata()
    ) {
        self.originalBaseName = originalBaseName
        self.suggestedTitle = suggestedTitle
        self.suggestedBuildName = suggestedBuildName
        self.normalizedFilename = normalizedFilename
        self.releaseKind = releaseKind
        self.confidence = confidence
        self.parentheticalGroups = parentheticalGroups
        self.bracketGroups = bracketGroups
        self.unknownGroups = unknownGroups
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
        var baseTitle: String?
        var hackTitle: String?
        var author: String?
        var translation: String?
        var status: String?
        var isHack = false
        var recognizedGroups = Set<String>()
        for group in parenthetical + bracketed {
            let tokens = group.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if !tokens.isEmpty && tokens.allSatisfy({ regions.contains($0) }) {
                region = region ?? tokens.joined(separator: ", ")
                recognizedGroups.insert(group)
            } else if !tokens.isEmpty && tokens.allSatisfy({ languages.contains($0) }) {
                language = language ?? tokens.joined(separator: ", ")
                recognizedGroups.insert(group)
            }
            if let value = captures(in: group, pattern: #"(?i)^\s*Rev(?:ision)?\s+([0-9]+|[A-Z])\s*$"#).first {
                revision = revision ?? value
                recognizedGroups.insert(group)
            }
            if let value = captures(in: group, pattern: #"(?i)^\s*v(?:ersion)?\s*([0-9]+(?:\.[0-9]+){0,3})\s*$"#).first {
                version = version ?? value
                recognizedGroups.insert(group)
            }
            if let value = firstCapture(in: group, patterns: [
                #"(?i)^\s*Base(?:\s+(?:Game|Title))?\s*[:\-]\s*(.+?)\s*$"#,
            ]) {
                baseTitle = baseTitle ?? value
                isHack = true
                recognizedGroups.insert(group)
            }
            if let value = firstCapture(in: group, patterns: [
                #"(?i)^\s*Hack(?:\s+Title)?\s*[:\-]\s*(.+?)\s*$"#,
            ]) {
                hackTitle = hackTitle ?? value
                isHack = true
                recognizedGroups.insert(group)
            }
            if let value = firstCapture(in: group, patterns: [
                #"(?i)^\s*(?:Hack(?:ed)?\s+)?by\s+(.+?)\s*$"#,
                #"(?i)^\s*Author(?:s)?\s*[:\-]\s*(.+?)\s*$"#,
            ]) {
                author = author ?? value
                if group.range(of: #"(?i)^\s*Hack(?:ed)?\s+by\s+"#, options: .regularExpression) != nil {
                    isHack = true
                }
                recognizedGroups.insert(group)
            }
            if let value = firstCapture(in: group, patterns: [
                #"(?i)^\s*Translation(?:\s+Language)?\s*[:\-]\s*(.+?)\s*$"#,
                #"(?i)^\s*(.+?)\s+Translation\s*$"#,
                #"(?i)^\s*T[+\-]([A-Za-z]{2,3})\s*$"#,
            ]) {
                translation = translation ?? value
                isHack = true
                recognizedGroups.insert(group)
            }
            if let value = canonicalStatus(group) {
                status = status ?? value
                recognizedGroups.insert(group)
            }
            if group.range(
                of: #"(?i)^\s*(?:(?:ROM\s+)?Hack|h[0-9]*)\s*$"#,
                options: .regularExpression
            ) != nil {
                isHack = true
                recognizedGroups.insert(group)
            }
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

        if isHack, baseTitle == nil, hackTitle == nil,
           let separator = cleanTitle.range(of: " - ") {
            baseTitle = String(cleanTitle[..<separator.lowerBound]).trimmingCharacters(in: .whitespaces)
            hackTitle = String(cleanTitle[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        if isHack {
            baseTitle = baseTitle ?? cleanTitle
            hackTitle = hackTitle ?? cleanTitle
        }

        let metadata = BuildImportMetadata(
            region: region,
            language: language,
            revision: revision,
            versionString: version,
            baseTitle: baseTitle,
            hackTitle: hackTitle,
            author: author,
            translation: translation,
            status: status
        )
        let releaseKind: FilenameReleaseKind = isHack
            ? .romHack
            : (version == nil && status == nil ? .standard : .development)
        let suggestedTitle = (hackTitle ?? cleanTitle).isEmpty ? base : (hackTitle ?? cleanTitle)
        let unknownGroups = (parenthetical + bracketed).filter { !recognizedGroups.contains($0) }
        let confidence: NamingSuggestionConfidence
        if releaseKind == .standard, metadata == BuildImportMetadata() {
            confidence = .low
        } else if isHack, baseTitle == hackTitle {
            confidence = .medium
        } else {
            confidence = .high
        }
        let suggestedBuildName = buildName(for: releaseKind, metadata: metadata)
        let normalizedFilename = canonicalFilename(
            fileExtension: (filename as NSString).pathExtension.lowercased(),
            title: cleanTitle,
            metadata: metadata,
            unknownGroups: unknownGroups
        )

        return FilenameMetadata(
            originalBaseName: base,
            suggestedTitle: suggestedTitle,
            suggestedBuildName: suggestedBuildName,
            normalizedFilename: normalizedFilename,
            releaseKind: releaseKind,
            confidence: confidence,
            parentheticalGroups: parenthetical,
            bracketGroups: bracketed,
            unknownGroups: unknownGroups,
            buildMetadata: metadata
        )
    }

    private static func buildName(for kind: FilenameReleaseKind, metadata: BuildImportMetadata) -> String {
        var parts: [String] = []
        if let version = metadata.versionString { parts.append("v\(version)") }
        if let revision = metadata.revision { parts.append("Rev \(revision)") }
        if let status = metadata.status { parts.append(status) }
        if let translation = metadata.translation { parts.append("\(translation) Translation") }
        if parts.isEmpty, let region = metadata.region { parts.append(region) }
        if parts.isEmpty { return kind == .romHack ? "Hack" : "Original" }
        return parts.joined(separator: " · ")
    }

    public static func canonicalFilename(
        fileExtension: String,
        title: String,
        metadata: BuildImportMetadata,
        unknownGroups: [String]
    ) -> String {
        let normalizedTitle: String
        if let baseTitle = metadata.baseTitle,
           let hackTitle = metadata.hackTitle,
           baseTitle.localizedCaseInsensitiveCompare(hackTitle) != .orderedSame {
            normalizedTitle = "\(baseTitle) - \(hackTitle)"
        } else {
            normalizedTitle = title
        }
        var groups: [String] = []
        if let region = metadata.region { groups.append("(\(region))") }
        if let language = metadata.language { groups.append("(\(language))") }
        if let revision = metadata.revision { groups.append("(Rev \(revision))") }
        if let version = metadata.versionString { groups.append("[v\(version)]") }
        if let author = metadata.author { groups.append("[by \(author)]") }
        if let translation = metadata.translation { groups.append("[\(translation) Translation]") }
        if let status = metadata.status { groups.append("[\(status)]") }
        groups.append(contentsOf: unknownGroups.map { "[\($0)]" })
        let stem = ([normalizedTitle] + groups).filter { !$0.isEmpty }.joined(separator: " ")
        return fileExtension.isEmpty ? stem : "\(stem).\(fileExtension)"
    }

    private static func canonicalStatus(_ value: String) -> String? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "alpha": return "Alpha"
        case "beta": return "Beta"
        case "demo": return "Demo"
        case "prototype", "proto": return "Prototype"
        case "preview": return "Preview"
        case "release candidate", "rc": return "RC"
        case "final": return "Final"
        default: return nil
        }
    }

    private static func firstCapture(in value: String, patterns: [String]) -> String? {
        patterns.lazy.compactMap { captures(in: value, pattern: $0).first }.first
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

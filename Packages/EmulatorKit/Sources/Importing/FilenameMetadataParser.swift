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
    /// A semver prerelease ("-beta.3") or build ("+deferred6") suffix, kept as part of the version.
    static let versionSuffixPattern = #"(?:-[0-9A-Za-z][0-9A-Za-z.-]*)?(?:\+[0-9A-Za-z][0-9A-Za-z.-]*)?"#
    /// One to four dotted numbers, as in "1", "1.1" or "0.2.0", with an optional semver suffix.
    static let versionPattern = #"[0-9]+(?:\.[0-9]+){0,3}"# + versionSuffixPattern

    public static func parse(filename: String) -> FilenameMetadata {
        let decodedFilename = filename.removingPercentEncoding ?? filename
        let base = (decodedFilename as NSString).deletingPathExtension
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
            if let parts = firstMatchGroups(
                in: group,
                pattern: #"(?i)^\s*(.+?\b(?:hack|patch|fix|translation|mod)\b.*?)\s+by\s+(.+?)\s+v("# + versionPattern + #")\s*$"#
            ), parts.count == 3 {
                hackTitle = hackTitle ?? parts[0]
                author = author ?? parts[1]
                version = version ?? parts[2]
                isHack = true
                recognizedGroups.insert(group)
                continue
            }
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
            // Retail revisions are a number or a letter. Homebrew uses "Rev 0.2.0" for its version.
            if let value = captures(in: group, pattern: #"(?i)^\s*Rev(?:ision)?\s+([0-9]+\.[0-9]+(?:\.[0-9]+){0,2}"# + versionSuffixPattern + #")\s*$"#).first {
                version = version ?? value
                recognizedGroups.insert(group)
            }
            if let value = captures(in: group, pattern: #"(?i)^\s*v(?:ersion)?\s*("# + versionPattern + #")\s*$"#).first {
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
            if group.range(of: #"(?i)^\s*(?:Aftermarket|Unl)\s*$"#, options: .regularExpression) != nil {
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
        var cleanTitle: String
        if let suffixRange = title.range(of: #"(?i)\s+v"# + versionPattern + #"$"#, options: .regularExpression) {
            let suffix = title[suffixRange].trimmingCharacters(in: .whitespacesAndNewlines)
            version = version ?? String(suffix.dropFirst())
            cleanTitle = String(title[..<suffixRange.lowerBound])
        } else {
            cleanTitle = title
        }
        // A version word mid-name, as in "Serve-Sisters-Coop-v5-Stability" or
        // "match-land-live-0.3.0+live1": the words after it describe the variant.
        if version == nil, let stamp = versionStamp(in: cleanTitle) {
            version = stamp.version
            status = status ?? stamp.variant.map { canonicalStatus($0) ?? $0 }
            cleanTitle = stamp.title
        }
        // Builds from game jams and nightlies are often stamped with a date, as in
        // "AeonMetalFighters_20261006_classic". The date becomes the version and the words after
        // it describe the variant.
        if version == nil, let stamp = dateStamp(in: cleanTitle) {
            version = stamp.version
            status = status ?? stamp.variant
            cleanTitle = stamp.title
        }
        if !cleanTitle.contains(" ") {
            cleanTitle = spacedTitle(cleanTitle)
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
            fileExtension: (decodedFilename as NSString).pathExtension.lowercased(),
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

    static func buildName(for kind: FilenameReleaseKind, metadata: BuildImportMetadata) -> String {
        var parts: [String] = []
        if let version = metadata.versionString {
            parts.append(isDateVersion(version) ? version.replacingOccurrences(of: ".", with: "-") : "v\(version)")
        }
        if let revision = metadata.revision { parts.append("Rev \(revision)") }
        if let status = metadata.status { parts.append(status) }
        if let translation = metadata.translation { parts.append("\(translation) Translation") }
        if parts.isEmpty, let region = metadata.region { parts.append(region) }
        if parts.isEmpty { return kind == .romHack ? "Hack" : "Original" }
        return parts.joined(separator: " · ")
    }

    /// A date version, "2026.10.06", reads as a date in a Build name: "2026-10-06".
    static func isDateVersion(_ version: String) -> Bool {
        version.range(of: #"^(?:19|20)[0-9]{2}\.(?:0[1-9]|1[0-2])\.(?:0[1-9]|[12][0-9]|3[01])$"#, options: .regularExpression) != nil
    }

    /// Words an all-lowercase name keeps in capitals: "mole_mania_dx" is "Mole Mania DX".
    private static let uppercaseWords: Set<String> = ["dx", "gb", "gbc", "sgb", "rpg", "ii", "iii", "iv"]

    private static func capitalized(_ word: String) -> String {
        uppercaseWords.contains(word) ? word.uppercased() : word.prefix(1).uppercased() + word.dropFirst()
    }

    /// Spaces out a name with no spaces, as homebrew downloads are often named: underscores become
    /// spaces, camel case splits ("MoonGarden", "GBStudioDemo"), and an all-lowercase name is
    /// capitalized. Hyphens stay, so "Pac-Man" keeps its title, and a lone lowercase letter stays
    /// joined, so "iPhone" isn't split.
    private static func spacedTitle(_ title: String) -> String {
        var words: [String] = []
        for part in title.split(separator: "_") {
            let characters = Array(part)
            var word = ""
            for (index, character) in characters.enumerated() {
                let previous = index > 0 ? characters[index - 1] : nil
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                let startsWord = character.isUppercase && word.count > 1 && (
                    previous?.isLowercase == true
                        || (previous?.isUppercase == true && next?.isLowercase == true)
                )
                if startsWord {
                    words.append(word)
                    word = ""
                }
                word.append(character)
            }
            if !word.isEmpty { words.append(word) }
        }
        if title.allSatisfy({ !$0.isUppercase }) {
            words = words.map(capitalized)
        }
        return words.joined(separator: " ")
    }

    /// A "v" version word after at least one title word, separated by spaces or underscores, or by
    /// hyphens in a name that has no spaces, so "R-Type v2" keeps its title. The title words are
    /// joined with spaces, and the words after the version are the variant.
    private static func versionStamp(in title: String) -> (title: String, version: String, variant: String?)? {
        let splitsHyphens = !title.contains(" ")
        let words = title.split(whereSeparator: { $0 == " " || $0 == "_" || (splitsHyphens && $0 == "-") })
            .map(String.init)
        guard words.count >= 2 else { return nil }
        // A bare number needs a dot to count, so "Mega Man 2" keeps its 2.
        let bareVersion = #"^([0-9]+(?:\.[0-9]+){1,3}"# + versionSuffixPattern + #")$"#
        for index in stride(from: words.count - 1, through: 1, by: -1) {
            guard let value = captures(in: words[index], pattern: #"(?i)^v("# + versionPattern + #")$"#).first
                ?? captures(in: words[index], pattern: bareVersion).first
            else { continue }
            var titleWords = Array(words[..<index])
            // An all-lowercase joined name, as in "match-land-live-0.3.0", reads better capitalized.
            if title.allSatisfy({ !$0.isUppercase }) {
                titleWords = titleWords.map(capitalized)
            }
            // In a joined name the separators stand in for the version's dots: "mole_mania_dx_v1_3" is 1.3.
            var version = value
            var variantStart = index + 1
            if !title.contains(" "), value.allSatisfy(\.isNumber) {
                while variantStart < words.count, variantStart - index < 4,
                      words[variantStart].count <= 3, words[variantStart].allSatisfy(\.isNumber) {
                    version += "." + words[variantStart]
                    variantStart += 1
                }
            }
            let variant = words[variantStart...].joined(separator: " ")
            return (titleWords.joined(separator: " "), version, variant.isEmpty ? nil : variant)
        }
        return nil
    }

    /// A date stamp after at least one title word, as "20261006" or "2026-10-06", separated by
    /// spaces or underscores. Words after it are the variant.
    private static func dateStamp(in title: String) -> (title: String, version: String, variant: String?)? {
        let words = title.split(whereSeparator: { $0 == "_" || $0 == " " }).map(String.init)
        guard words.count >= 2 else { return nil }
        for index in stride(from: words.count - 1, through: 1, by: -1) {
            let digits = words[index].replacingOccurrences(of: "-", with: "")
            guard digits.count == 8, digits.allSatisfy(\.isNumber),
                  words[index].count == 8 || words[index].range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil
            else { continue }
            let version = "\(digits.prefix(4)).\(digits.dropFirst(4).prefix(2)).\(digits.suffix(2))"
            guard isDateVersion(version) else { continue }
            let variant = words[(index + 1)...].joined(separator: " ")
            return (words[..<index].joined(separator: " "), version, variant.isEmpty ? nil : variant)
        }
        return nil
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
        if let parts = firstMatchGroups(
            in: value,
            pattern: #"(?i)^\s*(alpha|beta|demo|prototype|proto|preview|release candidate|rc|final)\s+([0-9]+)\s*$"#
        ), let status = canonicalStatus(parts[0]) {
            return "\(status) \(parts[1])"
        }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "alpha": return "Alpha"
        case "beta": return "Beta"
        case "demo": return "Demo"
        case "prototype", "proto": return "Prototype"
        case "preview": return "Preview"
        case "release candidate", "rc": return "RC"
        case "final": return "Final"
        case "sample": return "Sample"
        case "kiosk": return "Kiosk"
        case "debug": return "Debug"
        default: return nil
        }
    }

    private static func firstCapture(in value: String, patterns: [String]) -> String? {
        patterns.lazy.compactMap { captures(in: value, pattern: $0).first }.first
    }

    private static func firstMatchGroups(in value: String, pattern: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = expression.firstMatch(in: value, range: range) else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            guard let captureRange = Range(match.range(at: index), in: value) else { return nil }
            return String(value[captureRange])
        }
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

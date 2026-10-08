import Foundation

/// Names a ROM file the way No-Intro names a dump, then a hack or translation the way they're
/// released, in brackets after the base game's name:
/// "Title (Region) (Languages) (Rev X) (vX.Y) (Status) [Hack Title by Author vX.Y] [T-En]".
extension FilenameMetadataParser {
    public static func canonicalFilename(
        fileExtension: String,
        title: String,
        metadata: BuildImportMetadata,
        unknownGroups: [String]
    ) -> String {
        let modified = isModification(metadata)
        var groups: [String] = []
        if let region = metadata.region { groups.append("(\(region))") }
        if let language = metadata.language { groups.append("(\(noIntroLanguages(language)))") }
        if let revision = metadata.revision { groups.append("(Rev \(revision))") }
        if modified {
            // The version and status belong to the hack, so they go with it, not with the base.
            groups += modificationGroups(for: metadata)
        } else {
            if let version = metadata.versionString { groups.append("(v\(version))") }
            if let status = metadata.status { groups.append("(\(noIntroStatus(status)))") }
            if let author = metadata.author { groups.append("[by \(author)]") }
        }
        groups += unknownGroups.map { "[\($0)]" }
        let name = noIntroTitle(modified ? metadata.baseTitle ?? title : title)
        let stem = ([name] + groups).filter { !$0.isEmpty }.joined(separator: " ")
        return fileExtension.isEmpty ? stem : "\(stem).\(fileExtension)"
    }

    /// The brackets that follow a base game's name for a hack or translation: the hack's own title
    /// (or "Hack", or "T-En" for a translation) with its author and version, as in
    /// "[Night patch by Jane v0.3]" or "[T-En by Jane v1.0]", then its status.
    public static func modificationGroups(for metadata: BuildImportMetadata) -> [String] {
        let ownTitle = metadata.hackTitle.flatMap { hackTitle in
            metadata.baseTitle?.localizedCaseInsensitiveCompare(hackTitle) == .orderedSame ? nil : hackTitle
        }
        let translation = metadata.translation.map { "T-\(languageCode(for: $0))" }
        let credit = [metadata.author.map { "by \($0)" }, metadata.versionString.map { "v\($0)" }].compactMap { $0 }
        var groups: [String] = []
        if let ownTitle {
            groups.append("[\(([ownTitle] + credit).joined(separator: " "))]")
            if let translation { groups.append("[\(translation)]") }
        } else {
            groups.append("[\(([translation ?? "Hack"] + credit).joined(separator: " "))]")
        }
        if let status = metadata.status { groups.append("[\(noIntroStatus(status))]") }
        return groups
    }

    private static func isModification(_ metadata: BuildImportMetadata) -> Bool {
        metadata.baseTitle != nil || metadata.hackTitle != nil || metadata.translation != nil
    }

    /// No-Intro titles are plain ASCII, with a subtitle after " - " and a leading article moved to
    /// the end of the main title: "Legend of Zelda, The - Link's Awakening".
    static func noIntroTitle(_ title: String) -> String {
        let plain = title.folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: ": ", with: " - ")
        let mainEnd = plain.range(of: " - ")?.lowerBound ?? plain.endIndex
        let main = plain[..<mainEnd]
        for article in ["The", "A", "An"] where main.hasPrefix("\(article) ") && main.count > article.count + 1 {
            return "\(main.dropFirst(article.count + 1)), \(article)\(plain[mainEnd...])"
        }
        return plain
    }

    /// No-Intro lists languages with a comma and no space: "En,Fr,De".
    private static func noIntroLanguages(_ languages: String) -> String {
        languages.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: ",")
    }

    /// No-Intro writes "Proto" where filenames often say "Prototype".
    private static func noIntroStatus(_ status: String) -> String {
        guard status.lowercased().hasPrefix("prototype") else { return status }
        return "Proto" + status.dropFirst("prototype".count)
    }

    /// The two-letter code a translation tag uses, as No-Intro writes languages: "Spanish" and
    /// GoodTools' "Spa" both become "Es". An unknown name stays as written.
    static func languageCode(for language: String) -> String {
        let key = language.trimmingCharacters(in: .whitespaces).lowercased()
        let codes: [String: String] = [
            "english": "En", "eng": "En", "en": "En",
            "japanese": "Ja", "jpn": "Ja", "jap": "Ja", "ja": "Ja",
            "french": "Fr", "fre": "Fr", "fra": "Fr", "fr": "Fr",
            "german": "De", "ger": "De", "deu": "De", "de": "De",
            "spanish": "Es", "spa": "Es", "es": "Es",
            "italian": "It", "ita": "It", "it": "It",
            "portuguese": "Pt", "por": "Pt", "pt": "Pt",
            "dutch": "Nl", "dut": "Nl", "nld": "Nl", "nl": "Nl",
            "swedish": "Sv", "swe": "Sv", "sv": "Sv",
            "russian": "Ru", "rus": "Ru", "ru": "Ru",
            "chinese": "Zh", "chi": "Zh", "zho": "Zh", "zh": "Zh",
            "korean": "Ko", "kor": "Ko", "ko": "Ko",
            "polish": "Pl", "pol": "Pl", "pl": "Pl",
            "greek": "El", "gre": "El", "ell": "El", "el": "El",
            "turkish": "Tr", "tur": "Tr", "tr": "Tr",
            "arabic": "Ar", "ara": "Ar", "ar": "Ar",
        ]
        return codes[key] ?? language
    }
}

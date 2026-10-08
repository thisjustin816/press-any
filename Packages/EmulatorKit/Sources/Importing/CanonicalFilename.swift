import Foundation

/// Names a ROM file the way No-Intro names a dump, then a hack or translation in brackets after
/// the base game's name, a translation in GoodTools' form:
/// "Title (Region) (Languages) (Rev X) (vX.Y) (Status) [Night patch by Jane v0.3] [T+Eng1.03_Jane]".
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

    /// The brackets that follow a base game's name for a hack or translation, then its status. A
    /// hack names itself with its author and version, "[Night patch by Jane v0.3]", or "[Hack by
    /// Jane v1.3]" without a title of its own. A translation takes GoodTools' form,
    /// "[T+Eng1.03_Jane]", and its credit goes with the hack when it's part of one.
    public static func modificationGroups(for metadata: BuildImportMetadata) -> [String] {
        let ownTitle = metadata.hackTitle.flatMap { hackTitle in
            metadata.baseTitle?.localizedCaseInsensitiveCompare(hackTitle) == .orderedSame ? nil : hackTitle
        }
        var groups: [String] = []
        if ownTitle != nil || metadata.translation == nil {
            let credit = [metadata.author.map { "by \($0)" }, metadata.versionString.map { "v\($0)" }]
            groups.append("[\(([ownTitle ?? "Hack"] + credit.compactMap { $0 }).joined(separator: " "))]")
            if let translation = metadata.translation { groups.append("[T+\(goodToolsLanguage(for: translation))]") }
        } else if let translation = metadata.translation {
            let version = metadata.versionString ?? ""
            let author = metadata.author.map { "_\($0)" } ?? ""
            groups.append("[T+\(goodToolsLanguage(for: translation))\(version)\(author)]")
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

    /// GoodTools' three-letter language code for a translation tag: "Spanish", "Es" and "Spa" all
    /// become "Spa". An unknown name stays as written.
    static func goodToolsLanguage(for language: String) -> String {
        let key = language.trimmingCharacters(in: .whitespaces).lowercased()
        let codes: [String: String] = [
            "english": "Eng", "en": "Eng", "eng": "Eng",
            "japanese": "Jap", "ja": "Jap", "jap": "Jap", "jpn": "Jap",
            "french": "Fre", "fr": "Fre", "fre": "Fre", "fra": "Fre",
            "german": "Ger", "de": "Ger", "ger": "Ger", "deu": "Ger",
            "spanish": "Spa", "es": "Spa", "spa": "Spa",
            "italian": "Ita", "it": "Ita", "ita": "Ita",
            "portuguese": "Por", "pt": "Por", "por": "Por",
            "brazilian portuguese": "Bra", "pt-br": "Bra", "bra": "Bra",
            "dutch": "Dut", "nl": "Dut", "dut": "Dut", "nld": "Dut",
            "swedish": "Swe", "sv": "Swe", "swe": "Swe",
            "norwegian": "Nor", "no": "Nor", "nor": "Nor",
            "danish": "Dan", "da": "Dan", "dan": "Dan",
            "finnish": "Fin", "fi": "Fin", "fin": "Fin",
            "russian": "Rus", "ru": "Rus", "rus": "Rus",
            "polish": "Pol", "pl": "Pol", "pol": "Pol",
            "greek": "Gre", "el": "Gre", "gre": "Gre",
            "turkish": "Tur", "tr": "Tur", "tur": "Tur",
            "hungarian": "Hun", "hu": "Hun", "hun": "Hun",
            "catalan": "Cat", "ca": "Cat", "cat": "Cat",
            "hebrew": "Heb", "he": "Heb", "heb": "Heb",
            "arabic": "Ara", "ar": "Ara", "ara": "Ara",
            "chinese": "Chi", "zh": "Chi", "chi": "Chi",
            "korean": "Kor", "ko": "Kor", "kor": "Kor",
        ]
        return codes[key] ?? language
    }
}

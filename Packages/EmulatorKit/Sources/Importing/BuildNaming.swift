import EmulatorApplication
import EmulatorDomain
import Foundation

public enum BuildNaming {
    /// Returns `name`, or a name that tells this Build apart when another Build in the Game already
    /// has it. The parser's "Original" for a file without tags is never used: Base already marks
    /// the primary Build, so an untagged Build is named for the day it was added, "2026-10-06", as
    /// date-stamped files are. Any other repeated name gains the day, "v1.0 · Oct 6". Either then
    /// adds the time for Builds added the same day, then a number.
    public static func distinctName(
        _ name: String,
        existing: [String],
        addedAt date: Date,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let taken = Set(existing.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        func isFree(_ candidate: String) -> Bool { !taken.contains(candidate.lowercased()) }
        let untagged = name == "Original"
        guard untagged || !isFree(name) else { return name }

        let time = date.formatted(Date.FormatStyle(locale: locale, timeZone: timeZone).hour().minute())
        let candidates: [String]
        if untagged {
            let day = date.formatted(Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day())
            candidates = [day, "\(day) \(time)"]
        } else {
            let day = date.formatted(Date.FormatStyle(locale: locale, timeZone: timeZone).month(.abbreviated).day())
            candidates = ["\(name) · \(day)", "\(name) · \(day), \(time)"]
        }
        if let free = candidates.first(where: isFree) { return free }
        let last = candidates[candidates.count - 1]
        var number = 2
        while !isFree("\(last) (\(number))") { number += 1 }
        return "\(last) (\(number))"
    }

    /// The Build name a patch's filename suggests. A patch makes a variant, so the parser's generic
    /// names for an untagged file, "Original" and "Hack", give way to the patch's own title. A
    /// version or other tag follows the title, "Mole Mania DX v1.3", unless the title is the Game's
    /// own: "Example (Rev 1)" applied to Example is "Rev 1".
    public static func patchBuildName(for naming: FilenameMetadata, gameTitle: String? = nil) -> String {
        let title = naming.buildMetadata.hackTitle ?? naming.suggestedTitle
        guard !["Original", "Hack"].contains(naming.suggestedBuildName) else { return title }
        if let gameTitle, GameMatcher.normalized(gameTitle) == GameMatcher.normalized(title) { return naming.suggestedBuildName }
        return "\(title) \(naming.suggestedBuildName)"
    }

    /// The metadata a patch's filename gives the Build it makes. A patch with no hack title in its
    /// name is titled by its filename, since the patch is what tells the Build apart.
    public static func patchMetadata(for naming: FilenameMetadata) -> BuildImportMetadata {
        var metadata = naming.buildMetadata
        metadata.hackTitle = metadata.hackTitle ?? naming.suggestedTitle
        return metadata
    }

    /// Whether a name still carries URL escapes such as `%20`, as names taken from shared files did
    /// before filenames were decoded.
    static func hasPercentEscapes(_ name: String) -> Bool {
        name.range(of: "%[0-9A-Fa-f]{2}", options: .regularExpression) != nil
            && name.removingPercentEncoding != nil
            && name.removingPercentEncoding != name
    }
}

/// A suggested new name for an existing Build, for the player to confirm or edit.
public struct BuildNameSuggestion: Identifiable, Equatable, Sendable {
    public let buildID: UUID
    public let gameID: UUID
    public let gameTitle: String
    public let currentName: String
    public let suggestedName: String

    public var id: UUID { buildID }
}

/// Applies the import naming rules to Builds already in the library. It suggests a name only where
/// the current one looks generated: one still carrying URL escapes, one that is just the source
/// filename, "Original" or the parser's generic "Hack" with or without a date added, or one an
/// earlier Build in the same Game already has. Every "Original" gains the day its Build was added.
public struct BuildNameSuggester: Sendable {
    private let games: any GameRepository
    private let builds: any BuildRepository
    private let assets: any ManagedAssetRepository

    public init(games: any GameRepository, builds: any BuildRepository, assets: any ManagedAssetRepository) {
        self.games = games
        self.builds = builds
        self.assets = assets
    }

    public func suggestions(locale: Locale = .current, timeZone: TimeZone = .current) throws -> [BuildNameSuggestion] {
        var result: [BuildNameSuggestion] = []
        let sortedGames = try games.fetchGames().sorted {
            $0.primaryTitle.localizedCaseInsensitiveCompare($1.primaryTitle) == .orderedAscending
        }
        for game in sortedGames {
            let gameBuilds = try builds.fetchBuilds(gameID: game.id).sorted {
                ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString)
            }
            // Earlier Builds keep their names, so a later duplicate is the one that gains a date.
            var settled: [String] = []
            for (index, build) in gameBuilds.enumerated() {
                let others = settled + gameBuilds[(index + 1)...].map(\.displayName)
                let filename = try sourceFilename(of: build)
                let current = build.displayName
                let repeatsEarlier = settled.contains { $0.caseInsensitiveCompare(current) == .orderedSame }
                let looksGenerated = BuildNaming.hasPercentEscapes(current)
                    || Self.isGeneric(current)
                    || filename.map { Self.isFilename(current, of: $0) } == true
                    || repeatsEarlier
                guard looksGenerated else {
                    settled.append(current)
                    continue
                }
                let base = filename.map { FilenameMetadataParser.parse(filename: $0).suggestedBuildName }
                    ?? (current.removingPercentEncoding ?? current)
                // "Hack" with nothing better in the filename stays, unless an earlier Build has it.
                guard base != current || repeatsEarlier || current == "Original" else {
                    settled.append(current)
                    continue
                }
                let suggested = BuildNaming.distinctName(
                    base,
                    existing: others,
                    addedAt: build.createdAt,
                    locale: locale,
                    timeZone: timeZone
                )
                settled.append(suggested)
                if suggested != current {
                    result.append(BuildNameSuggestion(
                        buildID: build.id,
                        gameID: game.id,
                        gameTitle: game.primaryTitle,
                        currentName: current,
                        suggestedName: suggested
                    ))
                }
            }
        }
        return result
    }

    /// The imported file's name. Patched Builds have no source filename of their own.
    private func sourceFilename(of build: Build) throws -> String? {
        guard build.sourceKind != .patchRecipe else { return nil }
        return try assets.fetchAsset(id: build.imageAssetID)?.originalFilename
    }

    private static func isGeneric(_ name: String) -> Bool {
        ["Original", "Hack"].contains { name == $0 || name.hasPrefix("\($0) · ") }
    }

    private static func isFilename(_ name: String, of filename: String) -> Bool {
        let decoded = filename.removingPercentEncoding ?? filename
        let candidates = [filename, decoded].flatMap { [$0, ($0 as NSString).deletingPathExtension] }
        return candidates.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }
}

/// Finds the Game an imported file probably belongs to, from its title. Titles compare without case,
/// punctuation or spacing, so "match-land.gb" matches "Match Land". A hack also tries its base
/// title. More than one matching Game is no match, so the player chooses.
public enum GameMatcher {
    public static func matchingGameID(for naming: FilenameMetadata, headerTitle: String, in games: [Game]) -> UUID? {
        var titles = [naming.suggestedTitle, headerTitle]
        if let base = naming.buildMetadata.baseTitle { titles.append(base) }
        for title in titles {
            let key = normalized(title)
            guard !key.isEmpty else { continue }
            let matches = games.filter { ([$0.primaryTitle] + $0.aliases).contains { normalized($0) == key } }
            if matches.count == 1 { return matches[0].id }
            if matches.count > 1 { return nil }
        }
        return nil
    }

    static func normalized(_ title: String) -> String {
        String(title.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }
}

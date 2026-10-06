import EmulatorApplication
import EmulatorDomain
import Foundation

public enum BuildNaming {
    /// Returns `name`, or `name` with the date the Build was added when another Build in the Game
    /// already has that name: "Original · Oct 6", then with the year, then numbered.
    public static func distinctName(
        _ name: String,
        existing: [String],
        addedAt date: Date,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let taken = Set(existing.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        func isFree(_ candidate: String) -> Bool { !taken.contains(candidate.lowercased()) }
        guard !isFree(name) else { return name }

        var style = Date.FormatStyle(locale: locale, timeZone: timeZone).month(.abbreviated).day()
        let day = "\(name) · \(date.formatted(style))"
        if isFree(day) { return day }
        style = style.year()
        let dated = "\(name) · \(date.formatted(style))"
        if isFree(dated) { return dated }
        var number = 2
        while !isFree("\(dated) (\(number))") { number += 1 }
        return "\(dated) (\(number))"
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
/// filename, or one an earlier Build in the same Game already has.
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
                let looksGenerated = BuildNaming.hasPercentEscapes(current)
                    || filename.map { Self.isFilename(current, of: $0) } == true
                    || settled.contains { $0.caseInsensitiveCompare(current) == .orderedSame }
                guard looksGenerated else {
                    settled.append(current)
                    continue
                }
                let base = filename.map { FilenameMetadataParser.parse(filename: $0).suggestedBuildName }
                    ?? (current.removingPercentEncoding ?? current)
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

    private static func isFilename(_ name: String, of filename: String) -> Bool {
        let decoded = filename.removingPercentEncoding ?? filename
        let candidates = [filename, decoded].flatMap { [$0, ($0 as NSString).deletingPathExtension] }
        return candidates.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }
}

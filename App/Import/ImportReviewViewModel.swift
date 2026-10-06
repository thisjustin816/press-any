import Combine
import EmulatorApplication
import EmulatorDomain
import Foundation
import GameIdentity
import Importing

@MainActor
final class ImportReviewViewModel: ObservableObject {
    enum Destination: Hashable {
        case newGame
        case existing(UUID)
    }

    @Published var destination: Destination
    @Published var gameTitle: String
    @Published var buildDisplayName: String
    @Published var markAsBase: Bool
    @Published var markAsPreferred: Bool
    @Published var region: String
    @Published var language: String
    @Published var revision: String
    @Published var version: String
    @Published var baseTitle: String
    @Published var hackTitle: String
    @Published var author: String
    @Published var translation: String
    @Published var status: String
    @Published private(set) var errorMessage: String?

    let analysis: ROMImportAnalysis
    let games: [Game]

    private let coordinator: ImportCoordinator
    /// A Game's Builds: a suggested name that repeats one gains the date it was added, and an
    /// existing Base decides whether the new Build should replace it.
    private let existingBuilds: (UUID) -> [Build]
    /// The last name suggested, so changing the destination replaces it unless the player edited it.
    private var suggestedBuildName: String
    /// The destination the roles were last suggested for.
    private var previousDestination: Destination

    init(
        analysis: ROMImportAnalysis,
        games: [Game],
        coordinator: ImportCoordinator,
        existingBuilds: @escaping (UUID) -> [Build] = { _ in [] }
    ) {
        self.analysis = analysis
        // Games holding the release's No-Intro family come first, so a choice among them is at hand.
        let family = Set(analysis.familyGameIDs)
        self.games = games.sorted {
            if family.contains($0.id) != family.contains($1.id) { return family.contains($0.id) }
            return $0.primaryTitle.localizedCaseInsensitiveCompare($1.primaryTitle) == .orderedAscending
        }
        self.coordinator = coordinator
        self.existingBuilds = existingBuilds
        let metadata = BuildImportMetadata(analysis: analysis)
        region = metadata.region ?? ""
        language = metadata.language ?? ""
        revision = metadata.revision ?? ""
        version = metadata.versionString ?? ""
        baseTitle = metadata.baseTitle ?? ""
        hackTitle = metadata.hackTitle ?? ""
        author = metadata.author ?? ""
        translation = metadata.translation ?? ""
        status = metadata.status ?? ""

        let initialDestination: Destination
        // A family split across Games is the player's choice; a title match mustn't make it for them.
        let titleMatch = analysis.familyGameIDs.count > 1
            ? nil
            : GameMatcher.matchingGameID(for: analysis.filenameMetadata, headerTitle: analysis.header.title, in: games)
        if let suggested = analysis.suggestedGameID ?? titleMatch {
            initialDestination = .existing(suggested)
        } else {
            initialDestination = .newGame
        }
        destination = initialDestination
        previousDestination = initialDestination
        markAsBase = Self.suggestedBase(for: analysis, destination: initialDestination, existingBuilds: existingBuilds)
        markAsPreferred = true
        gameTitle = analysis.filenameMetadata.suggestedTitle.isEmpty
            ? analysis.header.title
            : analysis.filenameMetadata.suggestedTitle
        let suggestion = Self.buildName(for: analysis, destination: initialDestination, existingBuilds: existingBuilds)
        suggestedBuildName = suggestion
        buildDisplayName = analysis.exactExistingBuildID == nil ? suggestion : "Existing"
    }

    private static func buildName(
        for analysis: ROMImportAnalysis,
        destination: Destination,
        existingBuilds: (UUID) -> [Build]
    ) -> String {
        let existing: [String]
        if case .existing(let gameID) = destination {
            existing = existingBuilds(gameID).map(\.displayName)
        } else {
            existing = []
        }
        return BuildNaming.distinctName(analysis.filenameMetadata.suggestedBuildName, existing: existing, addedAt: .now)
    }

    var isExactDuplicate: Bool { analysis.exactExistingBuildID != nil }
    var shortHash: String { String(analysis.sha256.prefix(12)) }
    var normalizedFilename: String {
        // A known dump's canonical name is No-Intro's.
        if let dump = analysis.knownDump {
            let fileExtension = URL(fileURLWithPath: analysis.originalFilename).pathExtension.lowercased()
            return fileExtension.isEmpty ? dump.name : "\(dump.name).\(fileExtension)"
        }
        return FilenameMetadataParser.canonicalFilename(
            fileExtension: URL(fileURLWithPath: analysis.originalFilename).pathExtension.lowercased(),
            title: gameTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            metadata: reviewedMetadata,
            unknownGroups: analysis.filenameMetadata.unknownGroups
        )
    }
    var namingEvidence: String {
        guard let dump = analysis.knownDump else {
            return "Filename suggestion · \(analysis.filenameMetadata.confidence.displayName) confidence"
        }
        var evidence = dump.bad
            ? "No-Intro lists this file as a bad dump of \(dump.name)"
            : "Verified No-Intro dump: \(dump.name)"
        if analysis.familyGameIDs.count > 1 {
            evidence += ". Releases of this game are in \(analysis.familyGameIDs.count) Games, listed first; choose one"
        }
        return evidence
    }

    func destinationChanged() {
        if !isExactDuplicate, buildDisplayName == suggestedBuildName {
            suggestedBuildName = Self.buildName(for: analysis, destination: destination, existingBuilds: existingBuilds)
            buildDisplayName = suggestedBuildName
        }
        // Like the name, a role the player set stays; only an untouched suggestion follows the Game.
        let previousBase = Self.suggestedBase(for: analysis, destination: previousDestination, existingBuilds: existingBuilds)
        if markAsBase == previousBase {
            markAsBase = Self.suggestedBase(for: analysis, destination: destination, existingBuilds: existingBuilds)
        }
        previousDestination = destination
    }

    var plan: ROMImportPlan {
        let disposition: ROMImportDisposition
        if let existing = analysis.exactExistingBuildID {
            disposition = .duplicateExisting(buildID: existing)
        } else {
            switch destination {
            case .newGame:
                disposition = .createGame(title: gameTitle.trimmingCharacters(in: .whitespacesAndNewlines))
            case .existing(let gameID):
                disposition = .addBuild(gameID: gameID)
            }
        }
        return ROMImportPlan(
            analysis: analysis,
            disposition: disposition,
            buildDisplayName: buildDisplayName.trimmingCharacters(in: .whitespacesAndNewlines),
            markAsBase: markAsBase,
            markAsPreferred: markAsPreferred,
            metadata: reviewedMetadata
        )
    }

    var canCommit: Bool {
        isExactDuplicate || !buildDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func commit() throws -> ROMImportResult {
        do {
            let result = try coordinator.committer.commit(plan)
            errorMessage = nil
            return result
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func report(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    func cancel() {
        coordinator.discard(analysis)
    }

    /// A new Build is the one to play, so Preferred is always suggested. Base, the clean ROM patches
    /// apply to, is suggested for a Game that has none yet, unless the file is a hack. Where the Game
    /// has a Base, only a newer homebrew release replaces it: a file whose version or date sorts after
    /// the Base's, or any versioned file when the Base has none. A retail revision or a beta has no
    /// version, so it leaves the Base alone. Marking Base replaces the Game's previous Base Build.
    private static func suggestedBase(
        for analysis: ROMImportAnalysis,
        destination: Destination,
        existingBuilds: (UUID) -> [Build]
    ) -> Bool {
        guard analysis.filenameMetadata.releaseKind != .romHack else { return false }
        guard case .existing(let gameID) = destination,
              let base = existingBuilds(gameID).first(where: \.isBase) else { return true }
        guard let key = BuildImportMetadata(analysis: analysis).versionSortKey else { return false }
        guard let baseKey = base.versionSortKey else { return true }
        return key > baseKey
    }

    private var reviewedMetadata: BuildImportMetadata {
        BuildImportMetadata(
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
    }
}

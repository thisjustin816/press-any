import Combine
import EmulatorApplication
import EmulatorDomain
import Foundation
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
    /// A Game's Build names, so a suggested name that repeats one gains the date it was added.
    private let existingBuildNames: (UUID) -> [String]
    /// The last name suggested, so changing the destination replaces it unless the player edited it.
    private var suggestedBuildName: String

    init(
        analysis: ROMImportAnalysis,
        games: [Game],
        coordinator: ImportCoordinator,
        existingBuildNames: @escaping (UUID) -> [String] = { _ in [] }
    ) {
        self.analysis = analysis
        self.games = games.sorted {
            $0.primaryTitle.localizedCaseInsensitiveCompare($1.primaryTitle) == .orderedAscending
        }
        self.coordinator = coordinator
        self.existingBuildNames = existingBuildNames
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
        if let suggested = analysis.suggestedGameID
            ?? GameMatcher.matchingGameID(for: analysis.filenameMetadata, headerTitle: analysis.header.title, in: games) {
            initialDestination = .existing(suggested)
        } else {
            initialDestination = .newGame
        }
        destination = initialDestination
        markAsBase = Self.suggestedBase(for: analysis.filenameMetadata.releaseKind, destination: initialDestination)
        markAsPreferred = Self.suggestedPreferred(for: analysis.filenameMetadata.releaseKind, destination: initialDestination)
        gameTitle = analysis.filenameMetadata.suggestedTitle.isEmpty
            ? analysis.header.title
            : analysis.filenameMetadata.suggestedTitle
        let suggestion = Self.buildName(for: analysis, destination: initialDestination, existingBuildNames: existingBuildNames)
        suggestedBuildName = suggestion
        buildDisplayName = analysis.exactExistingBuildID == nil ? suggestion : "Existing"
    }

    private static func buildName(
        for analysis: ROMImportAnalysis,
        destination: Destination,
        existingBuildNames: (UUID) -> [String]
    ) -> String {
        let name = analysis.filenameMetadata.suggestedBuildName
        guard case .existing(let gameID) = destination else { return name }
        return BuildNaming.distinctName(name, existing: existingBuildNames(gameID), addedAt: .now)
    }

    var isExactDuplicate: Bool { analysis.exactExistingBuildID != nil }
    var shortHash: String { String(analysis.sha256.prefix(12)) }
    var normalizedFilename: String {
        FilenameMetadataParser.canonicalFilename(
            fileExtension: URL(fileURLWithPath: analysis.originalFilename).pathExtension.lowercased(),
            title: gameTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            metadata: reviewedMetadata,
            unknownGroups: analysis.filenameMetadata.unknownGroups
        )
    }
    var namingEvidence: String {
        "Filename suggestion · \(analysis.filenameMetadata.confidence.displayName) confidence"
    }

    func destinationChanged() {
        if !isExactDuplicate, buildDisplayName == suggestedBuildName {
            suggestedBuildName = Self.buildName(for: analysis, destination: destination, existingBuildNames: existingBuildNames)
            buildDisplayName = suggestedBuildName
        }
        markAsBase = Self.suggestedBase(for: analysis.filenameMetadata.releaseKind, destination: destination)
        markAsPreferred = Self.suggestedPreferred(for: analysis.filenameMetadata.releaseKind, destination: destination)
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

    /// A new Build is the one to play and, unless it's a hack, the clean ROM patches apply to.
    /// Marking it Base replaces the Game's previous Base Build.
    private static func suggestedBase(for kind: FilenameReleaseKind, destination: Destination) -> Bool {
        kind != .romHack
    }

    private static func suggestedPreferred(for kind: FilenameReleaseKind, destination: Destination) -> Bool {
        true
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

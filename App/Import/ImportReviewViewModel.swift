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
    /// Cover art chosen in review, already checked and downscaled, set on the Game after import.
    @Published private(set) var artwork: (data: Data, fileExtension: String)?
    /// Set when the ROM imported but its chosen artwork couldn't be saved.
    @Published private(set) var artworkFailure: String?

    let analysis: ROMImportAnalysis
    let games: [Game]

    private let coordinator: ImportCoordinator
    /// A Game's Builds: a suggested name that repeats one gains the date it was added, and an
    /// existing Base decides whether the new Build should replace it.
    private let existingBuilds: (UUID) -> [Build]
    /// Sets a Game's artwork. Without it, review doesn't offer artwork.
    private let setArtwork: ((UUID, Data, String) throws -> Void)?
    /// The last name suggested, so changing the destination replaces it unless the player edited it.
    private var suggestedBuildName: String
    /// The destination the roles were last suggested for.
    private var previousDestination: Destination

    init(
        analysis: ROMImportAnalysis,
        games: [Game],
        coordinator: ImportCoordinator,
        existingBuilds: @escaping (UUID) -> [Build] = { _ in [] },
        setArtwork: ((UUID, Data, String) throws -> Void)? = nil
    ) {
        self.analysis = analysis
        // Games holding the release's No-Intro family, or a Build with its header title, come first,
        // so a choice among them is at hand.
        let family = Set(analysis.familyGameIDs + analysis.headerTitleGameIDs)
        self.games = games.sorted {
            if family.contains($0.id) != family.contains($1.id) { return family.contains($0.id) }
            return $0.primaryTitle.localizedCaseInsensitiveCompare($1.primaryTitle) == .orderedAscending
        }
        self.coordinator = coordinator
        self.existingBuilds = existingBuilds
        self.setArtwork = setArtwork
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
        // A Game title match and a Build sharing the ROM's header title must agree, or neither is
        // suggested.
        var titleMatch: UUID?
        if analysis.familyGameIDs.count <= 1 {
            let byTitle = GameMatcher.matchingGameID(for: analysis.filenameMetadata, headerTitle: analysis.header.title, in: games)
            let byHeader = analysis.headerTitleGameIDs.count == 1 ? analysis.headerTitleGameIDs[0] : nil
            if let byTitle, let byHeader, byTitle != byHeader {
                titleMatch = nil
            } else {
                titleMatch = byTitle ?? byHeader
            }
        }
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
        var evidence = analysis.knownFile?.bad == true
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
        let result: ROMImportResult
        do {
            result = try coordinator.committer.commit(plan)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
        // The ROM is in the library now, so a failure here is reported without undoing the import.
        if canChooseArtwork, let artwork, let setArtwork {
            do {
                try setArtwork(result.build.gameID, artwork.data, artwork.fileExtension)
            } catch {
                artworkFailure = error.localizedDescription
            }
        }
        return result
    }

    /// Artwork applies to the Game the ROM lands in, so an exact duplicate, which changes nothing,
    /// doesn't offer it.
    var canChooseArtwork: Bool { setArtwork != nil && !isExactDuplicate }

    /// Whether the destination Game already has artwork that the chosen image would replace.
    var replacesArtwork: Bool {
        guard case .existing(let gameID) = destination else { return false }
        return games.first { $0.id == gameID }?.artworkAssetID != nil
    }

    /// Checks and downscales a picked image now, so an unreadable one is refused in review rather
    /// than after the ROM is imported.
    func chooseArtwork(_ data: Data, fileExtension: String) {
        do {
            try ImportSizeLimit.artwork.check(byteCount: Int64(data.count))
            artwork = try ArtworkImage.downscaled(data, fileExtension: fileExtension)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func chooseArtwork(fileAt url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            try ImportSizeLimit.artwork.check(fileAt: url)
            chooseArtwork(try Data(contentsOf: url), fileExtension: url.pathExtension.isEmpty ? "img" : url.pathExtension)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeArtwork() {
        artwork = nil
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

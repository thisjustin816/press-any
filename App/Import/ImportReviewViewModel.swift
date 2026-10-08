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
    @Published private(set) var proposedTitle: String?
    @Published var acceptProposedTitle = true
    @Published private(set) var baseGameReference: BaseGameReference?
    @Published var matchedAsHack = true
    @Published private(set) var errorMessage: String?
    /// Cover art chosen in review, already checked and downscaled, set on the Game after import.
    @Published private(set) var artwork: (data: Data, fileExtension: String)?
    /// Set when the ROM imported but its chosen artwork couldn't be saved.
    @Published private(set) var artworkFailure: String?

    let analysis: ROMImportAnalysis
    let games: [Game]

    private let coordinator: ImportCoordinator
    let knownDumps: KnownDumpIndex?
    private let releasePreference: ReleasePreference
    private var previousPreferredSuggestion = true
    private var previousBaseSuggestion = true
    /// A Game's Builds: a suggested name that repeats one gains the date it was added, and an
    /// existing Base decides whether the new Build should replace it.
    private let existingBuilds: (UUID) -> [Build]
    /// Sets a Game's artwork. Without it, review doesn't offer artwork.
    private let setArtwork: ((UUID, Data, String) throws -> Void)?
    /// The last name suggested, so changing the destination replaces it unless the player edited it.
    private var suggestedBuildName: String

    init(
        analysis: ROMImportAnalysis,
        games: [Game],
        coordinator: ImportCoordinator,
        existingBuilds: @escaping (UUID) -> [Build] = { _ in [] },
        setArtwork: ((UUID, Data, String) throws -> Void)? = nil,
        knownDumps: KnownDumpIndex? = nil,
        releasePreference: ReleasePreference = ReleasePreference()
    ) {
        self.analysis = analysis
        self.knownDumps = knownDumps
        self.releasePreference = releasePreference
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
        markAsBase = Self.suggestedBase(
            for: analysis, destination: initialDestination, existingBuilds: existingBuilds, knownDumps: knownDumps
        )
        markAsPreferred = true
        gameTitle = analysis.filenameMetadata.suggestedTitle.isEmpty
            ? analysis.header.title
            : analysis.filenameMetadata.suggestedTitle
        let suggestion = Self.buildName(for: analysis, destination: initialDestination, games: games, existingBuilds: existingBuilds)
        suggestedBuildName = suggestion
        buildDisplayName = analysis.exactExistingBuildID == nil ? suggestion : "Existing"
        previousBaseSuggestion = markAsBase
        refreshIdentityProposals()
    }

    private static func buildName(
        for analysis: ROMImportAnalysis,
        destination: Destination,
        games: [Game],
        existingBuilds: (UUID) -> [Build]
    ) -> String {
        guard case .existing(let gameID) = destination else {
            return BuildNaming.distinctName(analysis.filenameMetadata.suggestedBuildName, existing: [], addedAt: .now)
        }
        var name = analysis.filenameMetadata.suggestedBuildName
        // A hack joining a Game whose title it doesn't continue keeps its own title in the Build's
        // name, since the Game won't take it: "Co-op sync patch v0.1".
        if analysis.filenameMetadata.releaseKind == .romHack,
           let hack = analysis.filenameMetadata.buildMetadata.hackTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !hack.isEmpty, let game = games.first(where: { $0.id == gameID }),
           GameMatcher.normalized(hack) != GameMatcher.normalized(game.primaryTitle),
           !BuildNaming.offersTitle(hack, for: game.primaryTitle) {
            name = ["Original", "Hack"].contains(name) ? hack : "\(hack) \(name)"
        }
        return BuildNaming.distinctName(name, existing: existingBuilds(gameID).map(\.displayName), addedAt: .now)
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
            suggestedBuildName = Self.buildName(for: analysis, destination: destination, games: games, existingBuilds: existingBuilds)
            buildDisplayName = suggestedBuildName
        }
        // Like the name, a role the player set stays; only an untouched suggestion follows the Game.
        let baseSuggestion = baseGameReference != nil ? false
            : Self.suggestedBase(for: analysis, destination: destination, existingBuilds: existingBuilds, knownDumps: knownDumps)
        if markAsBase == previousBaseSuggestion { markAsBase = baseSuggestion }
        previousBaseSuggestion = baseSuggestion
        refreshIdentityProposals()
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
            metadata: reviewedMetadata,
            proposedGameTitle: acceptProposedTitle ? offeredGameTitle : nil,
            // A hack's title, adopted or given to a new Game, is the player's, so regional title
            // proposals leave it alone.
            proposedGameTitleIsPlayers: acceptProposedTitle && proposedHackTitle != nil,
            hasPlayerTitle: analysis.filenameMetadata.releaseKind == .romHack
                || (baseGameReference != nil && matchedAsHack)
                || gameTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    != (analysis.filenameMetadata.suggestedTitle.isEmpty ? analysis.header.title : analysis.filenameMetadata.suggestedTitle),
            baseGameReference: baseGameReference,
            suggestedBuildDisplayName: suggestedBuildName
        )
    }

    var canCommit: Bool {
        isExactDuplicate || (!buildDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (destination != .newGame || !gameTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
    }

    var offersBaseLink: Bool {
        guard case .existing(let id) = destination else { return false }
        return analysis.baseLineageGameIDs.contains(id)
    }

    func matchGame(_ game: Game) {
        let builds = existingBuilds(game.id)
        let ordered = builds.sorted {
            if $0.isBase != $1.isBase { return $0.isBase }
            return $0.createdAt < $1.createdAt
        }
        let base = ordered.first
        let dump = ordered.compactMap { $0.imageSHA1.flatMap { knownDumps?.dump(sha1: $0) } }.first
        if let dump, let knownDumps {
            baseGameReference = knownDumps.reference(to: dump, libraryGameID: game.id)
        } else if let reference = ordered.compactMap(\.baseGameReference).first {
            baseGameReference = BaseGameReference(title: reference.title, system: reference.system,
                familyName: reference.familyName, releaseName: reference.releaseName, libraryGameID: game.id)
        } else {
            baseGameReference = BaseGameReference(title: game.primaryTitle, system: base?.system ?? analysis.header.system, libraryGameID: game.id)
        }
        destination = .existing(game.id)
        baseTitle = baseGameReference?.title ?? ""
        destinationChanged()
        markAsBase = false
    }

    func matchGame(_ dump: KnownDump) {
        guard let knownDumps else { return }
        let candidates = games.filter { game in
            existingBuilds(game.id).contains { build in
                build.imageSHA1.flatMap { knownDumps.dump(sha1: $0) }.map { ($0.parent ?? $0.name) == (dump.parent ?? dump.name) && $0.system == dump.system } == true
            }
        }
        baseGameReference = knownDumps.reference(to: dump, libraryGameID: candidates.count == 1 ? candidates[0].id : nil)
        destination = candidates.count == 1 ? .existing(candidates[0].id) : .newGame
        baseTitle = dump.title
        destinationChanged()
        markAsBase = false
    }

    func clearMatch() {
        baseGameReference = nil
        baseTitle = analysis.filenameMetadata.buildMetadata.baseTitle ?? ""
        matchedAsHack = true
        markAsBase = Self.suggestedBase(
            for: analysis, destination: destination, existingBuilds: existingBuilds, knownDumps: knownDumps
        )
        previousBaseSuggestion = markAsBase
    }

    private func refreshIdentityProposals() {
        proposedTitle = nil
        var preferred = true
        if let incoming = analysis.knownDump, let knownDumps,
           case .existing(let id) = destination, let game = games.first(where: { $0.id == id }) {
            let builds = existingBuilds(id)
            let familyName = incoming.parent ?? incoming.name
            let releases = builds.compactMap { build -> (Build, KnownDump)? in
                guard let dump = build.imageSHA1.flatMap({ knownDumps.dump(sha1: $0) }),
                      dump.system == incoming.system, (dump.parent ?? dump.name) == familyName else { return nil }
                return (build, dump)
            }
            if let current = releases.first(where: { $0.0.id == game.preferredBuildID }) {
                preferred = releasePreference.prefers(region: region, language: language, overRegion: current.0.region, overLanguage: current.0.language)
            } else if let current = releases.first {
                preferred = releasePreference.prefers(region: region, language: language, overRegion: current.0.region, overLanguage: current.0.language)
            }
            if !releases.isEmpty, !game.hasPlayerTitle {
                let titles = releases.sorted {
                    ($0.0.createdAt, $0.0.id.uuidString) < ($1.0.createdAt, $1.0.id.uuidString)
                }.map { $0.1.releaseTitle(for: $0.0) }
                    + [ReleaseTitle(title: incoming.title, region: region, language: language)]
                if let best = releasePreference.preferredTitle(among: titles, currentTitle: game.primaryTitle),
                   best.title != game.primaryTitle { proposedTitle = best.title }
            }
        }
        if markAsPreferred == previousPreferredSuggestion { markAsPreferred = preferred }
        previousPreferredSuggestion = preferred
    }

    func metadataRankingChanged() { refreshIdentityProposals() }

    /// A hack that becomes an existing Game's Preferred Build offers its own title for the Game when
    /// that title is the Game's followed by more words, as "Mole Mania DX" for Mole Mania. A hack
    /// titled "Co-op sync patch" names its Build and leaves the Game alone. Accepting keeps the old
    /// title as an alias.
    var proposedHackTitle: String? {
        guard markAsPreferred, case .existing(let id) = destination,
              analysis.filenameMetadata.releaseKind == .romHack || (baseGameReference != nil && matchedAsHack),
              let game = games.first(where: { $0.id == id }) else { return nil }
        let title = hackTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return BuildNaming.offersTitle(title, for: game.primaryTitle) ? title : nil
    }

    /// The title review offers for the Game: a hack's own, or the best regional release title.
    var offeredGameTitle: String? { proposedHackTitle ?? proposedTitle }

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

    /// A missing Base or a recorded base family suggests a clean Base. A No-Intro release, or any
    /// file arriving where a No-Intro release is the Base, leaves that Base alone. Anything else is a
    /// homebrew or development build, and the newest one is the Base, so it replaces the Base unless
    /// its version sorts before the Base's.
    private static func suggestedBase(
        for analysis: ROMImportAnalysis,
        destination: Destination,
        existingBuilds: (UUID) -> [Build],
        knownDumps: KnownDumpIndex?
    ) -> Bool {
        guard analysis.filenameMetadata.releaseKind != .romHack else { return false }
        if case .existing(let id) = destination, analysis.baseLineageGameIDs.contains(id) { return true }
        guard case .existing(let gameID) = destination,
              let base = existingBuilds(gameID).first(where: \.isBase) else { return true }
        guard analysis.knownDump == nil,
              base.imageSHA1.flatMap({ knownDumps?.dump(sha1: $0) }) == nil else { return false }
        guard let key = BuildImportMetadata(analysis: analysis).versionSortKey,
              let baseKey = base.versionSortKey else { return true }
        return key >= baseKey
    }

    private var reviewedMetadata: BuildImportMetadata {
        BuildImportMetadata(
            region: region,
            language: language,
            revision: revision,
            versionString: version,
            baseTitle: baseTitle,
            hackTitle: baseGameReference != nil && matchedAsHack && hackTitle.isEmpty ? gameTitle : hackTitle,
            author: author,
            translation: translation,
            status: status
        )
    }
}

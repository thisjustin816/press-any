import Combine
import EmulationSession
import EmulatorApplication
import EmulatorDomain
import Foundation
import Importing
import Patching

@MainActor
final class GameDetailViewModel: ObservableObject {
    @Published private(set) var game: Game?
    @Published private(set) var builds: [Build] = []
    @Published private(set) var saveProfiles: [SaveProfile] = []
    @Published private(set) var otherGames: [Game] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var infoMessage: String?
    /// Set once a move leaves this Game deleted, so the screen can close.
    @Published private(set) var gameRemoved = false
    /// Patches refused because they expect a different base, waiting on Apply Anyway.
    @Published var baseMismatch: PendingPatch?
    /// A deletion waiting on its confirmation, with everything it takes.
    @Published var pendingDeletion: DeletionPlan?

    struct PendingPatch: Identifiable {
        let id = UUID()
        let urls: [URL]
        let build: Build
    }

    let gameID: UUID

    private let games: any GameRepository
    private let buildRepository: any BuildRepository
    private let profiles: any SaveProfileRepository
    private let buildOperations: BuildOperations
    private let createBlank: CreateBlankSaveProfile
    private let duplicateProfile: DuplicateSaveProfile
    private let badges: SetSaveProfileBadge
    private let deletion: LibraryDeletionOperations
    private let saveImporter: ImportBatterySave
    private let patchCreator: CreatePatchedBuild
    private let evictImage: EvictGeneratedImage
    private let artwork: GameArtwork
    private let variableMaps: AttachVariableMap
    private let saveReplacer: ReplaceBatterySave
    private let exporter: ExportLibraryFiles
    private let exportsDirectory: URL

    init(
        gameID: UUID,
        games: any GameRepository,
        builds: any BuildRepository,
        profiles: any SaveProfileRepository,
        buildOperations: BuildOperations,
        createBlank: CreateBlankSaveProfile,
        duplicateProfile: DuplicateSaveProfile,
        badges: SetSaveProfileBadge,
        deletion: LibraryDeletionOperations,
        importSave: ImportBatterySave,
        patchCreator: CreatePatchedBuild,
        evictImage: EvictGeneratedImage,
        artwork: GameArtwork,
        variableMaps: AttachVariableMap,
        replaceSave: ReplaceBatterySave,
        exporter: ExportLibraryFiles,
        exportsDirectory: URL
    ) {
        self.gameID = gameID
        self.games = games
        self.buildRepository = builds
        self.profiles = profiles
        self.buildOperations = buildOperations
        self.createBlank = createBlank
        self.duplicateProfile = duplicateProfile
        self.badges = badges
        self.deletion = deletion
        self.saveImporter = importSave
        self.patchCreator = patchCreator
        self.evictImage = evictImage
        self.artwork = artwork
        self.variableMaps = variableMaps
        self.saveReplacer = replaceSave
        self.exporter = exporter
        self.exportsDirectory = exportsDirectory
    }

    var preferredBuild: Build? {
        guard let preferred = game?.preferredBuildID else { return builds.first }
        return builds.first { $0.id == preferred } ?? builds.first
    }

    /// The save Play uses when the Build names none: the Game's default, or else its oldest, as
    /// `ResolvePreferredSaveProfile` picks it.
    var defaultSaveProfile: SaveProfile? {
        saveProfiles.first { $0.id == game?.preferredSaveProfileID } ?? saveProfiles.first
    }

    /// The Build and save Play starts, without creating the blank profile Play makes when the
    /// Game has none.
    var playSummary: String? {
        guard let build = preferredBuild else { return nil }
        let save = profileName(id: build.preferredSaveProfileID) ?? defaultSaveProfile?.title ?? "New Save"
        return "\(build.displayName) · \(save)"
    }

    func reload() {
        do {
            guard let fetched = try games.fetchGame(id: gameID) else {
                gameRemoved = true
                return
            }
            game = fetched
            builds = try buildRepository.fetchBuilds(gameID: gameID).sorted(by: Self.buildSort)
            saveProfiles = try profiles.fetchSaveProfiles(gameID: gameID).sorted {
                $0.createdAt < $1.createdAt
            }
            otherGames = try games.fetchGames()
                .filter { $0.id != gameID }
                .sorted { $0.primaryTitle.localizedCaseInsensitiveCompare($1.primaryTitle) == .orderedAscending }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func launchContext(build: Build? = nil, saveProfile: SaveProfile? = nil) throws -> LaunchContext {
        guard let selectedBuild = build ?? preferredBuild else {
            throw ResolvePreferredLaunchContextError.noBuilds(gameID)
        }
        let selectedProfile: SaveProfile
        if let saveProfile {
            selectedProfile = saveProfile
        } else {
            let resolver = ResolvePreferredSaveProfile(
                games: games,
                builds: buildRepository,
                profiles: profiles,
                createBlank: createBlank
            )
            selectedProfile = try resolver.execute(gameID: gameID, buildID: selectedBuild.id)
        }
        return LaunchContext(
            gameID: gameID,
            buildID: selectedBuild.id,
            saveProfileID: selectedProfile.id
        )
    }

    func buildName(id: UUID?) -> String? {
        guard let id else { return nil }
        return builds.first { $0.id == id }?.displayName
    }

    func profileName(id: UUID?) -> String? {
        guard let id else { return nil }
        return saveProfiles.first { $0.id == id }?.title
    }

    func setPreferredBuild(_ build: Build) {
        perform { try buildOperations.setPreferredBuild(gameID: gameID, buildID: build.id) }
    }

    func setFavorite(_ isFavorite: Bool) {
        do {
            try buildOperations.setFavorite(gameID: gameID, isFavorite: isFavorite)
            reload()
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func renameGame(to title: String) {
        do {
            try buildOperations.renameGame(gameID: gameID, title: title)
            reload()
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
        } catch BuildOperationError.invalidGameTitle {
            errorMessage = "A Game title can't be blank."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rename(_ build: Build, to displayName: String) {
        do {
            try buildOperations.renameBuild(buildID: build.id, displayName: displayName)
            reload()
        } catch BuildOperationError.invalidBuildName {
            errorMessage = "A Build name can’t be blank."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Sharing a profile between Builds is this choice: each Build names the profile it plays.
    func setDefaultProfile(_ profile: SaveProfile?, for build: Build) {
        perform { try buildOperations.setPreferredSaveProfile(buildID: build.id, profileID: profile?.id) }
    }

    func createBlankProfile(name: String) {
        perform { _ = try createBlank.execute(gameID: gameID, name: name) }
    }

    func setBadge(_ badge: String, of profile: SaveProfile) {
        do {
            _ = try badges.execute(profileID: profile.id, badge: badge)
            reload()
        } catch SaveProfileOperationError.invalidBadge {
            errorMessage = "A badge is a single emoji."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func requestGameDeletion() {
        requestDeletion { try deletion.planGameDeletion(gameID: gameID) }
    }

    func requestDeletion(of build: Build) {
        requestDeletion { try deletion.planBuildDeletion(buildID: build.id) }
    }

    func requestDeletion(of profile: SaveProfile) {
        requestDeletion { try deletion.planProfileDeletion(profileID: profile.id) }
    }

    func confirm(_ plan: DeletionPlan) {
        perform { _ = try deletion.delete(plan) }
        NotificationCenter.default.post(name: .libraryDidChange, object: nil)
    }

    /// What goes along with the deletion, and where it waits.
    func deletionMessage(for plan: DeletionPlan) -> String {
        let records = plan.records
        var counts: [(Int, String)] = []
        if plan.kind == .game {
            counts = [(records.buildIDs.count, "Build"), (records.saveProfileIDs.count, "Save Profile")]
        }
        counts.append((records.saveStateIDs.count, "save state"))
        var along = counts.filter { $0.0 > 0 }.map { "\($0.0) \($0.1)\($0.0 == 1 ? "" : "s")" }
        var total = counts.reduce(0) { $0 + $1.0 }
        if plan.kind == .saveProfile,
           saveProfiles.first(where: { $0.id == records.saveProfileIDs.first })?.persistentSaveAssetID != nil {
            along.insert("the battery save", at: 0)
            total += 1
        }

        var sentences: [String] = []
        if !along.isEmpty {
            let list = along.formatted(.list(type: .and))
            let capitalized = list.prefix(1).uppercased() + String(list.dropFirst())
            sentences.append("\(capitalized) \(total == 1 ? "goes" : "go") with it.")
        }
        if !plan.dependentBuilds.isEmpty {
            let one = plan.dependentBuilds.count == 1
            let names = plan.dependentBuilds.map(\.displayName).formatted(.list(type: .and))
            sentences.append("\(names) \(one ? "is" : "are") patched from it, so \(one ? "it goes" : "they go") too.")
        }
        for game in plan.emptiedGames {
            sentences.append("\(game.primaryTitle) has no other Builds, so it goes too, with its Save Profiles.")
        }
        sentences.append("Recently Deleted in Settings keeps \(plan.kind == .game ? "everything" : "it") for 30 days.")
        return sentences.joined(separator: " ")
    }

    func duplicate(_ profile: SaveProfile, name: String) {
        perform { _ = try duplicateProfile.execute(sourceProfileID: profile.id, name: name) }
    }

    func importSave(from url: URL) {
        perform {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let profile = try saveImporter.execute(
                gameID: gameID,
                sourceURL: url,
                name: url.deletingPathExtension().lastPathComponent
            )
            infoMessage = "Imported the save as \(profile.displayName)."
        }
    }

    func replaceSave(of profile: SaveProfile, from url: URL) {
        perform {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let result = try saveReplacer.execute(profileID: profile.id, sourceURL: url)
            infoMessage = if let copy = result.safetyCopy {
                "Imported \(url.lastPathComponent) into \(profile.displayName). Its previous save is in \(copy.displayName)."
            } else {
                "Imported \(url.lastPathComponent) into \(profile.displayName)."
            }
        }
    }

    func exportROM(of build: Build) {
        perform {
            let url = try exporter.exportROM(buildID: build.id, to: exportsDirectory)
            infoMessage = Self.exportedMessage(url)
        }
    }

    func exportSave(of profile: SaveProfile) {
        perform {
            let url = try exporter.exportSave(profileID: profile.id, to: exportsDirectory)
            infoMessage = Self.exportedMessage(url)
        }
    }

    private static func exportedMessage(_ url: URL) -> String {
        "Saved \(url.lastPathComponent) to Files, in \(AppBrand.displayName) › Exports."
    }

    func attachVariableMap(from url: URL, to build: Build) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let map = try variableMaps.execute(buildID: build.id, sourceURL: url)
            infoMessage = "Attached \(map.originalFilename) to \(build.displayName)."
        } catch AttachVariableMapError.unrecognizedFormat {
            errorMessage = "\(url.lastPathComponent) isn’t a GB Studio globals file or a symbol file."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyPatches(_ urls: [URL], to build: Build, ignoringBaseMismatch: Bool = false) {
        guard !urls.isEmpty else { return }
        let scoped = urls.map { $0.startAccessingSecurityScopedResource() }
        defer {
            for (url, didStart) in zip(urls, scoped) where didStart {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let naming = urls.map { FilenameMetadataParser.parse(filename: $0.lastPathComponent) }
            let displayName: String
            let metadata: BuildImportMetadata
            if let first = naming.first, naming.count == 1 {
                displayName = BuildNaming.distinctName(
                    BuildNaming.patchBuildName(for: first, gameTitle: game?.primaryTitle),
                    existing: builds.map(\.displayName),
                    addedAt: .now
                )
                metadata = BuildNaming.patchMetadata(for: first)
            } else {
                displayName = BuildNaming.distinctName(
                    urls.map { $0.deletingPathExtension().lastPathComponent }.joined(separator: " + "),
                    existing: builds.map(\.displayName),
                    addedAt: .now
                )
                metadata = BuildImportMetadata()
            }
            let patched = try patchCreator.execute(.init(
                gameID: gameID,
                baseBuildID: build.id,
                patches: urls.map { .init(url: $0, ignoreBaseMismatch: ignoringBaseMismatch) },
                displayName: displayName,
                makePreferred: true,
                metadata: metadata
            ))
            reload()
            infoMessage = "Created \(patched.displayName) from \(build.displayName)."
        } catch PatchError.sourceCRC32Mismatch, PatchError.sourceSizeMismatch {
            baseMismatch = PendingPatch(urls: urls, build: build)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeGeneratedImage(of build: Build) {
        perform {
            let removed = try evictImage.execute(buildID: build.id)
            infoMessage = removed
                ? "Removed the generated image. The next launch rebuilds it and checks its hash."
                : "The generated image wasn’t cached. The next launch rebuilds it."
        }
    }

    func setArtwork(from url: URL) {
        perform {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            try artwork.set(gameID: gameID, fileAt: url)
        }
    }

    func setArtwork(_ data: Data, fileExtension: String) {
        perform { try artwork.set(gameID: gameID, imageData: data, fileExtension: fileExtension) }
    }

    func removeArtwork() {
        perform { try artwork.remove(gameID: gameID) }
    }

    func setBase(_ build: Build, isBase: Bool) {
        perform { try buildOperations.setBase(buildID: build.id, isBase: isBase) }
    }

    /// The review step's first selection; when it can't be worked out, nothing is selected.
    func suggestedCarryOver(promoting build: Build) -> GameCarryOver {
        (try? buildOperations.suggestedCarryOver(promoting: build.id)) ?? .nothing
    }

    func suggestedCarryOver(mergingInto target: Game) -> GameCarryOver {
        (try? buildOperations.suggestedCarryOver(merging: gameID, into: target.id)) ?? .nothing
    }

    func promote(_ build: Build, title: String, mode: ReorganizationMode, carryOver: GameCarryOver) {
        perform {
            let newGame = try buildOperations.promoteBuild(buildID: build.id, title: title, mode: mode, carryOver: carryOver)
            infoMessage = "\(build.displayName) is now the Game \(newGame.primaryTitle)."
        }
    }

    func merge(into target: Game, mode: ReorganizationMode, carryOver: GameCarryOver) {
        do {
            try buildOperations.mergeGame(sourceGameID: gameID, into: target.id, mode: mode, carryOver: carryOver)
            reload()
            infoMessage = "Merged into \(target.primaryTitle)."
        } catch BuildOperationError.duplicateImagesInTarget(let buildIDs) {
            let names = buildIDs.compactMap { buildName(id: $0) }.formatted(.list(type: .and))
            errorMessage = "\(target.primaryTitle) already has the same ROM as \(names). Move can’t combine them without losing that Build’s save states. Use Copy, or remove one first."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func report(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    func clearMessages() {
        errorMessage = nil
        infoMessage = nil
    }

    private func requestDeletion(_ plan: () throws -> DeletionPlan) {
        do {
            pendingDeletion = try plan()
        } catch LibraryDeletionError.dependentBuildsInOtherGames(let buildIDs) {
            let names = buildIDs.compactMap { id -> String? in
                guard let build = try? buildRepository.fetchBuild(id: id) else { return nil }
                guard let game = try? games.fetchGame(id: build.gameID) else { return build.displayName }
                return "\(build.displayName) in \(game.primaryTitle)"
            }
            let one = names.count == 1
            errorMessage = "\(names.formatted(.list(type: .and))) \(one ? "is" : "are") patched from this Game’s Builds and can’t be rebuilt without them. Delete \(one ? "it" : "them") first, or merge the Games."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func perform(_ operation: () throws -> Void) {
        do {
            try operation()
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func buildSort(_ lhs: Build, _ rhs: Build) -> Bool {
        if lhs.isBase != rhs.isBase { return lhs.isBase && !rhs.isBase }
        if lhs.versionSortKey != rhs.versionSortKey {
            return (lhs.versionSortKey ?? "") < (rhs.versionSortKey ?? "")
        }
        return lhs.createdAt < rhs.createdAt
    }
}

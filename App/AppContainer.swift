import AssetStorage
import EmulationCore
import EmulationSession
import EmulatorApplication
import EmulatorDomain
import Foundation
import GameIdentity
import GameplayInput
import Importing
import Patching
import PersistenceGRDB
import QuickPlay
import SameBoyAdapter
import ToolchainDetection

@MainActor
final class AppContainer {
    let fileStore: ManagedFileStore
    let sharedFileInbox: SharedFileInbox
    let integrityChecker: ManagedAssetIntegrityChecker
    let database: AppDatabase
    let repositories: GRDBRepositorySet
    /// No-Intro's known dumps, bundled with the app. Nil only if the bundled file is unreadable,
    /// which its tests rule out; imports then go unmatched.
    let knownDumps: KnownDumpIndex?

    let importAnalyzer: ROMImportAnalyzer
    let importCommitter: ImportCommitter
    let buildOperations: BuildOperations
    let buildCheats: BuildCheatOperations
    let createBlankSaveProfile: CreateBlankSaveProfile
    let duplicateSaveProfile: DuplicateSaveProfile
    let setSaveProfileBadge: SetSaveProfileBadge
    let libraryDeletion: LibraryDeletionOperations
    let importBatterySave: ImportBatterySave
    let replaceBatterySave: ReplaceBatterySave
    let acceptDamagedSave: AcceptDamagedSave
    let preferredLaunchResolver: ResolvePreferredLaunchContext
    let patchCreator: CreatePatchedBuild
    let launchImageResolver: ResolveImageForLaunch
    let exportFiles: ExportLibraryFiles
    /// Where exports land: Documents/Exports, which Files shows in the Press Any folder.
    let exportsDirectory: URL
    let toolchainRefresh: RefreshToolchainReports
    let attachVariableMap: AttachVariableMap
    let saveCompatibility: AssessSaveCompatibility
    let chooseSaveForBuild: ChooseSaveForBuild
    let evictGeneratedImage: EvictGeneratedImage
    let gameArtwork: GameArtwork
    private let artworkProvider: (any ArtworkProvider)?
    private var artworkTasks: [UUID: Task<Void, Never>] = [:]
    let quickPlayWorkspace: QuickPlayWorkspace
    let quickPlayPromoter: PromoteQuickPlay
    let coreRegistry: CoreRegistry
    let settingsResolver: SettingsResolver
    let launchHistory: SessionLaunchHistory
    /// Plus ownership. LCD filters and Auto State history follow it; nothing else here does.
    let plus: PlusStore
    /// Files an import or the running game is using, which cache trimming and Check Library Files
    /// leave alone.
    let inFlightFiles = InFlightFiles()

    private(set) var activeSession: EmulationSession?

    var storageUsage: MeasureLibraryStorage {
        MeasureLibraryStorage(assets: repositories.assets, assetStore: fileStore)
    }

    var libraryBackup: LibraryBackupService {
        LibraryBackupService(repository: repositories.backup, assetStore: fileStore, inFlight: inFlightFiles)
    }

    func clearPatchedROMCache() throws {
        let activeBuildID: UUID?
        switch activeSession?.state {
        case .loading(let context), .running(let context), .paused(let context):
            activeBuildID = context.buildID
        default:
            activeBuildID = nil
        }
        try ClearPatchedROMCache(assets: repositories.assets, builds: repositories.builds,
            recipes: repositories.patchRecipes, assetStore: fileStore, inFlight: inFlightFiles)
            .execute(activeBuildID: activeBuildID)
    }

    static func live(fileManager: FileManager = .default) throws -> AppContainer {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        var root = ApplicationDataLocation.root(in: support)
        #if DEBUG
        // UI tests use separate libraries while file handoff still follows the production path.
        if let value = UserDefaults.standard.string(forKey: "UITestLibrary"),
           let id = UUID(uuidString: value) {
            root = root.appendingPathComponent("UITests/\(id.uuidString)", isDirectory: true)
        }
        #endif
        removeEmptyInbox()
        return try AppContainer(rootURL: root, plus: .live(), artworkProvider: LibretroArtworkProvider())
    }

    /// Production services are supplied by `live`; tests use StoreKit and artwork networking
    /// only when those services are injected.
    init(rootURL: URL, plus: PlusStore? = nil, artworkProvider: (any ArtworkProvider)? = nil) throws {
        self.plus = plus ?? .fixed(ownsPlus: false)
        self.artworkProvider = artworkProvider
        fileStore = try ManagedFileStore(rootURL: rootURL)
        sharedFileInbox = SharedFileInbox(store: fileStore)
        database = try AppDatabase(url: rootURL.appendingPathComponent("Library.sqlite"))
        try database.migrate()
        repositories = database.makeRepositories()

        integrityChecker = ManagedAssetIntegrityChecker(assets: repositories.assets, assetStore: fileStore,
            inFlight: inFlightFiles)
        knownDumps = try? KnownDumpIndex.bundled()
        importAnalyzer = ROMImportAnalyzer(builds: repositories.builds, games: repositories.games,
            assets: repositories.assets, fingerprints: repositories.fingerprints,
            toolchainReports: repositories.toolchainReports,
            assetStore: fileStore, knownDumps: knownDumps)
        importCommitter = ImportCommitter(
            games: repositories.games,
            builds: repositories.builds,
            assets: repositories.assets,
            toolchainReports: repositories.toolchainReports,
            fingerprints: repositories.fingerprints,
            assetStore: fileStore,
            transactions: repositories.transactions,
            inFlight: inFlightFiles
        )
        buildOperations = BuildOperations(
            games: repositories.games,
            builds: repositories.builds,
            profiles: repositories.saveProfiles,
            states: repositories.saveStates,
            recipes: repositories.patchRecipes,
            cheats: repositories.cheats,
            assets: repositories.assets,
            assetStore: fileStore,
            transactions: repositories.transactions
        )
        buildCheats = BuildCheatOperations(
            builds: repositories.builds,
            cheats: repositories.cheats,
            transactions: repositories.transactions
        )
        createBlankSaveProfile = CreateBlankSaveProfile(
            games: repositories.games,
            profiles: repositories.saveProfiles
        )
        setSaveProfileBadge = SetSaveProfileBadge(profiles: repositories.saveProfiles)
        libraryDeletion = LibraryDeletionOperations(
            games: repositories.games,
            builds: repositories.builds,
            profiles: repositories.saveProfiles,
            states: repositories.saveStates,
            recipes: repositories.patchRecipes,
            deletions: repositories.deletions,
            assetStore: fileStore,
            transactions: repositories.transactions,
            settings: SettingsResolver(store: repositories.settings)
        )
        duplicateSaveProfile = DuplicateSaveProfile(
            profiles: repositories.saveProfiles,
            assets: repositories.assets,
            assetStore: fileStore
        )
        importBatterySave = ImportBatterySave(
            games: repositories.games,
            profiles: repositories.saveProfiles,
            assets: repositories.assets,
            assetStore: fileStore
        )
        replaceBatterySave = ReplaceBatterySave(
            profiles: repositories.saveProfiles,
            assets: repositories.assets,
            assetStore: fileStore
        )
        acceptDamagedSave = AcceptDamagedSave(
            profiles: repositories.saveProfiles,
            assets: repositories.assets,
            assetStore: fileStore
        )
        preferredLaunchResolver = ResolvePreferredLaunchContext(
            games: repositories.games,
            builds: repositories.builds,
            profiles: repositories.saveProfiles
        )
        let volume = rootURL
        let trimCache = TrimPatchedROMCache(
            assets: repositories.assets,
            builds: repositories.builds,
            recipes: repositories.patchRecipes,
            profiles: repositories.saveProfiles,
            states: repositories.saveStates,
            assetStore: fileStore,
            inFlight: inFlightFiles,
            freeBytes: {
                try volume.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                    .volumeAvailableCapacityForImportantUsage
            }
        )
        patchCreator = CreatePatchedBuild(
            games: repositories.games,
            builds: repositories.builds,
            recipes: repositories.patchRecipes,
            assets: repositories.assets,
            toolchainReports: repositories.toolchainReports,
            assetStore: fileStore,
            transactions: repositories.transactions,
            trimCache: trimCache,
            inFlight: inFlightFiles
        )
        launchImageResolver = ResolveImageForLaunch(
            builds: repositories.builds,
            recipes: repositories.patchRecipes,
            assets: repositories.assets,
            assetStore: fileStore,
            trimCache: trimCache,
            inFlight: inFlightFiles
        )
        exportFiles = ExportLibraryFiles(
            games: repositories.games,
            builds: repositories.builds,
            profiles: repositories.saveProfiles,
            assets: repositories.assets,
            assetStore: fileStore,
            images: launchImageResolver,
            knownDumps: knownDumps
        )
        exportsDirectory = URL.documentsDirectory.appendingPathComponent("Exports", isDirectory: true)
        toolchainRefresh = RefreshToolchainReports(
            reports: repositories.toolchainReports,
            images: launchImageResolver,
            detect: { ToolchainDetectorRegistry.standard.detect(image: $0, system: $1) }
        )
        attachVariableMap = AttachVariableMap(
            builds: repositories.builds,
            maps: repositories.variableMaps,
            assets: repositories.assets,
            assetStore: fileStore,
            transactions: repositories.transactions,
            inFlight: inFlightFiles
        )
        saveCompatibility = AssessSaveCompatibility(
            builds: repositories.builds,
            profiles: repositories.saveProfiles,
            reports: repositories.toolchainReports,
            images: launchImageResolver,
            assetStore: fileStore
        )
        chooseSaveForBuild = ChooseSaveForBuild(
            games: repositories.games,
            builds: repositories.builds,
            profiles: repositories.saveProfiles,
            assets: repositories.assets,
            assetStore: fileStore
        )
        evictGeneratedImage = EvictGeneratedImage(
            builds: repositories.builds,
            assets: repositories.assets,
            assetStore: fileStore
        )
        gameArtwork = GameArtwork(
            games: repositories.games,
            assets: repositories.assets,
            assetStore: fileStore,
            transactions: repositories.transactions,
            settings: repositories.settings
        )
        quickPlayWorkspace = QuickPlayWorkspace(
            profiles: repositories.saveProfiles,
            assets: repositories.assets,
            assetStore: fileStore
        )
        quickPlayPromoter = PromoteQuickPlay(
            analyzer: importAnalyzer,
            committer: importCommitter,
            workspace: quickPlayWorkspace,
            builds: repositories.builds,
            profiles: repositories.saveProfiles,
            states: repositories.saveStates,
            assets: repositories.assets,
            assetStore: fileStore
        )
        coreRegistry = CoreRegistry(factories: [SameBoyCoreFactory()])
        settingsResolver = SettingsResolver(store: ScreenshotScene.settingsStore(repositories.settings))
        launchHistory = SessionLaunchHistory(store: repositories.settings)

        // Nothing has started yet, so this cleanup can't reach a Quick Play session, import or
        // game in progress. Cleanup that runs alongside them goes through inFlightFiles.
        _ = try? QuickPlayRetention(assetStore: fileStore).removeExpiredSessions()
        _ = try? libraryDeletion.purgeExpired()
        // Trim the patched ROM cache if space is short, and backfill source-image evidence, off
        // the main thread. Unreadable files are retried next launch; import suggestions use only
        // the records already filled.
        let fillSHA1 = FillImageSHA1(builds: repositories.builds, assetStore: fileStore)
        let fillFingerprints = imageFingerprintFiller
        let metadataRefresh = knownDumps.map {
            RefreshKnownDumpMetadata(builds: repositories.builds, settings: repositories.settings,
                index: $0, transactions: repositories.transactions)
        }
        Task.detached(priority: .utility) {
            _ = try? trimCache.execute()
            _ = try? fillSHA1.execute()
            _ = try? fillFingerprints.execute()
            try metadataRefresh?.execute()
        }
        try? fileStore.removeStagedFiles()
    }

    /// Rebuilds the fingerprints Import Review matches a new Build to its Game with. A backup leaves
    /// them out, so a restore runs this too instead of waiting for the next launch.
    var imageFingerprintFiller: FillImageFingerprints {
        FillImageFingerprints(assets: repositories.assets, fingerprints: repositories.fingerprints, assetStore: fileStore)
    }

    /// iOS leaves Documents/Inbox behind after handing over a shared file, and Files would show it
    /// in the Press Any folder. Each receipt removes its own copy, so an empty one can go. Only
    /// launch sweeps it: Documents isn't under a container's root, and tests share it.
    private static func removeEmptyInbox() {
        let inbox = URL.documentsDirectory.appendingPathComponent("Inbox", isDirectory: true)
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: inbox.path), contents.isEmpty else { return }
        try? FileManager.default.removeItem(at: inbox)
    }

    /// The file behind a Game's artwork, or nil when it has none or the file is missing.
    func artworkURL(for game: Game) -> URL? {
        guard let assetID = game.artworkAssetID,
              let asset = try? repositories.assets.fetchAsset(id: assetID),
              let url = try? fileStore.managedURL(relativePath: asset.relativePath),
              fileStore.fileExists(at: url) else { return nil }
        return url
    }

    /// The import is already committed. Artwork failure leaves it playable and retryable from
    /// the Game's artwork menu; a chosen image is never rechecked automatically.
    func fetchArtworkAfterImport(_ build: Build) {
        guard let artworkProvider, artworkTasks[build.id] == nil,
              let request = artworkLookup(gameID: build.gameID, importedBuild: build) else { return }
        let automatic = FindMissingGameArtwork(games: repositories.games, artwork: gameArtwork,
            settings: repositories.settings, providers: [artworkProvider], transactions: repositories.transactions)
        artworkTasks[build.id] = Task(priority: .utility) { [weak self] in
            defer { self?.artworkTasks[build.id] = nil }
            if (try? await automatic.execute(gameID: build.gameID, lookup: request.lookup,
                expectedPreferredBuildID: request.preferredBuildID)) == true {
                NotificationCenter.default.post(name: .libraryDidChange, object: nil)
            }
        }
    }

    /// Explicit checks work even when automatic artwork is off, and don't save the download.
    func findArtwork(gameID: UUID) async throws -> ProvidedArtwork? {
        guard let artworkProvider, let request = artworkLookup(gameID: gameID) else { return nil }
        return try await artworkProvider.artwork(for: request.lookup)
    }

    func proposeImportArtwork(_ plan: ROMImportPlan) async throws -> ImportArtworkProposal? {
        guard let artworkProvider,
              try AutomaticArtworkSetting(store: repositories.settings).load() else { return nil }
        let gameID: UUID?
        switch plan.disposition {
        case .createGame: gameID = nil
        case .addBuild(let id): gameID = id
        case .duplicateExisting: return nil
        }
        let game = try gameID.flatMap { try repositories.games.fetchGame(id: $0) }
        if gameID != nil, game == nil { return nil }
        let incoming = Build(id: plan.analysis.transactionID, gameID: gameID ?? plan.analysis.transactionID,
            system: plan.analysis.header.system, displayName: plan.buildDisplayName,
            imageAssetID: plan.analysis.transactionID, imageSHA256: plan.analysis.sha256,
            imageSHA1: plan.analysis.imageSHA1, sourceKind: .importedImage,
            baseGameReference: plan.baseGameReference, createdAt: .distantPast, modifiedAt: .distantPast)
        let builds = try gameID.map { try repositories.builds.fetchBuilds(gameID: $0) } ?? []
        let incomingIsPreferred = gameID == nil || plan.markAsPreferred
        let preferred = incomingIsPreferred ? incoming : builds.first { $0.id == game?.preferredBuildID }
        let ordered = [preferred, incoming].compactMap { $0 } + builds
        guard let lookup = artworkLookup(in: ordered) else { return nil }
        let provided: ProvidedArtwork?
        if let game {
            provided = try await missingArtworkFinder.find(gameID: game.id, lookup: lookup,
                expectedPreferredBuildID: game.preferredBuildID)
        } else {
            provided = try await artworkProvider.artwork(for: lookup)
        }
        try Task.checkCancellation()
        guard let provided, try AutomaticArtworkSetting(store: repositories.settings).load() else { return nil }
        return ImportArtworkProposal(artwork: provided, destinationGameID: gameID,
            preferredBuildID: game?.preferredBuildID, incomingIsPreferred: incomingIsPreferred)
    }

    func applyImportArtworkProposal(_ result: ROMImportResult, _ proposal: ImportArtworkProposal) throws {
        guard result.createdNewBuild,
              proposal.destinationGameID.map({ $0 == result.build.gameID }) ?? result.createdNewGame else { return }
        let preferred = proposal.incomingIsPreferred ? result.build.id : proposal.preferredBuildID
        try missingArtworkFinder.apply(proposal.artwork, gameID: result.build.gameID, expectedPreferredBuildID: preferred)
    }

    struct MissingArtworkProgress: Sendable {
        let total: Int
        var checked = 0
        var found = 0
        var failed = 0
    }

    struct MissingArtworkProposal: Identifiable, Sendable {
        let id: UUID
        let gameTitle: String
        let preferredBuildID: UUID?
        let artworkChoice: String?
        let imageURL: URL
        let provenance: ArtworkProvenance
    }

    struct MissingArtworkSearch: Sendable {
        let progress: MissingArtworkProgress
        let proposals: [MissingArtworkProposal]
    }

    private var missingArtworkFinder: FindMissingGameArtwork {
        FindMissingGameArtwork(games: repositories.games, artwork: gameArtwork,
            settings: repositories.settings, providers: artworkProvider.map { [$0] } ?? [],
            transactions: repositories.transactions)
    }

    func findMissingArtwork(proposalDirectory: URL,
                            onProgress: (MissingArtworkProgress) -> Void = { _ in }) async throws -> MissingArtworkSearch {
        let games = try repositories.games.fetchGames().filter { $0.artworkAssetID == nil }
        let finder = missingArtworkFinder
        try FileManager.default.createDirectory(at: proposalDirectory, withIntermediateDirectories: true)
        var progress = MissingArtworkProgress(total: games.count)
        var proposals: [MissingArtworkProposal] = []
        onProgress(progress)
        for game in games {
            try Task.checkCancellation()
            if let request = artworkLookup(gameID: game.id) {
                do {
                    let choice = try gameArtwork.choiceToken(gameID: game.id)
                    if let provided = try await finder.find(gameID: game.id, lookup: request.lookup,
                        expectedPreferredBuildID: request.preferredBuildID, trigger: .userRequested) {
                        try Task.checkCancellation()
                        let image = try ArtworkImage.downscaled(provided.data, fileExtension: provided.fileExtension)
                        let url = proposalDirectory.appendingPathComponent(game.id.uuidString).appendingPathExtension("png")
                        try image.data.write(to: url, options: .atomic)
                        proposals.append(MissingArtworkProposal(id: game.id, gameTitle: game.primaryTitle,
                            preferredBuildID: request.preferredBuildID, artworkChoice: choice,
                            imageURL: url, provenance: provided.provenance))
                        progress.found += 1
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    try Task.checkCancellation()
                    progress.failed += 1
                }
            }
            progress.checked += 1
            onProgress(progress)
            await Task.yield()
        }
        return MissingArtworkSearch(progress: progress, proposals: proposals)
    }

    func applyMissingArtwork(_ proposal: MissingArtworkProposal) throws -> Bool {
        let provided = ProvidedArtwork(data: try fileStore.readData(at: proposal.imageURL), fileExtension: "png",
            provenance: proposal.provenance)
        return try missingArtworkFinder.apply(provided, gameID: proposal.id,
            expectedPreferredBuildID: proposal.preferredBuildID, trigger: .userRequested,
            expectedArtworkChoice: proposal.artworkChoice)
    }

    private func artworkLookup(gameID: UUID, importedBuild: Build? = nil) -> (lookup: ArtworkLookup, preferredBuildID: UUID?)? {
        guard let game = try? repositories.games.fetchGame(id: gameID),
              let builds = try? repositories.builds.fetchBuilds(gameID: gameID) else { return nil }
        let preferred = builds.first { $0.id == game.preferredBuildID }
        let ordered = [preferred, importedBuild].compactMap { $0 } + builds
        guard let lookup = artworkLookup(in: ordered) else { return nil }
        return (lookup, game.preferredBuildID)
    }

    private func artworkLookup(in builds: [Build]) -> ArtworkLookup? {
        guard let knownDumps else { return nil }
        var visited: Set<UUID> = []
        for build in builds where visited.insert(build.id).inserted {
            if let lookup = knownDumps.artworkLookup(for: build, lookup: { try? repositories.builds.fetchBuild(id: $0) }) {
                return lookup
            }
        }
        return nil
    }

    /// Checks a typed cheat code with the core that plays the Build, without applying it. With no
    /// core that takes cheats, no code reads.
    func cheatCodeChecker(buildID: UUID) -> (String) -> Bool {
        guard let build = try? repositories.builds.fetchBuild(id: buildID) else { return { _ in false } }
        let factory = build.corePin.flatMap { try? coreRegistry.factory(for: $0.descriptor) }
            ?? (try? coreRegistry.latestFactory(system: build.system))
        guard let core = try? factory?.makeCore(), let cheats = core as? any CheatCapability else { return { _ in false } }
        return { cheats.isValidCheatCode($0) }
    }

    func makeEmulationSession() -> EmulationSession {
        let ownership = plus.ownership
        return EmulationSession(
            builds: repositories.builds,
            profiles: repositories.saveProfiles,
            states: repositories.saveStates,
            assets: repositories.assets,
            assetStore: fileStore,
            imageResolver: launchImageResolver,
            coreRegistry: coreRegistry,
            settings: settingsResolver,
            launchHistory: launchHistory,
            transactions: repositories.transactions,
            thumbnails: PNGFrameEncoder(),
            deletion: libraryDeletion,
            inFlight: inFlightFiles,
            cheats: repositories.cheats,
            keepsAutoStateHistory: { ownership.keepsAutoStateHistory },
            writesTimedStates: { ownership.isOwned },
            choosesHardwareModel: { ownership.appliesHardwareModel }
        )
    }

    /// Stops any running library session first, since its final battery flush decides whether
    /// the new context's Auto State is still safe to restore.
    func prepareLaunch(context: LaunchContext) -> PreparedLaunch {
        stopActiveSession(createAutoState: true)
        let session = makeEmulationSession()
        let policy = session.autoResumePolicy(for: context)
        let autoState = policy == .never ? nil : (try? session.resumableAutoState(for: context)) ?? nil
        return PreparedLaunch(
            context: context, session: session, policy: policy, autoState: autoState,
            autoStateNeedsOtherHardware: autoState.flatMap(session.hardwareFamilyNeeded) != nil
        )
    }

    func start(_ launch: PreparedLaunch, resume: Bool) throws -> AutoStateRestore {
        let restore = try launch.session.start(
            context: launch.context,
            resumeFrom: resume ? launch.autoState : nil
        )
        activeSession = launch.session
        return restore
    }

    func launchRestoration() throws -> SessionLaunchAction {
        guard let context = try launchHistory.context() else { return .library }
        guard let build = try repositories.builds.fetchBuild(id: context.buildID), build.gameID == context.gameID,
              let profile = try repositories.saveProfiles.fetchSaveProfile(id: context.saveProfileID),
              profile.gameID == context.gameID else {
            try launchHistory.closed()
            return .library
        }
        let checkpoint = try repositories.saveStates.fetchSaveStates(
            buildID: context.buildID, saveProfileID: context.saveProfileID
        ).filter { $0.kind == .crashRecovery }.max { $0.createdAt < $1.createdAt }
        return try launchHistory.launchAction(checkpoint: checkpoint)
    }

    func prepareRecovery(context: LaunchContext, checkpoint: SaveState) -> PreparedLaunch {
        let session = makeEmulationSession()
        return PreparedLaunch(
            context: context, session: session, policy: session.autoResumePolicy(for: context), autoState: checkpoint
        )
    }

    func startNormallyAfterCrash() throws {
        try launchHistory.closed()
    }

    /// Unset, unreadable or incompatible layouts use Game Boy without changing stored settings.
    func controllerStyle(system: GameSystem, gameID: UUID? = nil, buildID: UUID? = nil) -> TouchControlStyle {
        let style = launchSetting(
            TouchControlStyle.self, .controllerLayout, system: system, gameID: gameID, buildID: buildID
        )
        return (ScreenshotScene.layoutOverride ?? style ?? .gameBoy).forGameplay(
            controllerConnected: false, playtilesSupported: ControllerLayoutAvailability.supportsPlaytiles
        )
    }

    func controllerStyle(for context: LaunchContext) -> TouchControlStyle {
        (ScreenshotScene.layoutOverride ?? launchSetting(TouchControlStyle.self, .controllerLayout, for: context) ?? .gameBoy)
            .forGameplay(controllerConnected: false, playtilesSupported: ControllerLayoutAvailability.supportsPlaytiles)
    }

    /// The game picture's scaling for a launch. Unset or unreadable means integer scaling.
    /// Unset or unreadable means following the phone.
    func orientation(system: GameSystem, gameID: UUID? = nil, buildID: UUID? = nil) -> ScreenOrientation {
        launchSetting(ScreenOrientation.self, .orientation, system: system, gameID: gameID, buildID: buildID) ?? .automatic
    }

    func orientation(for context: LaunchContext) -> ScreenOrientation {
        launchSetting(ScreenOrientation.self, .orientation, for: context) ?? .automatic
    }

    func screenScaling(system: GameSystem, gameID: UUID? = nil, buildID: UUID? = nil) -> ScreenScaling {
        launchSetting(ScreenScaling.self, .screenScaling, system: system, gameID: gameID, buildID: buildID) ?? .integer
    }

    func screenScaling(for context: LaunchContext) -> ScreenScaling {
        launchSetting(ScreenScaling.self, .screenScaling, for: context) ?? .integer
    }

    /// Off without Plus, whatever is stored.
    func lcdFilter(system: GameSystem, gameID: UUID? = nil, buildID: UUID? = nil) -> LCDFilter {
        ScreenshotScene.lcdFilterOverride
            ?? plus.effective(launchSetting(LCDFilter.self, .lcdFilter, system: system, gameID: gameID, buildID: buildID) ?? .off)
    }

    func lcdFilter(for context: LaunchContext) -> LCDFilter {
        ScreenshotScene.lcdFilterOverride ?? plus.effective(launchSetting(LCDFilter.self, .lcdFilter, for: context) ?? .off)
    }

    func colorCorrection(system: GameSystem, gameID: UUID? = nil, buildID: UUID? = nil) -> ColorCorrection {
        launchSetting(ColorCorrection.self, .colorCorrection, system: system, gameID: gameID, buildID: buildID) ?? .defaultValue
    }

    func colorCorrection(for context: LaunchContext) -> ColorCorrection {
        launchSetting(ColorCorrection.self, .colorCorrection, for: context) ?? .defaultValue
    }

    func dmgPalette(system: GameSystem, gameID: UUID? = nil, buildID: UUID? = nil) -> DMGPalette {
        launchSetting(DMGPalette.self, .dmgPalette, system: system, gameID: gameID, buildID: buildID) ?? .defaultValue
    }

    func dmgPalette(for context: LaunchContext) -> DMGPalette {
        launchSetting(DMGPalette.self, .dmgPalette, for: context) ?? .defaultValue
    }

    func advanceColors(system: GameSystem, gameID: UUID? = nil, buildID: UUID? = nil) -> AdvanceColors {
        launchSetting(AdvanceColors.self, .advanceColors, system: system, gameID: gameID, buildID: buildID) ?? .gameBoyAdvance
    }

    func advanceColors(for context: LaunchContext) -> AdvanceColors {
        launchSetting(AdvanceColors.self, .advanceColors, for: context) ?? .gameBoyAdvance
    }

    /// A Game's Builds, for suggesting a new one's name and roles. Unreadable means none.
    func builds(in gameID: UUID) -> [Build] {
        (try? repositories.builds.fetchBuilds(gameID: gameID)) ?? []
    }

    func frameBlending(for context: LaunchContext) -> FrameBlending {
        launchSetting(FrameBlending.self, .frameBlending, for: context) ?? .off
    }

    func frameBlending(system: GameSystem, gameID: UUID? = nil, buildID: UUID? = nil) -> FrameBlending {
        launchSetting(FrameBlending.self, .frameBlending, system: system, gameID: gameID, buildID: buildID) ?? .off
    }

    func fastForwardSpeed(for context: LaunchContext) -> FastForwardSpeed {
        launchSetting(FastForwardSpeed.self, .fastForwardSpeed, for: context) ?? .x2
    }

    func fastForwardSpeed(system: GameSystem, gameID: UUID? = nil, buildID: UUID? = nil) -> FastForwardSpeed {
        launchSetting(FastForwardSpeed.self, .fastForwardSpeed, system: system, gameID: gameID, buildID: buildID) ?? .x2
    }

    func fastForwardAudio(for context: LaunchContext) -> FastForwardAudio {
        launchSetting(FastForwardAudio.self, .fastForwardAudio, for: context) ?? .muted
    }

    func fastForwardAudio(system: GameSystem, gameID: UUID? = nil, buildID: UUID? = nil) -> FastForwardAudio {
        launchSetting(FastForwardAudio.self, .fastForwardAudio, system: system, gameID: gameID, buildID: buildID) ?? .muted
    }

    /// The scope an open game's settings sheet edits: the Game for a library game, the system for
    /// Quick Play, which has no Game yet. Display settings still resolve through the Build.
    func gameplaySettingsTarget(for context: LaunchContext) -> GameplaySettingsTarget? {
        guard let build = try? repositories.builds.fetchBuild(id: context.buildID) else { return nil }
        return GameplaySettingsTarget(
            title: "Game Settings",
            scope: .game(build.gameID),
            system: build.system,
            gameID: build.gameID,
            buildID: build.id
        )
    }

    func gameplaySettingsTarget(system: GameSystem) -> GameplaySettingsTarget {
        GameplaySettingsTarget(
            title: "\(system.displayName) Settings",
            scope: .system(system),
            system: system,
            gameID: nil,
            buildID: nil
        )
    }

    /// Whether a game's header marks it for a Game Boy Color only (CGB flag 0xC0). With no Build
    /// given, every Build of the Game must be marked. A Build without a stored header counts as no.
    func marksGameBoyColorOnly(gameID: UUID?, buildID: UUID?) -> Bool {
        let headers = buildHeaders(gameID: gameID, buildID: buildID)
        return !headers.isEmpty && headers.allSatisfy { $0?.cgbFlag == 0xC0 }
    }

    /// Whether a game is a Game Boy Camera cartridge (type 0xFC), so its settings show Game Boy
    /// Camera. With no Build given, any Build of the Game counts.
    func hasCameraCartridge(gameID: UUID?, buildID: UUID?) -> Bool {
        buildHeaders(gameID: gameID, buildID: buildID).contains { $0?.cartridgeType == 0xFC }
    }

    /// The stored header of the Build, or of each Build of the Game, nil where none is stored.
    private func buildHeaders(gameID: UUID?, buildID: UUID?) -> [ImageFingerprint?] {
        let builds: [Build]
        if let buildID {
            builds = (try? repositories.builds.fetchBuild(id: buildID)).map { [$0] } ?? []
        } else if let gameID {
            builds = (try? repositories.builds.fetchBuilds(gameID: gameID)) ?? []
        } else {
            builds = []
        }
        guard !builds.isEmpty,
              let fingerprints = try? repositories.fingerprints.fetchFingerprints(imageSHA256s: builds.map(\.imageSHA256))
        else { return [] }
        return builds.map { fingerprints[$0.imageSHA256] }
    }

    /// The display settings for an open game, resolved down to its Build.
    func gameplayDisplay(for target: GameplaySettingsTarget) -> GameplayDisplaySettings {
        GameplayDisplaySettings(
            controlStyle: controllerStyle(system: target.system, gameID: target.gameID, buildID: target.buildID),
            orientation: orientation(system: target.system, gameID: target.gameID, buildID: target.buildID),
            screenScaling: screenScaling(system: target.system, gameID: target.gameID, buildID: target.buildID),
            lcdFilter: lcdFilter(system: target.system, gameID: target.gameID, buildID: target.buildID),
            colorCorrection: colorCorrection(system: target.system, gameID: target.gameID, buildID: target.buildID),
            dmgPalette: dmgPalette(system: target.system, gameID: target.gameID, buildID: target.buildID),
            advanceColors: advanceColors(system: target.system, gameID: target.gameID, buildID: target.buildID),
            frameBlending: frameBlending(system: target.system, gameID: target.gameID, buildID: target.buildID),
            fastForwardSpeed: fastForwardSpeed(system: target.system, gameID: target.gameID, buildID: target.buildID),
            fastForwardAudio: fastForwardAudio(system: target.system, gameID: target.gameID, buildID: target.buildID),
            camera: gameBoyCamera(system: target.system, gameID: target.gameID, buildID: target.buildID)
        )
    }

    /// Unset or unreadable means the rear camera.
    func gameBoyCamera(system: GameSystem, gameID: UUID? = nil, buildID: UUID? = nil) -> GameBoyCamera {
        launchSetting(GameBoyCamera.self, .gameBoyCamera, system: system, gameID: gameID, buildID: buildID) ?? .defaultValue
    }

    func gameBoyCamera(for context: LaunchContext) -> GameBoyCamera {
        launchSetting(GameBoyCamera.self, .gameBoyCamera, for: context) ?? .defaultValue
    }

    func saveStateSlots() -> SaveStateSlots { appSetting(SaveStateSlots.self, .saveStateSlots) ?? .off }
    func nameNewStates() -> Bool { appSetting(Bool.self, .nameNewStates) ?? false }

    /// App-wide. Unset or unreadable means following the silent switch.
    func soundMode() -> SoundMode {
        appSetting(SoundMode.self, .soundMode) ?? .followSilentSwitch
    }

    /// Saves the app-wide Sound setting, as the game menu does.
    func setSoundMode(_ mode: SoundMode) throws {
        try repositories.settings.set(mode, key: SettingKey.soundMode.rawValue, scope: .app)
    }

    /// App-wide. Unset or unreadable means matching Light or Dark Mode.
    func controllerTheme() -> ControllerTheme {
        appSetting(ControllerTheme.self, .controllerTheme) ?? .matchSystem
    }

    /// App-wide. Unset or unreadable means off: only the logo opens the menu.
    func tapGameForMenu() -> Bool {
        appSetting(Bool.self, .tapGameForMenu) ?? false
    }

    /// App-wide. Unset or unreadable means on: a controller hides the touch controls until a touch.
    func hidesTouchControlsWithController() -> Bool {
        appSetting(Bool.self, .hideTouchControlsWithController) ?? true
    }

    /// App-wide. Unset or unreadable means light.
    func touchHaptics() -> TouchHaptics {
        appSetting(TouchHaptics.self, .touchHaptics) ?? .light
    }

    /// A setting stored at the app scope only, or nil when it's unset or unreadable.
    private func appSetting<Value: Decodable>(_ type: Value.Type, _ key: SettingKey) -> Value? {
        guard let json = try? repositories.settings.valueJSON(key: key.rawValue, scope: .app) else { return nil }
        return try? JSONDecoder().decode(type, from: Data(json.utf8))
    }

    /// A setting resolved through the App, System, Game and Build scopes, or nil when none sets it
    /// or it's unreadable.
    private func launchSetting<Value: Decodable>(
        _ type: Value.Type,
        _ key: SettingKey,
        system: GameSystem,
        gameID: UUID?,
        buildID: UUID?
    ) -> Value? {
        try? settingsResolver.decode(type, key: key.rawValue, system: system, gameID: gameID, buildID: buildID)
    }

    /// The same, for the Build a library launch plays.
    private func launchSetting<Value: Decodable>(
        _ type: Value.Type,
        _ key: SettingKey,
        for context: LaunchContext
    ) -> Value? {
        guard let build = try? repositories.builds.fetchBuild(id: context.buildID) else { return nil }
        return launchSetting(type, key, system: build.system, gameID: build.gameID, buildID: build.id)
    }

    func quickPlayAutoResumePolicy(system: GameSystem) -> AutoResumePolicy {
        launchSetting(AutoResumePolicy.self, .autoResumePolicy, system: system, gameID: nil, buildID: nil) ?? .always
    }

    func stopActiveSession(createAutoState: Bool = true) {
        guard let activeSession else { return }
        try? activeSession.stop(createAutoState: createAutoState)
        self.activeSession = nil
    }
}

extension Notification.Name {
    /// Posted when library records or play statistics change outside the screen showing them.
    static let libraryDidChange = Notification.Name("libraryDidChange")
}

/// Where an open game's settings sheet saves, and the Game and Build its settings resolve for.
struct GameplaySettingsTarget {
    let title: String
    let scope: SettingsScope
    let system: GameSystem
    let gameID: UUID?
    let buildID: UUID?
}

/// The settings an open game applies as they change.
struct GameplayDisplaySettings: Equatable {
    var controlStyle: TouchControlStyle
    var orientation: ScreenOrientation = .automatic
    var screenScaling: ScreenScaling
    var lcdFilter: LCDFilter
    var colorCorrection: ColorCorrection
    var dmgPalette: DMGPalette
    var advanceColors: AdvanceColors = .gameBoyAdvance
    var frameBlending: FrameBlending
    var fastForwardSpeed: FastForwardSpeed
    var fastForwardAudio: FastForwardAudio
    /// Only camera cartridges read it.
    var camera: GameBoyCamera = .defaultValue
}

struct PreparedLaunch {
    let context: LaunchContext
    let session: EmulationSession
    let policy: AutoResumePolicy
    /// Nil when there is nothing safe to restore or the policy is `.never`.
    let autoState: SaveState?
    /// The Auto State was made on hardware of another family than the game now runs on, so it
    /// can't resume and isn't offered.
    var autoStateNeedsOtherHardware = false
}

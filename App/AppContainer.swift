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
    let quickPlayWorkspace: QuickPlayWorkspace
    let quickPlayPromoter: PromoteQuickPlay
    let coreRegistry: CoreRegistry
    let settingsResolver: SettingsResolver
    let launchHistory: SessionLaunchHistory

    private(set) var activeSession: EmulationSession?

    var storageUsage: MeasureLibraryStorage {
        MeasureLibraryStorage(assets: repositories.assets, assetStore: fileStore)
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
            recipes: repositories.patchRecipes, assetStore: fileStore)
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
        return try AppContainer(rootURL: root)
    }

    init(rootURL: URL) throws {
        fileStore = try ManagedFileStore(rootURL: rootURL)
        sharedFileInbox = SharedFileInbox(store: fileStore)
        database = try AppDatabase(url: rootURL.appendingPathComponent("Library.sqlite"))
        try database.migrate()
        repositories = database.makeRepositories()

        integrityChecker = ManagedAssetIntegrityChecker(assets: repositories.assets, assetStore: fileStore)
        knownDumps = try? KnownDumpIndex.bundled()
        importAnalyzer = ROMImportAnalyzer(builds: repositories.builds, games: repositories.games,
            fingerprints: repositories.fingerprints,
            toolchainReports: repositories.toolchainReports,
            assetStore: fileStore, knownDumps: knownDumps)
        importCommitter = ImportCommitter(
            games: repositories.games,
            builds: repositories.builds,
            assets: repositories.assets,
            toolchainReports: repositories.toolchainReports,
            fingerprints: repositories.fingerprints,
            assetStore: fileStore,
            transactions: repositories.transactions
        )
        buildOperations = BuildOperations(
            games: repositories.games,
            builds: repositories.builds,
            profiles: repositories.saveProfiles,
            states: repositories.saveStates,
            recipes: repositories.patchRecipes,
            assets: repositories.assets,
            assetStore: fileStore,
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
        patchCreator = CreatePatchedBuild(
            games: repositories.games,
            builds: repositories.builds,
            recipes: repositories.patchRecipes,
            assets: repositories.assets,
            toolchainReports: repositories.toolchainReports,
            assetStore: fileStore,
            transactions: repositories.transactions
        )
        launchImageResolver = ResolveImageForLaunch(
            builds: repositories.builds,
            recipes: repositories.patchRecipes,
            assets: repositories.assets,
            assetStore: fileStore
        )
        exportFiles = ExportLibraryFiles(
            games: repositories.games,
            builds: repositories.builds,
            profiles: repositories.saveProfiles,
            assets: repositories.assets,
            assetStore: fileStore,
            images: launchImageResolver
        )
        exportsDirectory = URL.documentsDirectory.appendingPathComponent("Exports", isDirectory: true)
        toolchainRefresh = RefreshToolchainReports(
            reports: repositories.toolchainReports,
            images: launchImageResolver,
            assetStore: fileStore,
            detect: { ToolchainDetectorRegistry.standard.detect(image: $0, system: $1) }
        )
        attachVariableMap = AttachVariableMap(
            builds: repositories.builds,
            maps: repositories.variableMaps,
            assets: repositories.assets,
            assetStore: fileStore,
            transactions: repositories.transactions
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
            assetStore: fileStore
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
        settingsResolver = SettingsResolver(store: repositories.settings)
        launchHistory = SessionLaunchHistory(store: repositories.settings)

        _ = try? QuickPlayRetention(assetStore: fileStore).removeExpiredSessions()
        _ = try? libraryDeletion.purgeExpired()
        // Backfill source-image evidence off the main thread. Unreadable files are retried
        // next launch; import suggestions use only the records already filled.
        let fillSHA1 = FillImageSHA1(builds: repositories.builds, assetStore: fileStore)
        let fillFingerprints = FillImageFingerprints(assets: repositories.assets,
            fingerprints: repositories.fingerprints, assetStore: fileStore)
        let metadataRefresh = knownDumps.map {
            RefreshKnownDumpMetadata(builds: repositories.builds, settings: repositories.settings,
                index: $0, transactions: repositories.transactions)
        }
        Task.detached(priority: .utility) {
            _ = try? fillSHA1.execute()
            _ = try? fillFingerprints.execute()
            try metadataRefresh?.execute()
        }
        try? fileStore.removeStagedFiles()
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

    func makeEmulationSession() -> EmulationSession {
        EmulationSession(
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
            deletion: libraryDeletion
        )
    }

    /// Stops any running library session first, since its final battery flush decides whether
    /// the new context's Auto State is still safe to restore.
    func prepareLaunch(context: LaunchContext) -> PreparedLaunch {
        stopActiveSession(createAutoState: true)
        let session = makeEmulationSession()
        let policy = session.autoResumePolicy(for: context)
        let autoState = policy == .never ? nil : (try? session.resumableAutoState(for: context)) ?? nil
        return PreparedLaunch(context: context, session: session, policy: policy, autoState: autoState)
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

    /// The controller layout for a launch. Unset or unreadable means the Game Boy layout.
    func controllerStyle(system: GameSystem, gameID: UUID? = nil, buildID: UUID? = nil) -> TouchControlStyle {
        let style = launchSetting(
            TouchControlStyle.self, .controllerLayout, system: system, gameID: gameID, buildID: buildID
        )
        return ScreenshotScene.layoutOverride ?? style ?? .gameBoy
    }

    func controllerStyle(for context: LaunchContext) -> TouchControlStyle {
        ScreenshotScene.layoutOverride ?? launchSetting(TouchControlStyle.self, .controllerLayout, for: context) ?? .gameBoy
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

    func lcdFilter(system: GameSystem, gameID: UUID? = nil, buildID: UUID? = nil) -> LCDFilter {
        ScreenshotScene.lcdFilterOverride
            ?? launchSetting(LCDFilter.self, .lcdFilter, system: system, gameID: gameID, buildID: buildID)
            ?? .off
    }

    func lcdFilter(for context: LaunchContext) -> LCDFilter {
        ScreenshotScene.lcdFilterOverride ?? launchSetting(LCDFilter.self, .lcdFilter, for: context) ?? .off
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

    /// The display settings for an open game, resolved down to its Build.
    func gameplayDisplay(for target: GameplaySettingsTarget) -> GameplayDisplaySettings {
        GameplayDisplaySettings(
            controlStyle: controllerStyle(system: target.system, gameID: target.gameID, buildID: target.buildID),
            orientation: orientation(system: target.system, gameID: target.gameID, buildID: target.buildID),
            screenScaling: screenScaling(system: target.system, gameID: target.gameID, buildID: target.buildID),
            lcdFilter: lcdFilter(system: target.system, gameID: target.gameID, buildID: target.buildID),
            colorCorrection: colorCorrection(system: target.system, gameID: target.gameID, buildID: target.buildID),
            dmgPalette: dmgPalette(system: target.system, gameID: target.gameID, buildID: target.buildID),
            frameBlending: frameBlending(system: target.system, gameID: target.gameID, buildID: target.buildID),
            fastForwardSpeed: fastForwardSpeed(system: target.system, gameID: target.gameID, buildID: target.buildID),
            fastForwardAudio: fastForwardAudio(system: target.system, gameID: target.gameID, buildID: target.buildID)
        )
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
    var frameBlending: FrameBlending
    var fastForwardSpeed: FastForwardSpeed
    var fastForwardAudio: FastForwardAudio
}

struct PreparedLaunch {
    let context: LaunchContext
    let session: EmulationSession
    let policy: AutoResumePolicy
    /// Nil when there is nothing safe to restore or the policy is `.never`.
    let autoState: SaveState?
}

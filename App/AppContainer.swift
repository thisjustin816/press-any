import AssetStorage
import EmulationCore
import EmulationSession
import EmulatorApplication
import EmulatorDomain
import Foundation
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

    let importAnalyzer: ROMImportAnalyzer
    let importCommitter: ImportCommitter
    let buildOperations: BuildOperations
    let createBlankSaveProfile: CreateBlankSaveProfile
    let duplicateSaveProfile: DuplicateSaveProfile
    let setSaveProfileBadge: SetSaveProfileBadge
    let libraryDeletion: LibraryDeletionOperations
    let importBatterySave: ImportBatterySave
    let replaceBatterySave: ReplaceBatterySave
    let preferredLaunchResolver: ResolvePreferredLaunchContext
    let patchCreator: CreatePatchedBuild
    let launchImageResolver: ResolveImageForLaunch
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

    private(set) var activeSession: EmulationSession?

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
        return try AppContainer(rootURL: root)
    }

    init(rootURL: URL) throws {
        fileStore = try ManagedFileStore(rootURL: rootURL)
        sharedFileInbox = SharedFileInbox(store: fileStore)
        database = try AppDatabase(url: rootURL.appendingPathComponent("Library.sqlite"))
        try database.migrate()
        repositories = database.makeRepositories()

        integrityChecker = ManagedAssetIntegrityChecker(assets: repositories.assets, assetStore: fileStore)
        importAnalyzer = ROMImportAnalyzer(builds: repositories.builds, assetStore: fileStore)
        importCommitter = ImportCommitter(
            games: repositories.games,
            builds: repositories.builds,
            assets: repositories.assets,
            toolchainReports: repositories.toolchainReports,
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
            transactions: repositories.transactions
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

        _ = try? QuickPlayRetention(assetStore: fileStore).removeExpiredSessions()
        _ = try? libraryDeletion.purgeExpired()
        try? fileStore.removeStagedFiles()
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
            thumbnails: PNGFrameEncoder()
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
            screenScaling: screenScaling(system: target.system, gameID: target.gameID, buildID: target.buildID),
            lcdFilter: lcdFilter(system: target.system, gameID: target.gameID, buildID: target.buildID),
            frameBlending: frameBlending(system: target.system, gameID: target.gameID, buildID: target.buildID),
            fastForwardSpeed: fastForwardSpeed(system: target.system, gameID: target.gameID, buildID: target.buildID),
            fastForwardAudio: fastForwardAudio(system: target.system, gameID: target.gameID, buildID: target.buildID)
        )
    }

    /// App-wide. Unset or unreadable means following the silent switch.
    func soundMode() -> SoundMode {
        appSetting(SoundMode.self, .soundMode) ?? .followSilentSwitch
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
    /// Posted when Games or Builds change outside the screen showing them.
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
    var screenScaling: ScreenScaling
    var lcdFilter: LCDFilter
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

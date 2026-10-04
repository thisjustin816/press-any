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
    let database: AppDatabase
    let repositories: GRDBRepositorySet

    let importAnalyzer: ROMImportAnalyzer
    let importCommitter: ImportCommitter
    let buildOperations: BuildOperations
    let createBlankSaveProfile: CreateBlankSaveProfile
    let duplicateSaveProfile: DuplicateSaveProfile
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
        let root = ApplicationDataLocation.root(in: support)
        return try AppContainer(rootURL: root)
    }

    init(rootURL: URL) throws {
        fileStore = try ManagedFileStore(rootURL: rootURL)
        database = try AppDatabase(url: rootURL.appendingPathComponent("Library.sqlite"))
        try database.migrate()
        repositories = database.makeRepositories()

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
            recipes: repositories.patchRecipes,
            assets: repositories.assets,
            assetStore: fileStore,
            transactions: repositories.transactions
        )
        createBlankSaveProfile = CreateBlankSaveProfile(
            games: repositories.games,
            profiles: repositories.saveProfiles
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
            profiles: repositories.saveProfiles,
            assets: repositories.assets,
            assetStore: fileStore
        )
        coreRegistry = CoreRegistry(factories: [SameBoyCoreFactory()])
        settingsResolver = SettingsResolver(store: repositories.settings)

        _ = try? QuickPlayRetention(assetStore: fileStore).removeExpiredSessions()
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
            settings: settingsResolver
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
        return style ?? .gameBoy
    }

    func controllerStyle(for context: LaunchContext) -> TouchControlStyle {
        launchSetting(TouchControlStyle.self, .controllerLayout, for: context) ?? .gameBoy
    }

    /// The game picture's scaling for a launch. Unset or unreadable means integer scaling.
    func screenScaling(system: GameSystem, gameID: UUID? = nil, buildID: UUID? = nil) -> ScreenScaling {
        launchSetting(ScreenScaling.self, .screenScaling, system: system, gameID: gameID, buildID: buildID) ?? .integer
    }

    func screenScaling(for context: LaunchContext) -> ScreenScaling {
        launchSetting(ScreenScaling.self, .screenScaling, for: context) ?? .integer
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
    /// Posted when Games are added or removed outside the library screen.
    static let libraryDidChange = Notification.Name("libraryDidChange")
}

struct PreparedLaunch {
    let context: LaunchContext
    let session: EmulationSession
    let policy: AutoResumePolicy
    /// Nil when there is nothing safe to restore or the policy is `.never`.
    let autoState: SaveState?
}

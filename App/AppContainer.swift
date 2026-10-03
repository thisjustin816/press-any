import AssetStorage
import EmulationCore
import EmulationSession
import EmulatorApplication
import EmulatorDomain
import Foundation
import Importing
import Patching
import PersistenceGRDB
import QuickPlay
import SameBoyAdapter

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
    let preferredLaunchResolver: ResolvePreferredLaunchContext
    let patchCreator: CreatePatchedBuild
    let launchImageResolver: ResolveImageForLaunch
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
            assetStore: fileStore,
            transactions: repositories.transactions
        )
        buildOperations = BuildOperations(
            games: repositories.games,
            builds: repositories.builds,
            profiles: repositories.saveProfiles,
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
            assetStore: fileStore,
            transactions: repositories.transactions
        )
        launchImageResolver = ResolveImageForLaunch(
            builds: repositories.builds,
            recipes: repositories.patchRecipes,
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

    func startPermanentSession(context: LaunchContext) throws -> EmulationSession {
        if let activeSession {
            try activeSession.stop(createAutoState: true)
        }
        let session = makeEmulationSession()
        try session.start(context: context)
        activeSession = session
        return session
    }

    func stopActiveSession(createAutoState: Bool = true) {
        guard let activeSession else { return }
        try? activeSession.stop(createAutoState: createAutoState)
        self.activeSession = nil
    }
}

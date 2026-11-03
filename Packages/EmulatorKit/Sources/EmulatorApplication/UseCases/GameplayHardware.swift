import EmulationCore
import EmulatorDomain
import Foundation

/// The hardware Automatic runs each Build on. Automatic reads the game's header and the Super Game
/// Boy borders setting (`CartridgeHints.automaticModel(superGameBoyBorders:)`), except that a
/// Build that already has save states the first time it starts on Automatic keeps the hardware its
/// newest state was made on, so its states keep loading. The first start records which of the two
/// applies under `SettingKey.automaticHardware`, so states made afterwards never pin a Build.
public struct AutomaticHardware: Sendable {
    private let profiles: any SaveProfileRepository
    private let states: any SaveStateRepository
    private let assets: any ManagedAssetRepository
    private let assetStore: any AssetStore
    private let coreRegistry: CoreRegistry
    private let settings: (any SettingsStore)?

    /// Without `settings` nothing is recorded, every start decides again, and borders are off.
    public init(
        profiles: any SaveProfileRepository,
        states: any SaveStateRepository,
        assets: any ManagedAssetRepository,
        assetStore: any AssetStore,
        coreRegistry: CoreRegistry,
        settings: (any SettingsStore)?
    ) {
        self.profiles = profiles
        self.states = states
        self.assets = assets
        self.assetStore = assetStore
        self.coreRegistry = coreRegistry
        self.settings = settings
    }

    /// What Automatic runs `build` on: the hardware its states keep, or the header rule. Before
    /// the first start, a Build with states counts as keeping them. `image` is the Build's image
    /// when it's at hand; otherwise the image file is read, and when it's missing, as a patched
    /// Build's evicted image can be, the system decides (`HardwareModel.automaticFallback`).
    public func hardware(for build: Build, image: Data? = nil) -> HardwareModel {
        switch recorded(for: build) {
        case .automatic?: headerModel(of: build, image: image)
        case let kept?: kept
        case nil: newestStateModel(of: build) ?? headerModel(of: build, image: image)
        }
    }

    /// Records, unless it already is, whether `build` keeps the hardware of its newest save state
    /// or follows the header rule, and returns what it runs on. With `keepsStateHardware` false, as
    /// for a Build whose Model is set by hand, it follows the rule even when it has save states.
    @discardableResult
    public func record(for build: Build, image: Data, keepsStateHardware: Bool) throws -> HardwareModel {
        if recorded(for: build) == nil {
            let kept = keepsStateHardware ? newestStateModel(of: build) : nil
            try settings?.set(kept ?? .automatic, key: SettingKey.automaticHardware.rawValue, scope: .build(build.id))
            if let kept { return kept }
        }
        return hardware(for: build, image: image)
    }

    /// The recorded choice: `.automatic` for the header rule, another model for the hardware the
    /// Build's states keep, or nil before the first start or when it can't be read.
    public func recorded(for build: Build) -> HardwareModel? {
        guard let json = try? settings?.valueJSON(key: SettingKey.automaticHardware.rawValue, scope: .build(build.id)) else {
            return nil
        }
        return try? JSONDecoder().decode(HardwareModel.self, from: Data(json.utf8))
    }

    /// Whether Super Game Boy borders are on for `build`. Unset or unreadable means off.
    public func superGameBoyBorders(for build: Build) -> Bool {
        guard let settings else { return false }
        let borders = try? SettingsResolver(store: settings).decode(
            Bool.self, key: SettingKey.superGameBoyBorders.rawValue,
            system: build.system, gameID: build.gameID, buildID: build.id
        )
        return borders ?? false
    }

    private func headerModel(of build: Build, image: Data?) -> HardwareModel {
        let header = (image ?? storedImage(of: build)).flatMap(CartridgeHints.init(image:))
        return header?.automaticModel(superGameBoyBorders: superGameBoyBorders(for: build))
            ?? HardwareModel.automaticFallback(for: build.system)
    }

    private func storedImage(of build: Build) -> Data? {
        guard let asset = try? assets.fetchAsset(id: build.imageAssetID),
              let url = try? assetStore.managedURL(relativePath: asset.relativePath),
              assetStore.fileExists(at: url) else { return nil }
        return try? assetStore.readData(at: url)
    }

    /// The model the Build's newest save state, of any kind and with any profile, was made on.
    /// A state that can't be read, or doesn't name its model, gives way to the next newest. Nil
    /// for a Build without states.
    private func newestStateModel(of build: Build) -> HardwareModel? {
        let made = (try? profiles.fetchSaveProfiles(gameID: build.gameID))?
            .flatMap { (try? states.fetchSaveStates(buildID: build.id, saveProfileID: $0.id)) ?? [] }
            .sorted { $0.createdAt > $1.createdAt } ?? []
        // A Build with states has run, so it has a pin to read them with.
        guard !made.isEmpty, let pin = build.corePin,
              let core = (try? coreRegistry.factory(for: pin.descriptor).makeCore()) as? any HardwareModelCapability else {
            return nil
        }
        for state in made {
            guard let asset = try? assets.fetchAsset(id: state.stateAssetID),
                  let url = try? assetStore.managedURL(relativePath: asset.relativePath),
                  let data = try? assetStore.readData(at: url),
                  let model = core.hardwareModel(ofState: data) else { continue }
            return model
        }
        return nil
    }
}

/// The hardware games play on and that each settings scope shows: the Model setting, which needs
/// Plus for anything but Automatic, and for Automatic the hardware `AutomaticHardware` picks.
public struct GameplayHardware: Sendable {
    private let builds: any BuildRepository
    private let settings: SettingsResolver?
    private let automatic: AutomaticHardware
    private let choosesModel: @Sendable () -> Bool

    /// `choosesModel` says whether a stored Model applies; without it, or without `settings`, every
    /// game plays on Automatic.
    public init(
        builds: any BuildRepository,
        settings: SettingsResolver?,
        automatic: AutomaticHardware,
        choosesModel: @escaping @Sendable () -> Bool
    ) {
        self.builds = builds
        self.settings = settings
        self.automatic = automatic
        self.choosesModel = choosesModel
    }

    /// The Model setting resolved for the scopes given: the stored choice when it applies,
    /// otherwise Automatic, as when it can't be read.
    public func model(system: GameSystem, gameID: UUID? = nil, buildID: UUID? = nil) -> HardwareModel {
        guard choosesModel() else { return .automatic }
        let model = try? settings?.decode(
            HardwareModel.self, key: SettingKey.hardwareModel.rawValue, system: system, gameID: gameID, buildID: buildID
        )
        return model ?? .automatic
    }

    /// What `build` plays on, never Automatic. `image` is the Build's image when it's at hand.
    public func hardware(for build: Build, image: Data? = nil) -> HardwareModel {
        let model = model(system: build.system, gameID: build.gameID, buildID: build.id)
        return model == .automatic ? automatic.hardware(for: build, image: image) : model
    }

    /// Records whether `build` keeps its states' hardware under Automatic, the first time it
    /// starts, and returns what it plays on. A Build whose Model is set by hand records the header
    /// rule, so its states don't decide what Automatic picks if Model goes back to Automatic.
    public func recordForStart(_ build: Build, image: Data) throws -> HardwareModel {
        let model = model(system: build.system, gameID: build.gameID, buildID: build.id)
        let automaticModel = try automatic.record(for: build, image: image, keepsStateHardware: model == .automatic)
        return model.resolved(automatic: automaticModel)
    }

    /// The models games at a settings scope play on, never Automatic and never empty. A Build
    /// gives its own; a Game each of its Builds', in order with no repeats; a system, or a Game
    /// with no Builds, the Model when one is chosen, and otherwise every model Automatic picks
    /// among for that system (`HardwareModel.automaticChoices`).
    public func hardware(system: GameSystem, gameID: UUID? = nil, buildID: UUID? = nil) -> [HardwareModel] {
        if let buildID, let build = try? builds.fetchBuild(id: buildID) {
            return [hardware(for: build)]
        }
        if let gameID, let gameBuilds = try? builds.fetchBuilds(gameID: gameID), !gameBuilds.isEmpty {
            var models: [HardwareModel] = []
            for build in gameBuilds {
                let model = hardware(for: build)
                if !models.contains(model) { models.append(model) }
            }
            return models
        }
        let model = model(system: system, gameID: gameID)
        guard model == .automatic else { return [model] }
        let borders = try? settings?.decode(
            Bool.self, key: SettingKey.superGameBoyBorders.rawValue, system: system, gameID: gameID
        )
        return HardwareModel.automaticChoices(for: system, superGameBoyBorders: borders ?? false)
    }
}

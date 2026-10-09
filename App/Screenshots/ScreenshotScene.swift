import EmulatorApplication
import EmulatorDomain
import Foundation
import GameplayInput
import Importing
import Patching

/// A screen the app opens straight to at launch, so `Scripts/take-screenshots.sh` can capture it
/// without tapping through the file picker. Set with the launch argument
/// `-ScreenshotScene <scene>[:<ROM file>]`, which only Debug builds read.
enum ScreenshotScene: Equatable {
    case library
    case settings
    case game(romFile: String)
    case buildInfo(romFile: String)
    case importReview(romFile: String)
    case play(romFile: String)
    case quickPlay(romFile: String)
    case quickPlayInfo(romFile: String)

    static let current: ScreenshotScene? = {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "ScreenshotScene").flatMap(ScreenshotScene.init(argument:))
        #else
        return nil
        #endif
    }()

    /// Set with `-ScreenshotGamepad YES`: gameplay acts as if a controller were connected, so its
    /// touch controls hide, whatever controllers the simulator has.
    static let simulatesGamepad = flag("ScreenshotGamepad")

    /// Set with `-ScreenshotLayout <layout>`, such as `playtiles`: gameplay uses that controller
    /// layout instead of the one in Settings, which stays as it is.
    static let layoutOverride: TouchControlStyle? = {
        #if DEBUG
        guard current != nil else { return nil }
        return UserDefaults.standard.string(forKey: "ScreenshotLayout").flatMap(TouchControlStyle.init(rawValue:))
        #else
        return nil
        #endif
    }()

    /// `-ScreenshotLCDFilter lcd1x|lcd3x|off` changes a capture without changing saved settings.
    static let lcdFilterOverride: LCDFilter? = {
        #if DEBUG
        guard current != nil else { return nil }
        return UserDefaults.standard.string(forKey: "ScreenshotLCDFilter").flatMap(LCDFilter.init(rawValue:))
        #else
        return nil
        #endif
    }()

    /// `-GrantPlus YES` acts as if Plus were owned, without StoreKit, for screenshots and UI tests.
    /// Unlike the other arguments it needs no screenshot scene. `-ScreenshotLCDFilter` implies it,
    /// so a capture's settings agree with the filter it shows.
    static let grantsPlus: Bool = {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "GrantPlus") || lcdFilterOverride != nil
        #else
        return false
        #endif
    }()

    /// Set with `-ScreenshotInput "<script>"`: gameplay plays the script from the game's first
    /// frame, which `ScreenshotInput` describes.
    static let input: ScreenshotInput? = {
        #if DEBUG
        guard current != nil, let script = UserDefaults.standard.string(forKey: "ScreenshotInput") else { return nil }
        do {
            return try ScreenshotInput(script)
        } catch {
            log("\(inputErrorMessage): \(error)")
            return nil
        }
        #else
        return nil
        #endif
    }()

    /// Logged once a scene that takes time to settle is ready: Technical Info is showing, or
    /// gameplay's button script has played. `Scripts/take-screenshots.sh` waits for it before the
    /// scene's own wait. Gameplay also puts it in the game menu button's accessibility value, where
    /// the screenshot UI tests look for it.
    static let readyMessage = "Screenshot scene ready"
    /// Logged with the reason when the button script can't be read, which stops the screenshot run.
    static let inputErrorMessage = "Couldn't read -ScreenshotInput"

    /// With a button script, games skip the boot logo, so the script starts on the game's first
    /// frame in a library game as it does in Quick Play.
    static func settingsStore(_ store: any SettingsStore) -> any SettingsStore {
        input == nil ? store : BootSkippingSettingsStore(base: store)
    }

    private static func flag(_ key: String) -> Bool {
        #if DEBUG
        return current != nil && UserDefaults.standard.bool(forKey: key)
        #else
        return false
        #endif
    }

    /// Where the script copies the ROMs, patches and `manifest.json` from `TestROMs/`, or the folder
    /// `-ScreenshotROMs <path>` names, which the menu UI tests pass.
    static var fixtureDirectory: URL {
        #if DEBUG
        if current != nil, let path = UserDefaults.standard.string(forKey: "ScreenshotROMs") {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        #endif
        return URL.documentsDirectory.appendingPathComponent("ScreenshotROMs", isDirectory: true)
    }

    init?(argument: String) {
        let parts = argument.split(separator: ":", maxSplits: 1).map(String.init)
        guard let name = parts.first else { return nil }
        let file = parts.count == 2 ? parts[1] : nil
        switch (name, file) {
        case ("library", nil): self = .library
        case ("settings", nil): self = .settings
        case ("game", let file?): self = .game(romFile: file)
        case ("build-info", let file?): self = .buildInfo(romFile: file)
        case ("import", let file?): self = .importReview(romFile: file)
        case ("play", let file?): self = .play(romFile: file)
        case ("quick-play", let file?): self = .quickPlay(romFile: file)
        case ("quick-play-info", let file?): self = .quickPlayInfo(romFile: file)
        default: return nil
        }
    }

    /// Standard error is unbuffered, so the script's log keeps these when it ends the app.
    static func log(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    static func romURL(_ file: String) -> URL {
        fixtureDirectory.appendingPathComponent(file)
    }

    /// The Build seeded from a fixture ROM, found by the hash its manifest entry records.
    @MainActor
    static func build(romFile: String, in container: AppContainer) -> Build? {
        guard let manifest = try? ScreenshotManifest.load(),
              let rom = manifest.roms.first(where: { $0.filename == romFile }) else { return nil }
        return try? container.repositories.builds.fetchBuild(imageSHA256: rom.sha256)
    }

    /// That Build with the save it would play, so a scene can launch a Build that isn't its
    /// Game's preferred one.
    @MainActor
    static func launchContext(romFile: String, in container: AppContainer) throws -> LaunchContext? {
        guard let build = build(romFile: romFile, in: container) else { return nil }
        let profile = try ResolvePreferredSaveProfile(
            games: container.repositories.games,
            builds: container.repositories.builds,
            profiles: container.repositories.saveProfiles,
            createBlank: container.createBlankSaveProfile
        ).execute(gameID: build.gameID, buildID: build.id)
        return LaunchContext(gameID: build.gameID, buildID: build.id, saveProfileID: profile.id)
    }
}

private struct BootSkippingSettingsStore: SettingsStore {
    let base: any SettingsStore

    func valueJSON(key: String, scope: SettingsScope) throws -> String? {
        key == SettingKey.skipBootAnimation.rawValue ? "true" : try base.valueJSON(key: key, scope: scope)
    }

    func setValueJSON(_ valueJSON: String, key: String, scope: SettingsScope) throws {
        try base.setValueJSON(valueJSON, key: key, scope: scope)
    }

    func removeValue(key: String, scope: SettingsScope) throws {
        try base.removeValue(key: key, scope: scope)
    }
}

/// The parts of `TestROMs/manifest.json` the screenshot scenes use.
struct ScreenshotManifest: Decodable {
    struct ROM: Decodable {
        let filename: String
        let name: String
        let sha256: String
    }

    struct Patch: Decodable {
        let filename: String
        let format: String
        let source: String
        let target: String
        let sourceSha256: String
        let targetSha256: String
    }

    let roms: [ROM]
    let patches: [Patch]

    static func load() throws -> ScreenshotManifest {
        let data = try Data(contentsOf: ScreenshotScene.romURL("manifest.json"))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ScreenshotManifest.self, from: data)
    }
}

/// Fills an empty library from the fixture directory before the first screen appears. Each ROM
/// becomes a Game named after its manifest entry, except a patch's target, which joins its
/// source's Game as another Build. A patch whose target wasn't copied makes a patched Build.
@MainActor
enum ScreenshotSeeder {
    static func seedIfRequested(_ container: AppContainer) {
        guard ScreenshotScene.current != nil else { return }
        do {
            guard try container.repositories.games.fetchGames().isEmpty else { return }
            try seed(container, manifest: ScreenshotManifest.load())
        } catch {
            ScreenshotScene.log("Screenshot seeding failed: \(error)")
        }
    }

    private static func seed(_ container: AppContainer, manifest: ScreenshotManifest) throws {
        let fileManager = FileManager.default
        let copied = manifest.roms.filter { fileManager.fileExists(atPath: ScreenshotScene.romURL($0.filename).path) }
        let targets = Set(manifest.patches.map(\.target))
        // Sources are imported first, so a target has a Game to join.
        for rom in copied.filter({ !targets.contains($0.filename) }) + copied.filter({ targets.contains($0.filename) }) {
            do {
                try importROM(rom, manifest: manifest, container: container)
                ScreenshotScene.log("Seeded \(rom.filename)")
            } catch {
                ScreenshotScene.log("Couldn't seed \(rom.filename): \(error)")
            }
        }

        for patch in manifest.patches where fileManager.fileExists(atPath: ScreenshotScene.romURL(patch.filename).path) {
            guard let base = try container.repositories.builds.fetchBuild(imageSHA256: patch.sourceSha256),
                  try container.repositories.builds.fetchBuild(imageSHA256: patch.targetSha256) == nil else { continue }
            let targetName = manifest.roms.first { $0.filename == patch.target }?.name ?? patch.target
            do {
                _ = try container.patchCreator.execute(.init(
                    gameID: base.gameID,
                    baseBuildID: base.id,
                    patchURLs: [ScreenshotScene.romURL(patch.filename)],
                    displayName: "\(targetName) (\(patch.format) patch)"
                ))
                ScreenshotScene.log("Seeded \(patch.filename)")
            } catch {
                ScreenshotScene.log("Couldn't seed \(patch.filename): \(error)")
            }
        }
    }

    private static func importROM(
        _ rom: ScreenshotManifest.ROM,
        manifest: ScreenshotManifest,
        container: AppContainer
    ) throws {
        let analysis = try container.importAnalyzer.analyzeROM(at: ScreenshotScene.romURL(rom.filename), targetGameID: nil)
        guard analysis.exactExistingBuildID == nil else {
            try? container.fileStore.removeIfExists(analysis.stagedURL.deletingLastPathComponent())
            return
        }
        let sourceGameID: UUID? = manifest.patches
            .first { $0.target == rom.filename }
            .flatMap { try? container.repositories.builds.fetchBuild(imageSHA256: $0.sourceSha256) }?
            .gameID
        _ = try container.importCommitter.commit(ROMImportPlan(
            analysis: analysis,
            disposition: sourceGameID.map(ROMImportDisposition.addBuild(gameID:)) ?? .createGame(title: rom.name),
            buildDisplayName: sourceGameID == nil ? "Original" : rom.name,
            markAsBase: sourceGameID == nil
        ))
    }
}

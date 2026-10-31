import EmulationCore
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
    case printPreview(romFile: String)
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

    /// Set with `-ScreenshotLayout <layout>`, such as `playtiles`: requests that layout without
    /// changing Settings. The physical screen fit requirement still applies.
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

    /// Logged once a scene that takes time to settle is ready: Technical Info or the print preview
    /// is showing, or gameplay's button script has played. `Scripts/take-screenshots.sh` waits for
    /// it before the scene's own wait. Gameplay also puts it in the game menu button's
    /// accessibility value, where the screenshot UI tests look for it.
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
        case ("print", let file?): self = .printPreview(romFile: file)
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
/// source's Game as another Build. A patch whose target wasn't copied makes a patched Build. The
/// `print` scene also has it add a print to a Game's Captures.
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

    /// The print the `print` scene shows: a picture drawn by `drawnSlip()`, saved to the Game's
    /// Captures as a print from the Build when the Game has none, then read back as Captures reads
    /// it. The scene picks the Printer background, which shows only with Plus.
    static func seedPrint(romFile: String, in container: AppContainer) -> CapturedPrint? {
        guard let build = ScreenshotScene.build(romFile: romFile, in: container) else {
            ScreenshotScene.log("Couldn't seed a print: \(romFile) wasn't seeded.")
            return nil
        }
        let prints = container.printCaptures
        do {
            if try prints.captures(gameID: build.gameID).isEmpty {
                try prints.save(drawnSlip(), gameID: build.gameID, buildID: build.id, saveProfileID: nil)
                ScreenshotScene.log("Seeded a print")
            }
            UserDefaults.standard.set(PrinterPreviewBackground.printer.rawValue, forKey: PrinterPreviewBackground.storageKey)
            guard let capture = try prints.captures(gameID: build.gameID).first,
                  let seeded = CapturedPrint.read(capture, from: prints) else {
                ScreenshotScene.log("Couldn't seed a print: the saved print can't be read.")
                return nil
            }
            return seeded
        } catch {
            ScreenshotScene.log("Couldn't seed a print: \(error)")
            return nil
        }
    }

    /// A 160 by 96 picture in the printer's four shades, drawn here so the listing shows no game's
    /// art: a D-pad, two round buttons and two small ones on a striped ground, in a frame.
    private static func drawnSlip() throws -> PrinterSlip {
        let width = PrinterOutput.width, height = 96
        let (white, light, dark, black): (UInt8, UInt8, UInt8, UInt8) = (0xFF, 0xAA, 0x55, 0x00)
        var pixels = [UInt8](repeating: white, count: width * height)
        func paint(_ shade: UInt8, where inside: (Int, Int) -> Bool) {
            for y in 0..<height {
                for x in 0..<width where inside(x, y) { pixels[y * width + x] = shade }
            }
        }
        func inFrame(_ x: Int, _ y: Int, inset: Int) -> Bool {
            x >= inset && y >= inset && x < width - inset && y < height - inset
        }
        func dPad(_ x: Int, _ y: Int, inset: Int = 0) -> Bool {
            let dx = abs(x - 46), dy = abs(y - 48)
            return (dx < 8 - inset && dy < 24 - inset) || (dx < 24 - inset && dy < 8 - inset)
        }
        func disc(_ x: Int, _ y: Int, center: (x: Int, y: Int), radius: Int) -> Bool {
            (x - center.x) * (x - center.x) + (y - center.y) * (y - center.y) < radius * radius
        }
        func pill(_ x: Int, _ y: Int, centerX: Int) -> Bool {
            let dx = abs(x - centerX), dy = abs(y - 82)
            return dx < 7 && dy < 3 && dx + dy < 8
        }
        let buttons = [(x: 108, y: 58), (x: 132, y: 40)]
        let pills = [70, 90]

        paint(light) { x, y in (x + y) % 6 == 0 }
        paint(black) { x, y in !inFrame(x, y, inset: 3) }
        paint(dark) { x, y in inFrame(x, y, inset: 6) && !inFrame(x, y, inset: 7) }
        // Shadows down and to the right, then each control's outline, face and lit top-left edge.
        paint(dark) { x, y in
            dPad(x - 3, y - 3) || buttons.contains { disc(x - 3, y - 3, center: $0, radius: 12) }
                || pills.contains { pill(x - 2, y - 2, centerX: $0) }
        }
        paint(black) { x, y in
            dPad(x, y) || buttons.contains { disc(x, y, center: $0, radius: 12) } || pills.contains { pill(x, y, centerX: $0) }
        }
        paint(dark) { x, y in dPad(x, y, inset: 2) || buttons.contains { disc(x, y, center: $0, radius: 10) } }
        paint(light) { x, y in
            (dPad(x, y, inset: 2) && !dPad(x - 2, y - 2, inset: 2))
                || buttons.contains { disc(x, y, center: $0, radius: 10) && !disc(x - 3, y - 3, center: $0, radius: 10) }
        }
        paint(black) { x, y in disc(x, y, center: (46, 48), radius: 4) }
        paint(white) { x, y in buttons.contains { disc(x, y, center: ($0.x - 5, $0.y - 5), radius: 3) } }

        return PrinterSlip(output: try PrinterOutput(
            height: height, luminance: Data(pixels), topMargin: 1, bottomMargin: 3, exposure: 64
        ))
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

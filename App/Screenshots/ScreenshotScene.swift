import EmulatorApplication
import EmulatorDomain
import Foundation
import Importing
import Patching

/// A screen the app opens straight to at launch, so `Scripts/take-screenshots.sh` can capture it
/// without tapping through the file picker. Set with the launch argument
/// `-ScreenshotScene <scene>[:<ROM file>]`, which only Debug builds read.
enum ScreenshotScene: Equatable {
    case library
    case game(romFile: String)
    case buildInfo(romFile: String)
    case importReview(romFile: String)
    case play(romFile: String)
    case quickPlay(romFile: String)

    static let current: ScreenshotScene? = {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "ScreenshotScene").flatMap(ScreenshotScene.init(argument:))
        #else
        return nil
        #endif
    }()

    /// Where the script copies the ROMs, patches and `manifest.json` from `TestROMs/`.
    static var fixtureDirectory: URL {
        URL.documentsDirectory.appendingPathComponent("ScreenshotROMs", isDirectory: true)
    }

    init?(argument: String) {
        let parts = argument.split(separator: ":", maxSplits: 1).map(String.init)
        guard let name = parts.first else { return nil }
        let file = parts.count == 2 ? parts[1] : nil
        switch (name, file) {
        case ("library", nil): self = .library
        case ("game", let file?): self = .game(romFile: file)
        case ("build-info", let file?): self = .buildInfo(romFile: file)
        case ("import", let file?): self = .importReview(romFile: file)
        case ("play", let file?): self = .play(romFile: file)
        case ("quick-play", let file?): self = .quickPlay(romFile: file)
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

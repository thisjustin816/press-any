import AssetStorage
import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import GameIdentity
@testable import Importing
import XCTest

final class ExportLibraryFilesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testAROMExportsUnderItsCanonicalNameWithTheResolvedBytes() throws {
        let fixture = try Fixture(title: "Pokemon Crystal", region: "USA", revision: "1")
        let exported = try fixture.exporter.exportROM(buildID: fixture.build.id, to: fixture.exports)

        XCTAssertEqual(exported.lastPathComponent, "Pokemon Crystal (USA) (Rev 1).gbc")
        XCTAssertEqual(try Data(contentsOf: exported), fixture.romBytes)
        XCTAssertEqual(fixture.resolver.resolvedBuildIDs, [fixture.build.id], "a patched Build is rebuilt through the resolver")
    }

    func testASecondExportGetsANumberAndLeavesTheFirstAlone() throws {
        let fixture = try Fixture(title: "Pokemon Crystal", region: "USA")
        let first = try fixture.exporter.exportROM(buildID: fixture.build.id, to: fixture.exports)
        try Data([0xFF]).write(to: first)

        let second = try fixture.exporter.exportROM(buildID: fixture.build.id, to: fixture.exports)

        XCTAssertEqual(second.lastPathComponent, "Pokemon Crystal (USA) 2.gbc")
        XCTAssertEqual(try Data(contentsOf: first), Data([0xFF]))
        XCTAssertEqual(try Data(contentsOf: second), fixture.romBytes)
    }

    func testASaveExportsNamedForTheGameAndProfile() throws {
        let fixture = try Fixture(title: "Pokemon Crystal")
        let profile = try fixture.createProfile(name: "Main", battery: Data([1, 2, 3]))

        let exported = try fixture.exporter.exportSave(profileID: profile.id, to: fixture.exports)

        XCTAssertEqual(exported.lastPathComponent, "Pokemon Crystal - Main.sav")
        XCTAssertEqual(try Data(contentsOf: exported), Data([1, 2, 3]))
    }

    func testABlankProfileHasNoSaveToExport() throws {
        let fixture = try Fixture(title: "Pokemon Crystal")
        let blank = SaveProfile(id: UUID(), gameID: fixture.game.id, displayName: "New", createdAt: now, modifiedAt: now)
        try fixture.profiles.insertSaveProfile(blank)

        XCTAssertThrowsError(try fixture.exporter.exportSave(profileID: blank.id, to: fixture.exports)) {
            XCTAssertEqual($0 as? ExportLibraryFilesError, .noSave(blank.id))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.exports.path), "nothing is written")
    }

    func testAKnownDumpExportsUnderNoIntrosNameAndAHackOfItAddsTheHack() throws {
        let fixture = try Fixture(title: "Moon Garden", region: "USA")
        let dump = KnownDump(
            name: "Moon Garden (USA) (Rev 1)", system: .gameBoyColor, title: "Moon Garden",
            files: [KnownDumpFile(sha1: String(repeating: "1", count: 40), size: 4)]
        )
        let badDump = KnownDump(
            name: "Moon Garden (Europe)", system: .gameBoyColor, title: "Moon Garden",
            files: [KnownDumpFile(sha1: String(repeating: "2", count: 40), size: 4, bad: true)]
        )
        let index = try KnownDumpIndex(catalog: KnownDumpCatalog(source: "test", generated: "", systems: [], games: [dump, badDump]))
        let base = fixture.build(sha1: String(repeating: "1", count: 40), kind: .importedImage)
        let bad = fixture.build(sha1: String(repeating: "2", count: 40), kind: .importedImage)
        let hack = fixture.build(
            kind: .patchRecipe, parent: base.id,
            baseTitle: "Moon Garden", hackTitle: "Night patch", author: "Jane", version: "0.3"
        )
        let bare = fixture.build(kind: .patchRecipe, parent: base.id)
        let exporter = fixture.exporter(builds: [base, bad, hack, bare], knownDumps: index)
        let name = { (build: Build) in try exporter.exportROM(buildID: build.id, to: fixture.exports).lastPathComponent }

        XCTAssertEqual(try name(base), "Moon Garden (USA) (Rev 1).gbc")
        XCTAssertEqual(try name(bad), "Moon Garden (Europe) [b].gbc")
        XCTAssertEqual(try name(hack), "Moon Garden (USA) (Rev 1) [Night patch by Jane v0.3].gbc")
        XCTAssertEqual(try name(bare), "Moon Garden (USA) (Rev 1) [Hack].gbc", "a patched copy never passes for the dump")
    }

    func testANameCannotEscapeTheFolderOrHideTheFile() {
        XCTAssertEqual(ExportLibraryFiles.safeFilename("AC/DC: Live.gb"), "AC-DC- Live.gb")
        XCTAssertEqual(ExportLibraryFiles.safeFilename("..hidden.sav"), "hidden.sav")
        XCTAssertEqual(ExportLibraryFiles.safeFilename("..."), "Export")
    }

    private final class RecordingResolver: BuildImageResolving, @unchecked Sendable {
        let url: URL
        private(set) var resolvedBuildIDs: [UUID] = []

        init(url: URL) { self.url = url }

        func resolveImageURL(buildID: UUID) throws -> URL {
            resolvedBuildIDs.append(buildID)
            return url
        }
    }

    private struct Fixture {
        let game: Game
        let build: Build
        let games: InMemoryGameRepository
        let profiles = InMemorySaveProfileRepository()
        let assets = InMemoryAssetRepository()
        let store: ManagedFileStore
        let resolver: RecordingResolver
        let exports: URL
        let romBytes = Data([0x00, 0xC3, 0x50, 0x01])
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        init(title: String, region: String? = nil, revision: String? = nil) throws {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("export-tests-\(UUID())", isDirectory: true)
            store = try ManagedFileStore(rootURL: root.appendingPathComponent("Library", isDirectory: true))
            exports = root.appendingPathComponent("Exports", isDirectory: true)
            game = Game(id: UUID(), primaryTitle: title, systemFamily: "gameboy", createdAt: now, modifiedAt: now)
            games = InMemoryGameRepository([game])
            build = Build(
                id: UUID(),
                gameID: game.id,
                system: .gameBoyColor,
                displayName: "Original",
                imageAssetID: UUID(),
                imageSHA256: String(repeating: "a", count: 64),
                sourceKind: .patchRecipe,
                region: region,
                revision: revision,
                createdAt: now,
                modifiedAt: now
            )
            let image = root.appendingPathComponent("resolved.gbc")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try romBytes.write(to: image)
            resolver = RecordingResolver(url: image)
        }

        var exporter: ExportLibraryFiles { exporter(builds: [build], knownDumps: nil) }

        func exporter(builds: [Build], knownDumps: KnownDumpIndex?) -> ExportLibraryFiles {
            ExportLibraryFiles(
                games: games,
                builds: InMemoryBuildRepository(builds),
                profiles: profiles,
                assets: assets,
                assetStore: store,
                images: resolver,
                knownDumps: knownDumps
            )
        }

        func build(
            sha1: String? = nil, kind: BuildSourceKind, parent: UUID? = nil,
            baseTitle: String? = nil, hackTitle: String? = nil, author: String? = nil, version: String? = nil
        ) -> Build {
            Build(
                id: UUID(), gameID: game.id, system: .gameBoyColor, displayName: "Build", imageAssetID: UUID(),
                imageSHA256: String(repeating: "a", count: 64), imageSHA1: sha1, sourceKind: kind,
                parentBuildID: parent, versionString: version, baseTitle: baseTitle, hackTitle: hackTitle,
                author: author, createdAt: now, modifiedAt: now
            )
        }

        func createProfile(name: String, battery: Data) throws -> SaveProfile {
            let source = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).sav")
            try battery.write(to: source)
            return try ImportBatterySave(games: games, profiles: profiles, assets: assets, assetStore: store, now: { now })
                .execute(gameID: game.id, sourceURL: source, name: name)
        }
    }
}

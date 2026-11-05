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
        // Import Review titles a hack left blank with its Game's title, and records no base.
        let untitled = fixture.build(kind: .patchRecipe, parent: base.id, hackTitle: "Moon Garden", author: "Jane")
        let exporter = fixture.exporter(builds: [base, bad, hack, bare, untitled], knownDumps: index)
        let name = { (build: Build) in try exporter.exportROM(buildID: build.id, to: fixture.exports).lastPathComponent }

        XCTAssertEqual(try name(base), "Moon Garden (USA) (Rev 1) [!].gbc")
        XCTAssertEqual(try name(bad), "Moon Garden (Europe) [b].gbc")
        XCTAssertEqual(try name(hack), "Moon Garden (USA) (Rev 1) [Night patch by Jane v0.3].gbc")
        XCTAssertEqual(try name(bare), "Moon Garden (USA) (Rev 1) [Hack].gbc", "a patched copy never passes for the dump")
        XCTAssertEqual(try name(untitled), "Moon Garden (USA) (Rev 1) [Hack by Jane].gbc")
    }

    func testANameCannotEscapeTheFolderOrHideTheFile() {
        XCTAssertEqual(ExportLibraryFiles.safeFilename("AC/DC: Live.gb"), "AC-DC- Live.gb")
        XCTAssertEqual(ExportLibraryFiles.safeFilename("..hidden.sav"), "hidden.sav")
        XCTAssertEqual(ExportLibraryFiles.safeFilename("..."), "Export")
    }

    func testASaveExportsAtAShrunkSizeUnderANameThatSaysSo() throws {
        let fixture = try Fixture(title: "Pokemon Crystal", rom: Self.rom(ram: 0x04))
        let battery = Self.battery(128 * 1024, writing: [0: 0x42, 1557: 0x01])
        let profile = try fixture.createProfile(name: "Main", battery: battery, writtenBy: fixture.build.id)
        let profileBefore = try fixture.profiles.fetchSaveProfile(id: profile.id)
        let assetBefore = try fixture.assets.fetchAsset(id: XCTUnwrap(profile.persistentSaveAssetID))

        let options = try fixture.exporter.saveExportOptions(profileID: profile.id)
        let smallest = try fixture.exporter.exportSave(profileID: profile.id, to: fixture.exports, size: .minimized)
        let middle = try fixture.exporter.exportSave(
            profileID: profile.id, to: fixture.exports, size: .custom(bytes: 32 * 1024)
        )
        let original = try fixture.exporter.exportSave(profileID: profile.id, to: fixture.exports, size: .original)

        XCTAssertEqual(options.minimizedBytes, 8 * 1024)
        XCTAssertEqual(options.customSizes, [32 * 1024, 64 * 1024])
        XCTAssertEqual(smallest.lastPathComponent, "Pokemon Crystal - Main (8 KB).sav")
        XCTAssertEqual(try Data(contentsOf: smallest), battery.prefix(8 * 1024))
        XCTAssertEqual(middle.lastPathComponent, "Pokemon Crystal - Main (32 KB).sav")
        XCTAssertEqual(try Data(contentsOf: middle), battery.prefix(32 * 1024))
        XCTAssertEqual(original.lastPathComponent, "Pokemon Crystal - Main.sav", "the original size keeps the plain name")
        XCTAssertEqual(try Data(contentsOf: original), battery)
        XCTAssertEqual(try fixture.profiles.fetchSaveProfile(id: profile.id), profileBefore, "an export leaves the profile alone")
        XCTAssertEqual(try fixture.assets.fetchAsset(id: XCTUnwrap(profile.persistentSaveAssetID)), assetBefore)
    }

    func testASaveExportsAtALargerSizePaddedWithErasedBytes() throws {
        let fixture = try Fixture(title: "Pokemon Crystal", rom: Self.rom(ram: 0x02))
        let battery = Self.battery(8 * 1024, writing: [0: 0x42, 0x1FFF: 0x01])
        let profile = try fixture.createProfile(name: "Main", battery: battery, writtenBy: fixture.build.id)
        let profileBefore = try fixture.profiles.fetchSaveProfile(id: profile.id)

        let options = try fixture.exporter.saveExportOptions(profileID: profile.id)
        let larger = try fixture.exporter.exportSave(
            profileID: profile.id, to: fixture.exports, size: .custom(bytes: 32 * 1024)
        )

        XCTAssertNil(options.minimizedBytes)
        XCTAssertEqual(options.largerSizes, [32 * 1024, 64 * 1024, 128 * 1024])
        XCTAssertEqual(larger.lastPathComponent, "Pokemon Crystal - Main (32 KB).sav")
        let written = try Data(contentsOf: larger)
        XCTAssertEqual(written.prefix(8 * 1024), battery)
        XCTAssertEqual(Set(written.dropFirst(8 * 1024)), [0xFF])
        XCTAssertEqual(written.count, 32 * 1024)
        XCTAssertEqual(try fixture.profiles.fetchSaveProfile(id: profile.id), profileBefore, "an export leaves the profile alone")
    }

    func testASizeThatIsNotOfferedWritesNothing() throws {
        let fixture = try Fixture(title: "Pokemon Crystal", rom: Self.rom(ram: 0x04))
        let profile = try fixture.createProfile(
            name: "Main", battery: Self.battery(128 * 1024, writing: [0x2000: 0x01]), writtenBy: fixture.build.id
        )

        for size: SaveExportSize in [.custom(bytes: 8 * 1024), .custom(bytes: 100)] {
            XCTAssertThrowsError(try fixture.exporter.exportSave(profileID: profile.id, to: fixture.exports, size: size)) {
                XCTAssertEqual($0 as? ExportLibraryFilesError, .sizeNotOffered)
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.exports.path), "nothing is written")
    }

    func testASaveWithNoKnownHeaderOnlyExportsAtItsOriginalSize() throws {
        let fixture = try Fixture(title: "Pokemon Crystal")
        let profile = try fixture.createProfile(name: "Main", battery: Data([1, 2, 3]))

        XCTAssertEqual(try fixture.exporter.saveExportOptions(profileID: profile.id).minimizedBytes, nil)
        XCTAssertThrowsError(try fixture.exporter.exportSave(profileID: profile.id, to: fixture.exports, size: .minimized)) {
            XCTAssertEqual($0 as? ExportLibraryFilesError, .sizeNotOffered)
        }
    }

    func testTheHeaderComesFromTheBuildThatWroteTheSaveBeforeThePreferredBuild() {
        let writer = UUID(), preferred = UUID()
        let game = Game(
            id: UUID(), primaryTitle: "Pokemon Crystal", systemFamily: "gameboy", preferredBuildID: preferred,
            createdAt: now, modifiedAt: now
        )
        var profile = SaveProfile(id: UUID(), gameID: game.id, displayName: "Main", createdAt: now, modifiedAt: now)

        XCTAssertEqual(ExportLibraryFiles.headerBuildID(for: profile, in: game), preferred)
        profile.saveWrittenByBuildID = writer
        XCTAssertEqual(ExportLibraryFiles.headerBuildID(for: profile, in: game), writer)
    }

    private static func rom(ram: UInt8, type: UInt8 = 0x1B) -> Data {
        var rom = Data(count: 0x150)
        rom[0x147] = type
        rom[0x148] = 0x06
        rom[0x149] = ram
        return rom
    }

    private static func battery(_ size: Int, writing bytes: [Int: UInt8]) -> Data {
        var data = Data(repeating: 0xFF, count: size)
        for (offset, byte) in bytes { data[offset] = byte }
        return data
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
        let romBytes: Data
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        init(
            title: String, region: String? = nil, revision: String? = nil,
            rom: Data = Data([0x00, 0xC3, 0x50, 0x01])
        ) throws {
            romBytes = rom
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

        /// `writtenBy` records the Build that last wrote the save, as a played profile has.
        func createProfile(name: String, battery: Data, writtenBy buildID: UUID? = nil) throws -> SaveProfile {
            let source = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).sav")
            try battery.write(to: source)
            var profile = try ImportBatterySave(
                games: games, profiles: profiles, assets: assets, assetStore: store, now: { now }
            ).execute(gameID: game.id, sourceURL: source, name: name)
            if let buildID {
                profile.saveWrittenByBuildID = buildID
                try profiles.updateSaveProfile(profile)
            }
            return profile
        }
    }
}

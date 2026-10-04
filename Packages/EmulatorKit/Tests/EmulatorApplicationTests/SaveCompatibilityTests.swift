import AssetStorage
@testable import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import XCTest

final class SaveCompatibilityTests: XCTestCase {
    // MARK: Variable maps

    func testRecognizesGBStudioGlobalsAndSymbolFilesOnly() {
        func format(_ text: String) -> BuildVariableMap.Format? { AttachVariableMap.format(of: Data(text.utf8)) }
        XCTAssertEqual(format("; generated\nVAR_HAS_KEY = 0\nVAR_LIVES = 1\nMAX_GLOBAL_VARS = 2\n"), .gbStudioGlobals)
        XCTAssertEqual(format("00:C0A0 wPlayerX\n00:C0A1 wPlayerY\n"), .symbolFile)
        XCTAssertEqual(format("DEF _player_x 0xC0A0\nDEF _player_y 0xC0A1\n"), .symbolFile)
        XCTAssertNil(format("Just some notes about the game.\nNothing to see.\n"))
        XCTAssertNil(format(""))
    }

    func testAttachingAMapKeepsItOnThatBuildOnce() throws {
        let fixture = try Fixture()
        let build = try fixture.addBuild(title: "MAPS")
        let url = try fixture.writeExternal("game_globals.i", "VAR_HAS_KEY = 0\nVAR_LIVES = 1\n")

        let map = try fixture.attach.execute(buildID: build.id, sourceURL: url)
        XCTAssertEqual(map.format, .gbStudioGlobals)
        XCTAssertEqual(map.originalFilename, "game_globals.i")
        XCTAssertEqual(try fixture.attach.execute(buildID: build.id, sourceURL: url), map, "attaching it again changes nothing")
        XCTAssertEqual(try fixture.maps.fetchVariableMaps(buildID: build.id), [map])
        let asset = try XCTUnwrap(fixture.assets.fetchAsset(id: map.assetID))
        XCTAssertEqual(asset.kind, .variableMap)
        XCTAssertEqual(asset.storageClass, .source)

        let notes = try fixture.writeExternal("notes.txt", "remember to beat the boss\n")
        XCTAssertThrowsError(try fixture.attach.execute(buildID: build.id, sourceURL: notes)) {
            XCTAssertEqual($0 as? AttachVariableMapError, .unrecognizedFormat)
        }
    }

    // MARK: Assessing a launch's save

    func testASaveIsSafeForTheBuildThatWroteItOrWithNoKnownWriter() throws {
        let fixture = try Fixture()
        let a = try fixture.addBuild(title: "SAFE A", tools: ["GBDK"])
        let b = try fixture.addBuild(title: "SAFE B", tools: ["ZGB"])
        let unknown = try fixture.addProfile(writtenBy: nil)
        let byA = try fixture.addProfile(writtenBy: a.id)

        XCTAssertFalse(try fixture.assess(b, unknown).isRisky, "no recorded writer, nothing to compare")
        XCTAssertFalse(try fixture.assess(a, byA).isRisky)
    }

    func testDifferentBuildsWithTheSameToolsAndHardwareAreSafe() throws {
        let fixture = try Fixture()
        let a = try fixture.addBuild(title: "SAME A", tools: [])
        let b = try fixture.addBuild(title: "SAME B", tools: [])
        let assessment = try fixture.assess(b, fixture.addProfile(writtenBy: a.id))
        XCTAssertEqual(assessment.risks, [])
        XCTAssertEqual(assessment.writtenBy?.id, a.id)
    }

    func testGBStudioDifferentToolsAndDifferentSaveHardwareAreRisky() throws {
        let fixture = try Fixture()
        let plain = try fixture.addBuild(title: "PLAIN", tools: [])
        let studio = try fixture.addBuild(title: "STUDIO", tools: ["GBStudio"])
        let gbdk = try fixture.addBuild(title: "GBDK", tools: ["GBDK"])
        let bigSave = try fixture.addBuild(title: "BIG SAVE", tools: [], ramSize: 0x03)

        XCTAssertEqual(try fixture.assess(studio, fixture.addProfile(writtenBy: plain.id)).risks, [.gbStudio])
        XCTAssertEqual(
            try fixture.assess(gbdk, fixture.addProfile(writtenBy: plain.id)).risks,
            [.differentTools(writtenWith: [], playingWith: ["GBDK 4.3.0"])]
        )
        XCTAssertEqual(try fixture.assess(bigSave, fixture.addProfile(writtenBy: plain.id)).risks, [.differentSaveHardware])
    }

    func testDetectionNotYetRunOnABuildDoesNotCountAsADifference() throws {
        let fixture = try Fixture()
        let undetected = try fixture.addBuild(title: "OLD", tools: nil)
        let gbdk = try fixture.addBuild(title: "NEW", tools: ["GBDK"])
        XCTAssertFalse(try fixture.assess(gbdk, fixture.addProfile(writtenBy: undetected.id)).isRisky)
    }

    // MARK: The safe choices

    func testPlayingWithACopyLeavesTheOriginalSaveAndBecomesTheBuildsDefault() throws {
        let fixture = try Fixture()
        let a = try fixture.addBuild(title: "COPY A")
        let b = try fixture.addBuild(title: "COPY B")
        let original = try fixture.addProfile(writtenBy: a.id, battery: Data([1, 2, 3]))

        let context = try fixture.choose.playWithCopy(LaunchContext(gameID: fixture.gameID, buildID: b.id, saveProfileID: original.id))

        XCTAssertNotEqual(context.saveProfileID, original.id)
        let copy = try XCTUnwrap(fixture.profiles.fetchSaveProfile(id: context.saveProfileID))
        XCTAssertEqual(copy.copiedFromProfileID, original.id)
        XCTAssertEqual(copy.displayName, "Main for COPY B")
        XCTAssertEqual(try fixture.battery(of: copy), Data([1, 2, 3]))
        XCTAssertEqual(try fixture.battery(of: original), Data([1, 2, 3]))
        XCTAssertEqual(try fixture.builds.fetchBuild(id: b.id)?.preferredSaveProfileID, copy.id)
        XCTAssertEqual(try fixture.builds.fetchBuild(id: a.id)?.preferredSaveProfileID, nil)
    }

    func testPlayingWithANewSaveStartsBlank() throws {
        let fixture = try Fixture()
        let a = try fixture.addBuild(title: "NEW A")
        let b = try fixture.addBuild(title: "NEW B")
        let original = try fixture.addProfile(writtenBy: a.id, battery: Data([9]))

        let context = try fixture.choose.playWithNewSave(LaunchContext(gameID: fixture.gameID, buildID: b.id, saveProfileID: original.id))

        let blank = try XCTUnwrap(fixture.profiles.fetchSaveProfile(id: context.saveProfileID))
        XCTAssertNil(blank.persistentSaveAssetID)
        XCTAssertEqual(blank.displayName, "NEW B")
        XCTAssertEqual(try fixture.builds.fetchBuild(id: b.id)?.preferredSaveProfileID, blank.id)
    }
}

private final class Fixture: @unchecked Sendable {
    let root: URL
    let store: ManagedFileStore
    let games = InMemoryGameRepository()
    let builds = InMemoryBuildRepository()
    let profiles = InMemorySaveProfileRepository()
    let assets = InMemoryAssetRepository()
    let reports = InMemoryToolchainReportRepository()
    let maps = InMemoryBuildVariableMapRepository()
    let images = MappedImages()
    let gameID = UUID()
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("SaveCompat-\(UUID().uuidString)")
        store = try ManagedFileStore(rootURL: root.appendingPathComponent("Managed"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("External"), withIntermediateDirectories: true)
        try games.insertGame(Game(id: gameID, primaryTitle: "Compat", systemFamily: "gameboy", createdAt: now, modifiedAt: now))
    }

    var attach: AttachVariableMap {
        AttachVariableMap(builds: builds, maps: maps, assets: assets, assetStore: store, transactions: PassthroughTransactionRunner())
    }

    var choose: ChooseSaveForBuild {
        ChooseSaveForBuild(games: games, builds: builds, profiles: profiles, assets: assets, assetStore: store)
    }

    func assess(_ build: Build, _ profile: SaveProfile) throws -> SaveCompatibilityAssessment {
        try AssessSaveCompatibility(builds: builds, profiles: profiles, reports: reports, images: images, assetStore: store)
            .execute(context: LaunchContext(gameID: gameID, buildID: build.id, saveProfileID: profile.id))
    }

    /// A Build whose image declares `ramSize` at 0x149. `tools` are detected toolchain names, or nil
    /// for a Build detection hasn't run on.
    func addBuild(title: String, tools: [String]? = [], ramSize: UInt8 = 0x02) throws -> Build {
        var image = TestROM.make(title: title)
        image[0x147] = 0x03
        image[0x149] = ramSize
        let url = root.appendingPathComponent("\(UUID().uuidString).gb")
        try image.write(to: url)
        let build = Build(
            id: UUID(),
            gameID: gameID,
            system: .gameBoy,
            displayName: title,
            imageAssetID: UUID(),
            imageSHA256: UUID().uuidString,
            sourceKind: .importedImage,
            createdAt: now,
            modifiedAt: now
        )
        try builds.insertBuild(build)
        images.urls[build.id] = url
        if let tools {
            try reports.saveReport(
                ToolchainDetectionReport(
                    detector: "gbtoolsid",
                    detectorVersion: "1",
                    corpusRevision: "v1.5.5-14-g5ff49ad",
                    components: tools.map { DetectedToolchainComponent(kind: .toolchain, name: $0, version: "4.3.0", evidence: []) }
                ),
                buildID: build.id,
                detectedAt: now
            )
        }
        return build
    }

    func addProfile(writtenBy buildID: UUID?, battery: Data = Data([0])) throws -> SaveProfile {
        let profileID = UUID()
        let url = store.persistentSaveURL(profileID: profileID)
        try store.writeDataAtomically(battery, to: url)
        let asset = ManagedAsset(
            id: UUID(),
            kind: .persistentSave,
            storageClass: .userData,
            contentSHA256: store.hashData(battery),
            byteLength: Int64(battery.count),
            relativePath: try store.managedRelativePath(for: url),
            integrityStatus: .verified,
            createdAt: now
        )
        try assets.insertAsset(asset)
        let profile = SaveProfile(
            id: profileID,
            gameID: gameID,
            displayName: "Main",
            persistentSaveAssetID: asset.id,
            saveWrittenByBuildID: buildID,
            createdAt: now,
            modifiedAt: now
        )
        try profiles.insertSaveProfile(profile)
        return profile
    }

    func battery(of profile: SaveProfile) throws -> Data {
        let asset = try XCTUnwrap(assets.fetchAsset(id: XCTUnwrap(profile.persistentSaveAssetID)))
        return try store.readData(at: store.managedURL(relativePath: asset.relativePath))
    }

    func writeExternal(_ name: String, _ text: String) throws -> URL {
        let url = root.appendingPathComponent("External/\(name)")
        try Data(text.utf8).write(to: url)
        return url
    }
}

private final class MappedImages: BuildImageResolving, @unchecked Sendable {
    var urls: [UUID: URL] = [:]
    func resolveImageURL(buildID: UUID) throws -> URL {
        guard let url = urls[buildID] else { throw CocoaError(.fileNoSuchFile) }
        return url
    }
}

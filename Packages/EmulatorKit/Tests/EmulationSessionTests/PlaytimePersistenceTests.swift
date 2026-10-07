import AssetStorage
import EmulationCore
import EmulationSession
import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import PersistenceGRDB
import XCTest

final class PlaytimePersistenceTests: XCTestCase {
    func testFailedProfileUpdateRollsBackBuildTimeAndRetryRecordsBothOnce() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ManagedFileStore(rootURL: root)
        let databaseURL = root.appendingPathComponent("Library.sqlite")
        let database = try AppDatabase(url: databaseURL)
        try database.migrate()
        let repositories = database.makeRepositories()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let game = Game(id: UUID(), primaryTitle: "Playtime", systemFamily: "gameboy", createdAt: date, modifiedAt: date)
        let romURL = root.appendingPathComponent("Test.gb")
        try Data(repeating: 0, count: 0x8000).write(to: romURL)
        let rom = ManagedAsset(
            id: UUID(), kind: .sourceImage, storageClass: .source, contentSHA256: try store.hashFile(at: romURL),
            byteLength: 0x8000, relativePath: "Test.gb", integrityStatus: .verified, createdAt: date
        )
        let build = Build(
            id: UUID(), gameID: game.id, system: .gameBoy, displayName: "Test", imageAssetID: rom.id,
            imageSHA256: rom.contentSHA256, sourceKind: .importedImage, createdAt: date, modifiedAt: date
        )
        let profile = SaveProfile(id: UUID(), gameID: game.id, displayName: "Main", createdAt: date, modifiedAt: date)
        try repositories.games.insertGame(game)
        try repositories.assets.insertAsset(rom)
        try repositories.builds.insertBuild(build)
        try repositories.saveProfiles.insertSaveProfile(profile)
        let context = LaunchContext(gameID: game.id, buildID: build.id, saveProfileID: profile.id)
        let session = EmulationSession(
            builds: repositories.builds, profiles: repositories.saveProfiles, states: repositories.saveStates,
            assets: repositories.assets, assetStore: store, imageResolver: PlaytimeImageResolver(url: romURL),
            coreRegistry: CoreRegistry(factories: [FakeCoreFactory(descriptor: CoreDescriptor(identifier: "sameboy", version: "1.0.3"))]), transactions: repositories.transactions
        )
        try session.start(context: context)
        _ = try session.stepFrame()
        try database.writer.write { db in
            try db.execute(sql: """
                CREATE TRIGGER refuse_playtime BEFORE UPDATE OF total_playtime_seconds ON save_profiles
                BEGIN SELECT RAISE(ABORT, 'test profile update failure'); END;
                """)
        }

        XCTAssertThrowsError(try session.background())
        XCTAssertEqual(try repositories.builds.fetchBuild(id: build.id)?.totalPlaytimeSeconds, 0)
        XCTAssertEqual(try repositories.saveProfiles.fetchSaveProfile(id: profile.id)?.totalPlaytimeSeconds, 0)
        XCTAssertEqual(try repositories.saveProfiles.fetchSaveProfile(id: profile.id)?.sessionCount, 0)
        try database.writer.write { db in try db.execute(sql: "DROP TRIGGER refuse_playtime") }
        try session.background()
        try session.stop()

        let reopened = try AppDatabase(url: databaseURL).makeRepositories()
        let recordedBuild = try XCTUnwrap(reopened.builds.fetchBuild(id: build.id))
        let recordedProfile = try XCTUnwrap(reopened.saveProfiles.fetchSaveProfile(id: profile.id))
        XCTAssertEqual(recordedBuild.totalPlaytimeSeconds, 0.016742706, accuracy: 1e-9)
        XCTAssertEqual(recordedBuild.totalPlaytimeSeconds, recordedProfile.totalPlaytimeSeconds)
        XCTAssertEqual(recordedProfile.sessionCount, 1)
        XCTAssertEqual(recordedProfile.modifiedAt, profile.modifiedAt)
    }
}

private struct PlaytimeImageResolver: BuildImageResolving {
    let url: URL
    func resolveImageURL(buildID: UUID) throws -> URL { url }
}

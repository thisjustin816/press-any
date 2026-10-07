import EmulatorApplication
import EmulatorDomain
import Foundation
import XCTest
@testable import PressAny

@MainActor
final class SaveCompatibilityFlowTests: XCTestCase {
    func testBuildDetailsListsAddsReplacesCancelsAndRemovesDeclarations() throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let builds = fixture.container.repositories.builds
        let model = fixture.details(fixture.writer)
        model.reload()
        XCTAssertTrue(model.saveDeclarations.isEmpty)
        XCTAssertEqual(model.compatibilityCandidates.map(\.id), [fixture.playing.id])
        model.addCompatibility()
        XCTAssertTrue(model.isAddingCompatibility)
        XCTAssertEqual(model.compatibilityBuildID, fixture.playing.id)
        model.compatibilityDraft = .doesNotShareSaves
        model.isAddingCompatibility = false
        XCTAssertTrue(try builds.fetchSaveDeclarations(buildID: fixture.writer.id).isEmpty)

        model.addCompatibility()
        model.saveCompatibility()
        XCTAssertFalse(model.isAddingCompatibility)
        XCTAssertEqual(model.saveDeclarations.map(\.otherBuild.displayName), ["USA Build"])
        XCTAssertEqual(model.saveDeclarations.map(\.label), ["Shares Saves"])
        let other = fixture.details(fixture.playing)
        other.reload()
        XCTAssertEqual(other.saveDeclarations.map(\.otherBuild.displayName), ["Japan Build"])
        other.addCompatibility()
        other.compatibilityDraft = .doesNotShareSaves
        other.saveCompatibility()
        model.reload()
        XCTAssertEqual(model.saveDeclarations.count, 1)
        XCTAssertEqual(model.saveDeclarations.first?.label, "Doesn’t Share Saves")

        var renamed = fixture.playing
        renamed.displayName = "Renamed Release"
        try builds.updateBuildMetadata(renamed)
        model.reload()
        XCTAssertEqual(model.saveDeclarations.first?.otherBuild.displayName, "Renamed Release")
        let reopened = try AppContainer(rootURL: fixture.root)
        XCTAssertEqual(try reopened.repositories.builds.fetchSaveDeclarations(buildID: fixture.writer.id).first?.compatibility, .doesNotShareSaves)
        model.removeCompatibility(otherBuildID: fixture.playing.id)
        XCTAssertTrue(model.saveDeclarations.isEmpty)
        other.reload()
        XCTAssertTrue(other.saveDeclarations.isEmpty)
        XCTAssertNil(model.errorMessage)
    }

    func testAlwaysUseSavesPromptChoiceKeepsLaunchAndRecordsShare() throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let container = fixture.container
        try container.repositories.builds.setSaveCompatibility(
            between: fixture.writer.id, and: fixture.playing.id, compatibility: .doesNotShareSaves
        )
        let assessment = try container.saveCompatibility.execute(context: fixture.context)
        let prompt = RiskyLaunch(context: fixture.context, assessment: assessment, profileName: "Main")
        XCTAssertTrue(prompt.canDeclareCompatibility)
        XCTAssertTrue(prompt.message.contains("These Builds are declared not to share saves."))
        let launched = try container.chooseSaveForBuild.playSharingSaves(
            prompt.context, writtenByBuildID: XCTUnwrap(prompt.assessment.writtenBy).id
        )
        XCTAssertEqual(launched, fixture.context)
        XCTAssertFalse(try container.saveCompatibility.execute(context: launched).isRisky)
        XCTAssertEqual(try container.repositories.saveProfiles.fetchSaveProfile(id: fixture.profile.id), fixture.profile)
        let reopened = try AppContainer(rootURL: fixture.root)
        XCTAssertFalse(try reopened.saveCompatibility.execute(context: launched).isRisky)
    }

    func testCrossRegionPromptNamesBothReleasesAndLanguages() throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let assessment = try fixture.container.saveCompatibility.execute(context: fixture.context)
        let prompt = RiskyLaunch(context: fixture.context, assessment: assessment, profileName: "Main")
        XCTAssertTrue(assessment.isRisky)
        XCTAssertTrue(prompt.message.contains("This save was last written by the Japan release."))
        XCTAssertTrue(prompt.message.contains("This Build is the USA release."))
        XCTAssertTrue(prompt.message.contains("The save's language is Ja; this Build's is En."))

        var profile = fixture.profile
        profile.saveWrittenByBuildID = nil
        try fixture.container.repositories.saveProfiles.updateSaveProfile(profile)
        let unknown = try fixture.container.saveCompatibility.execute(context: fixture.context)
        XCTAssertFalse(unknown.isRisky)
        XCTAssertFalse(RiskyLaunch(context: fixture.context, assessment: unknown, profileName: "Main").message.contains("release"))
        profile.saveWrittenByBuildID = fixture.writer.id
        try fixture.container.repositories.saveProfiles.updateSaveProfile(profile)
        var playing = fixture.playing
        playing.region = nil
        try fixture.container.repositories.builds.updateBuildMetadata(playing)
        let noRegion = try fixture.container.saveCompatibility.execute(context: fixture.context)
        XCTAssertFalse(noRegion.isRisky)
        XCTAssertFalse(RiskyLaunch(context: fixture.context, assessment: noRegion, profileName: "Main").message.contains("release"))
    }
}

@MainActor
private final class Fixture {
    let root: URL
    let container: AppContainer
    let writer: Build
    let playing: Build
    let profile: SaveProfile

    var context: LaunchContext {
        LaunchContext(gameID: playing.gameID, buildID: playing.id, saveProfileID: profile.id)
    }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        container = try AppContainer(rootURL: root)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let game = Game(id: UUID(), primaryTitle: "Example", systemFamily: "gameboy", createdAt: now, modifiedAt: now)
        try container.repositories.games.insertGame(game)
        let rom = ManagedAsset(id: UUID(), kind: .sourceImage, storageClass: .source,
            contentSHA256: String(repeating: "a", count: 64), byteLength: 1, relativePath: "Source/ROM/fixture.rom",
            integrityStatus: .verified, createdAt: now)
        try container.repositories.assets.insertAsset(rom)
        writer = Build(id: UUID(), gameID: game.id, system: .gameBoy, displayName: "Japan Build", imageAssetID: rom.id,
            imageSHA256: rom.contentSHA256, sourceKind: .importedImage, region: "Japan", language: "Ja", createdAt: now, modifiedAt: now)
        playing = Build(id: UUID(), gameID: game.id, system: .gameBoy, displayName: "USA Build", imageAssetID: rom.id,
            imageSHA256: String(repeating: "b", count: 64), sourceKind: .importedImage, region: "USA", language: "En", createdAt: now, modifiedAt: now)
        try container.repositories.builds.insertBuild(writer)
        try container.repositories.builds.insertBuild(playing)
        let other = Game(id: UUID(), primaryTitle: "Other", systemFamily: "gameboy", createdAt: now, modifiedAt: now)
        try container.repositories.games.insertGame(other)
        try container.repositories.builds.insertBuild(Build(id: UUID(), gameID: other.id, system: .gameBoy,
            displayName: "Other Game Build", imageAssetID: rom.id, imageSHA256: rom.contentSHA256,
            sourceKind: .importedImage, createdAt: now, modifiedAt: now))
        let profileID = UUID()
        let batteryURL = container.fileStore.persistentSaveURL(profileID: profileID)
        let bytes = Data([1, 2, 3])
        try container.fileStore.writeDataAtomically(bytes, to: batteryURL)
        let battery = ManagedAsset(id: UUID(), kind: .persistentSave, storageClass: .userData,
            contentSHA256: container.fileStore.hashData(bytes), byteLength: Int64(bytes.count),
            relativePath: try container.fileStore.managedRelativePath(for: batteryURL), integrityStatus: .verified, createdAt: now)
        try container.repositories.assets.insertAsset(battery)
        profile = SaveProfile(id: profileID, gameID: game.id, displayName: "Main", persistentSaveAssetID: battery.id,
            saveWrittenByBuildID: writer.id, createdAt: now, modifiedAt: now)
        try container.repositories.saveProfiles.insertSaveProfile(profile)
    }

    func details(_ build: Build) -> BuildDetailViewModel {
        BuildDetailViewModel(buildID: build.id, builds: container.repositories.builds, operations: container.buildOperations)
    }

    func removeFiles() { try? FileManager.default.removeItem(at: root) }
}

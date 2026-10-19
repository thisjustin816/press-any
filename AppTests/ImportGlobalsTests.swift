import EmulatorApplication
import EmulatorDomain
import Foundation
import Importing
import Testing
@testable import PressAny

@MainActor
struct ImportGlobalsTests {
    @Test func importingAZipAttachesTheMapToTheExactBuildAndSurvivesCleanup() throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let review = try fixture.review()
        #expect(try fixture.container.repositories.games.fetchGames().isEmpty)

        let result = try review.commit()
        fixture.container.sharedFileInbox.discard(fixture.file)

        let reopened = try AppContainer(rootURL: fixture.library)
        let map = try #require(reopened.repositories.variableMaps.fetchVariableMaps(buildID: result.build.id).first)
        #expect(map.format == .gbStudioGlobals)
        #expect(map.originalFilename == "globals.i")
        let asset = try #require(reopened.repositories.assets.fetchAsset(id: map.assetID))
        #expect(try reopened.fileStore.readData(at: reopened.fileStore.rootURL.appendingPathComponent(asset.relativePath)) == fixture.mapData)
        #expect(review.importWarning == nil)
    }

    @Test func duplicateROMStillAttachesANewMapWithoutDuplicatingTheBuildOrMap() throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let first = try fixture.review()
        first.includeVariableMap = false
        let original = try first.commit()
        #expect(try fixture.container.repositories.variableMaps.fetchVariableMaps(buildID: original.build.id).isEmpty)

        let duplicate = try fixture.review()
        #expect(duplicate.isExactDuplicate)
        let result = try duplicate.commit()
        #expect(result.build.id == original.build.id)
        #expect(!result.createdNewBuild)
        let maps = try fixture.container.repositories.variableMaps.fetchVariableMaps(buildID: original.build.id)
        #expect(maps.count == 1)
        _ = try fixture.review().commit()
        #expect(try fixture.container.repositories.variableMaps.fetchVariableMaps(buildID: original.build.id) == maps)
    }

    @Test func invalidGlobalsReportPartialSuccessWithoutLosingTheROM() throws {
        let fixture = try Fixture(mapData: Data("not a globals file\n".utf8))
        defer { fixture.removeFiles() }
        let review = try fixture.review()

        let result = try review.commit()

        #expect(try fixture.container.repositories.builds.fetchBuild(id: result.build.id) != nil)
        #expect(try fixture.container.repositories.variableMaps.fetchVariableMaps(buildID: result.build.id).isEmpty)
        #expect(review.variableMapFailure?.contains("globals.i") == true)
        #expect(review.importWarning?.contains("The ROM is in your library.") == true)
        fixture.container.sharedFileInbox.discard(fixture.file)
        #expect(!FileManager.default.fileExists(atPath: try #require(fixture.file.variableMapURL).path))
    }

    @Test func cancelAndFailedROMCommitDoNotAttachTheMap() throws {
        let fixture = try Fixture()
        defer { fixture.removeFiles() }
        let review = try fixture.review()
        review.cancel()
        #expect(throws: (any Error).self) { try review.commit() }
        #expect(try fixture.container.repositories.games.fetchGames().isEmpty)
        #expect(review.variableMapFailure == nil)
        fixture.container.sharedFileInbox.discard(fixture.file)
        #expect(!FileManager.default.fileExists(atPath: try #require(fixture.file.variableMapURL).path))
    }

    @Test func actualGBStudioROMsAcceptTheExportedGlobals() throws {
        let bundle = Bundle(for: GlobalsFixtureBundle.self)
        for (name, suffix) in [("gbstudio-dmg", "gb"), ("gbstudio-gbc", "gbc")] {
            let rom = try Data(contentsOf: #require(bundle.url(forResource: name, withExtension: suffix)))
            let map = try Data(contentsOf: #require(bundle.url(forResource: name, withExtension: "i")))
            let fixture = try Fixture(romData: rom, romFilename: "\(name).\(suffix)", mapData: map)
            defer { fixture.removeFiles() }
            let review = try fixture.review()
            let result = try review.commit()
            #expect(try fixture.container.repositories.variableMaps.fetchVariableMaps(buildID: result.build.id).first?.format == .gbStudioGlobals)
            #expect(review.importWarning == nil)
        }
    }
}

private final class GlobalsFixtureBundle {}

@MainActor
private struct Fixture {
    let root: URL
    let library: URL
    let container: AppContainer
    let file: SharedFile
    let mapData: Data

    init(romData: Data = Data(repeating: 0, count: 0x8000), romFilename: String = "Example.gb",
         mapData: Data = Data("VAR_SCORE = 0\nVAR_LIVES = 1\nMAX_GLOBAL_VARS = 2\n".utf8)) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        library = root.appendingPathComponent("Library")
        container = try AppContainer(rootURL: library)
        self.mapData = mapData
        let source = root.appendingPathComponent("Example.zip")
        try ZipArchiveWriter.archive(entries: [
            .init(relativePath: "Release/\(romFilename)", data: romData),
            .init(relativePath: "Release/globals.i", data: mapData),
        ]).write(to: source)
        let received = try container.sharedFileInbox.receiveAll(source)
        file = try #require(received.first)
    }

    func review() throws -> ImportReviewViewModel {
        let coordinator = ImportCoordinator(analyzer: container.importAnalyzer,
            committer: container.importCommitter, assetStore: container.fileStore)
        return ImportReviewViewModel(analysis: try coordinator.analyzeROM(at: file.url),
            games: try container.repositories.games.fetchGames(), coordinator: coordinator,
            variableMapURL: file.variableMapURL,
            attachVariableMap: { _ = try container.attachVariableMap.execute(buildID: $0, sourceURL: $1) })
    }

    func removeFiles() { try? FileManager.default.removeItem(at: root) }
}

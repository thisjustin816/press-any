import AssetStorage
import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import Testing

@Suite("Metadata Details edits")
struct MetadataDetailsTests {
    @Test("editing or clearing metadata keeps the offered value", arguments: ["  Japan  ", "", " \n "])
    func playerEdit(value: String) throws {
        let fixture = try MetadataEditFixture()
        defer { fixture.removeFiles() }
        try fixture.builds.saveMetadataProvenance(MetadataProvenance(field: .region, source: .noIntro,
            confidence: .high, providedValue: "USA", recordedAt: fixture.before), ownerID: fixture.build.id)

        try fixture.operations.setMetadata(buildID: fixture.build.id, field: .region, value: value)

        let updated = try #require(try fixture.builds.fetchBuild(id: fixture.build.id))
        #expect(updated.region == (value.contains("Japan") ? "Japan" : nil))
        #expect(updated.imageSHA256 == fixture.build.imageSHA256)
        #expect(updated.modifiedAt == fixture.now)
        let row = try #require(try fixture.builds.fetchMetadataProvenance(ownerID: updated.id).first { $0.field == .region })
        #expect(row.source == .player)
        #expect(row.confidence == nil)
        #expect(row.providedValue == "USA")
        #expect(row.recordedAt == fixture.now)
    }

    @Test("using an offered value keeps the player source")
    func useOfferedValue() throws {
        let fixture = try MetadataEditFixture()
        defer { fixture.removeFiles() }
        try fixture.builds.saveMetadataProvenance(MetadataProvenance(field: .region, source: .player,
            providedValue: "Europe", recordedAt: fixture.before), ownerID: fixture.build.id)
        let offered = try #require(try fixture.builds.fetchMetadataProvenance(ownerID: fixture.build.id).first?.providedValue)

        try fixture.operations.setMetadata(buildID: fixture.build.id, field: .region, value: offered)

        #expect(try fixture.builds.fetchBuild(id: fixture.build.id)?.region == "Europe")
        let row = try #require(try fixture.builds.fetchMetadataProvenance(ownerID: fixture.build.id).first)
        #expect(row.source == .player)
        #expect(row.providedValue == "Europe")
    }

    @Test("saving an unchanged value records a player override")
    func unchangedValue() throws {
        let fixture = try MetadataEditFixture()
        defer { fixture.removeFiles() }
        try fixture.builds.saveMetadataProvenance(MetadataProvenance(field: .region, source: .filename,
            providedValue: "USA", recordedAt: fixture.before), ownerID: fixture.build.id)
        try fixture.operations.setMetadata(buildID: fixture.build.id, field: .region, value: "USA")
        #expect(try fixture.builds.fetchMetadataProvenance(ownerID: fixture.build.id).first?.source == .player)
    }

    @Test("version edits update and clear the numeric sort key")
    func versionSortKey() throws {
        let fixture = try MetadataEditFixture()
        defer { fixture.removeFiles() }
        try fixture.operations.setMetadata(buildID: fixture.build.id, field: .versionString, value: "1.10")
        let updated = try #require(try fixture.builds.fetchBuild(id: fixture.build.id))
        #expect(updated.versionSortKey == "0000000001.0000000010.0000000000.0000000000~")
        try fixture.operations.setMetadata(buildID: fixture.build.id, field: .versionString, value: "")
        #expect(try fixture.builds.fetchBuild(id: fixture.build.id)?.versionSortKey == nil)
    }

    @Test("each optional field can be edited", arguments: MetadataField.allCases.filter { $0 != .title && $0 != .displayName })
    func optionalFields(field: MetadataField) throws {
        let fixture = try MetadataEditFixture()
        defer { fixture.removeFiles() }
        try fixture.operations.setMetadata(buildID: fixture.build.id, field: field, value: "Custom")
        let updated = try #require(try fixture.builds.fetchBuild(id: fixture.build.id))
        #expect(field.value(in: updated) == "Custom")
        #expect(try fixture.builds.fetchMetadataProvenance(ownerID: updated.id).first { $0.field == field }?.source == .player)
    }

    @Test("names use their rename operations and keep the offered value")
    func renameFields() throws {
        let fixture = try MetadataEditFixture()
        defer { fixture.removeFiles() }
        let gameID = fixture.build.gameID
        try fixture.games.saveMetadataProvenance(MetadataProvenance(field: .title, source: .noIntro,
            providedValue: "Offered Title", recordedAt: fixture.before), ownerID: gameID)
        try fixture.builds.saveMetadataProvenance(MetadataProvenance(field: .displayName, source: .filename,
            providedValue: "Offered Name", recordedAt: fixture.before), ownerID: fixture.build.id)
        try fixture.operations.renameGame(gameID: gameID, title: "Player Title")
        try fixture.operations.renameBuild(buildID: fixture.build.id, displayName: "Original")
        let title = try #require(try fixture.games.fetchMetadataProvenance(ownerID: gameID).first)
        let name = try #require(try fixture.builds.fetchMetadataProvenance(ownerID: fixture.build.id).first)
        #expect(title.source == .player)
        #expect(name.source == .player)
        #expect(title.providedValue == "Offered Title")
        #expect(name.providedValue == "Offered Name")
        try fixture.operations.renameGame(gameID: gameID, title: try #require(title.providedValue))
        try fixture.operations.renameBuild(buildID: fixture.build.id, displayName: try #require(name.providedValue))
        #expect(try fixture.games.fetchGame(id: gameID)?.primaryTitle == "Offered Title")
        #expect(try fixture.builds.fetchBuild(id: fixture.build.id)?.displayName == "Offered Name")
        #expect(try fixture.games.fetchMetadataProvenance(ownerID: gameID).first?.source == .player)
        #expect(try fixture.builds.fetchMetadataProvenance(ownerID: fixture.build.id).first?.source == .player)
    }

    @Test("renaming keeps metadata committed before its transaction")
    func renameKeepsFreshMetadata() throws {
        let fixture = try MetadataEditFixture()
        defer { fixture.removeFiles() }
        let builds = fixture.builds
        let buildID = fixture.build.id
        let operations = fixture.buildOperations(transactions: BeforeRenameTransaction {
            var refreshed = try #require(try builds.fetchBuild(id: buildID))
            refreshed.region = "Europe"
            try builds.updateBuildMetadata(refreshed)
        })
        try operations.renameBuild(buildID: buildID, displayName: "Renamed")
        #expect(try builds.fetchBuild(id: buildID)?.displayName == "Renamed")
        #expect(try builds.fetchBuild(id: buildID)?.region == "Europe")
    }
}

private struct MetadataEditFixture {
    let before = Date(timeIntervalSince1970: 100)
    let now = Date(timeIntervalSince1970: 200)
    let build: Build
    let games: InMemoryGameRepository
    let builds: InMemoryBuildRepository
    let store: ManagedFileStore
    var operations: BuildOperations { buildOperations() }

    init() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Metadata-\(UUID())")
        store = try ManagedFileStore(rootURL: root)
        build = Build(id: UUID(), gameID: UUID(), system: .gameBoy, displayName: "Original",
            imageAssetID: UUID(), imageSHA256: "image", sourceKind: .importedImage, region: "USA",
            createdAt: before, modifiedAt: before)
        builds = InMemoryBuildRepository([build])
        games = InMemoryGameRepository([Game(id: build.gameID, primaryTitle: "Original Title", systemFamily: "gameBoy",
            createdAt: before, modifiedAt: before)])
    }

    func buildOperations(transactions: any LibraryTransactionRunner = PassthroughTransactionRunner()) -> BuildOperations {
        let timestamp = now
        return BuildOperations(games: games, builds: builds,
            profiles: InMemorySaveProfileRepository(), states: InMemorySaveStateRepository(),
            recipes: InMemoryPatchRecipeRepository(), cheats: InMemoryBuildCheatRepository(builds: builds),
            assets: InMemoryAssetRepository(), assetStore: store,
            transactions: transactions, now: { timestamp })
    }

    func removeFiles() { try? FileManager.default.removeItem(at: store.rootURL) }
}

private struct BeforeRenameTransaction: LibraryTransactionRunner {
    let before: @Sendable () throws -> Void
    func run<T: Sendable>(_ operation: @Sendable () throws -> T) throws -> T {
        try before()
        return try operation()
    }
}

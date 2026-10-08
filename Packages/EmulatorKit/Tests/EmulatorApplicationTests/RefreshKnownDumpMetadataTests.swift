import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import GameIdentity
@testable import Importing
import Testing

@Suite("Quiet No-Intro refresh")
struct RefreshKnownDumpMetadataTests {
    @Test("known-dump import leaves an omitted revision empty")
    func importWithoutCatalogRevision() {
        let dump = KnownDump(name: "Catalog Title (Europe)", system: .gameBoy, title: "Catalog Title",
            region: "Europe", languages: "En,Fr", files: [KnownDumpFile(sha1: "known", size: 32_768)])
        let header = GBROMHeader(title: "HEADER", system: .gameBoy, cgbFlag: 0, cartridgeType: 0,
            romSizeCode: 0, ramSizeCode: 0, headerChecksum: 0, headerChecksumValid: true,
            globalChecksum: 0, globalChecksumValid: true, revisionNumber: 7)
        let analysis = ROMImportAnalysis(transactionID: UUID(), stagedURL: URL(fileURLWithPath: "/unused.gb"),
            originalFilename: "file.gb", sha256: "image", byteLength: 32_768, header: header,
            filenameMetadata: FilenameMetadata(knownDump: dump, fileExtension: "gb"),
            exactExistingBuildID: nil, suggestedGameID: nil, knownDump: dump)
        let metadata = BuildImportMetadata(analysis: analysis)
        #expect(metadata.revision == nil)
        #expect(metadata.language == "En, Fr")
        #expect(metadata == BuildImportMetadata(knownDump: dump))
    }

    @Test("refresh only changes eligible fields", arguments: [MetadataSource.noIntro, .filename, .romHeader, .player, .patch])
    func eligibleSources(source: MetadataSource) throws {
        let fixture = RefreshMetadataFixture()
        let build = fixture.build()
        try fixture.builds.insertBuild(build)
        let games = InMemoryGameRepository([Game(id: build.gameID, primaryTitle: "Existing Title", systemFamily: "gameBoy",
            createdAt: fixture.before, modifiedAt: fixture.before)])
        try games.saveMetadataProvenance(MetadataProvenance(field: .title, source: .noIntro,
            providedValue: "Existing Title", recordedAt: fixture.before), ownerID: build.gameID)
        let originalGame = try games.fetchGame(id: build.gameID)
        let originalTitle = try games.fetchMetadataProvenance(ownerID: build.gameID)
        for field in MetadataField.allCases where field != .title {
            try fixture.builds.saveMetadataProvenance(MetadataProvenance(field: field, source: source,
                confidence: .medium, providedValue: field.value(in: build), recordedAt: fixture.before), ownerID: build.id)
        }
        try fixture.refresh().execute()

        let updated = try #require(try fixture.builds.fetchBuild(id: build.id))
        let eligible = source == .noIntro || source == .filename || source == .romHeader
        if eligible {
            #expect(updated.region == "Europe")
            #expect(updated.language == "En, Fr")
            #expect(updated.revision == nil)
            #expect(updated.versionString == "1.10-beta.2")
            #expect(updated.versionSortKey == "0000000001.0000000010.0000000000.0000000000-beta.0000000002")
            #expect(updated.status == nil)
            #expect(updated.modifiedAt == fixture.now)
        } else {
            #expect(updated == build)
        }
        #expect(updated.displayName == build.displayName)
        #expect(updated.baseTitle == build.baseTitle)
        #expect(updated.hackTitle == build.hackTitle)
        #expect(updated.author == build.author)
        #expect(updated.translation == build.translation)
        #expect(updated.imageSHA256 == build.imageSHA256)
        #expect(try games.fetchGame(id: build.gameID) == originalGame)
        #expect(try games.fetchMetadataProvenance(ownerID: build.gameID) == originalTitle)
        let rows = try fixture.builds.fetchMetadataProvenance(ownerID: build.id)
        for field in RefreshMetadataFixture.fields {
            let row = try #require(rows.first { $0.field == field })
            #expect(row.source == (eligible ? .noIntro : source))
            #expect(row.confidence == (eligible ? .high : .medium))
            #expect(row.providedValue == field.value(in: updated))
            #expect(row.recordedAt == (eligible ? fixture.now : fixture.before))
        }
        for field in [MetadataField.displayName, .baseTitle, .hackTitle, .author, .translation] {
            #expect(rows.first { $0.field == field }?.source == source)
            #expect(rows.first { $0.field == field }?.recordedAt == fixture.before)
        }
    }

    @Test("unrecorded fields, unmatched images and other systems stay unchanged")
    func excludedBuilds() throws {
        let fixture = RefreshMetadataFixture()
        let unrecorded = fixture.build()
        let unmatched = fixture.build(sha1: "absent")
        let otherSystem = fixture.build(system: .gameBoyColor)
        for build in [unrecorded, unmatched, otherSystem] {
            try fixture.builds.insertBuild(build)
            if build.id != unrecorded.id {
                try fixture.builds.saveMetadataProvenance(MetadataProvenance(field: .region, source: .noIntro,
                    providedValue: "USA", recordedAt: fixture.before), ownerID: build.id)
            }
        }
        try fixture.refresh().execute()
        for build in [unrecorded, unmatched, otherSystem] {
            #expect(try fixture.builds.fetchBuild(id: build.id) == build)
        }
        #expect(try fixture.builds.fetchMetadataProvenance(ownerID: unrecorded.id).isEmpty)
    }

    @Test("a matching field without provenance is skipped beside a recorded field")
    func unrecordedField() throws {
        let fixture = RefreshMetadataFixture()
        let build = fixture.build()
        try fixture.builds.insertBuild(build)
        try fixture.builds.saveMetadataProvenance(MetadataProvenance(field: .language, source: .filename,
            providedValue: "En", recordedAt: fixture.before), ownerID: build.id)
        try fixture.refresh().execute()
        #expect(try fixture.builds.fetchBuild(id: build.id)?.region == "USA")
        #expect(try fixture.builds.fetchBuild(id: build.id)?.language == "En, Fr")
        #expect(try fixture.builds.fetchMetadataProvenance(ownerID: build.id).map(\.field) == [.language])
    }

    @Test("an unchanged version does no work, and a changed version reapplies")
    func versionGate() throws {
        let fixture = RefreshMetadataFixture()
        try fixture.refresh().execute()
        let build = fixture.build()
        try fixture.builds.insertBuild(build)
        try fixture.builds.saveMetadataProvenance(MetadataProvenance(field: .region, source: .filename,
            providedValue: "USA", recordedAt: fixture.before), ownerID: build.id)
        try fixture.refresh().execute()
        #expect(try fixture.builds.fetchBuild(id: build.id) == build)
        try fixture.refresh(version: "2").execute()
        #expect(try fixture.builds.fetchBuild(id: build.id)?.region == "Europe")
        #expect(try fixture.settings.valueJSON(key: "noIntro.appliedVersion", scope: .system(.gameBoy)) == "\"2\"")
    }

    @Test("versions are applied separately for each system")
    func systemVersions() throws {
        let fixture = RefreshMetadataFixture()
        try fixture.refresh(colorVersion: "1").execute()
        let gb = fixture.build()
        let gbc = fixture.build(sha1: "color", system: .gameBoyColor)
        for build in [gb, gbc] {
            try fixture.builds.insertBuild(build)
            try fixture.builds.saveMetadataProvenance(MetadataProvenance(field: .region, source: .filename,
                providedValue: "USA", recordedAt: fixture.before), ownerID: build.id)
        }
        try fixture.refresh(version: "2", colorVersion: "1").execute()
        #expect(try fixture.builds.fetchBuild(id: gb.id)?.region == "Europe")
        #expect(try fixture.builds.fetchBuild(id: gbc.id) == gbc)
        try fixture.refresh(version: "2", colorVersion: "2").execute()
        #expect(try fixture.builds.fetchBuild(id: gbc.id)?.region == "Japan")
    }

    @Test("a failed pass keeps the last applied version and retries")
    func retryAfterFailure() throws {
        let fixture = RefreshMetadataFixture()
        try fixture.refresh().execute()
        let build = fixture.build()
        try fixture.builds.insertBuild(build)
        try fixture.builds.saveMetadataProvenance(MetadataProvenance(field: .region, source: .filename,
            providedValue: "USA", recordedAt: fixture.before), ownerID: build.id)
        let failing = FailingRefreshSettings(inner: fixture.settings)
        #expect(throws: RefreshTestError.failed) {
            try fixture.refresh(version: "2", settings: failing).execute()
        }
        #expect(try fixture.settings.valueJSON(key: "noIntro.appliedVersion", scope: .system(.gameBoy)) == "\"1\"")
        try fixture.refresh(version: "2").execute()
        #expect(try fixture.settings.valueJSON(key: "noIntro.appliedVersion", scope: .system(.gameBoy)) == "\"2\"")
        #expect(try fixture.builds.fetchBuild(id: build.id)?.region == "Europe")
    }
}

private struct RefreshMetadataFixture {
    static let fields: [MetadataField] = [.region, .language, .revision, .versionString, .status]
    let before = Date(timeIntervalSince1970: 100)
    let now = Date(timeIntervalSince1970: 200)
    let builds = InMemoryBuildRepository()
    let settings = InMemorySettingsStore()

    func build(sha1: String = "known", system: GameSystem = .gameBoy) -> Build {
        Build(id: UUID(), gameID: UUID(), system: system, displayName: "Player's Build",
            imageAssetID: UUID(), imageSHA256: "image", imageSHA1: sha1, sourceKind: .importedImage,
            region: "USA", language: "En", revision: "A", versionString: "1.1",
            versionSortKey: "old", baseTitle: "Base", hackTitle: "Hack", author: "Author",
            translation: "Spanish", status: "Beta", createdAt: before, modifiedAt: before)
    }

    func refresh(version: String = "1", colorVersion: String? = nil,
                 settings store: (any SettingsStore)? = nil) throws -> RefreshKnownDumpMetadata {
        let dump = KnownDump(name: "Catalog Title (Europe)", system: .gameBoy, title: "Catalog Title",
            region: "Europe", languages: "En,Fr", version: "v1.10-beta.2",
            files: [KnownDumpFile(sha1: "known", size: 32_768)])
        var dumps = [dump]
        var systems = [KnownDumpCatalog.SystemData(system: .gameBoy, dat: "Game Boy", version: version, games: 1, files: 1)]
        if let colorVersion {
            dumps.append(KnownDump(name: "Color Title (Japan)", system: .gameBoyColor, title: "Color Title", region: "Japan",
                files: [KnownDumpFile(sha1: "color", size: 32_768)]))
            systems.append(.init(system: .gameBoyColor, dat: "Game Boy Color", version: colorVersion, games: 1, files: 1))
        }
        let index = try KnownDumpIndex(catalog: KnownDumpCatalog(source: "test", generated: "2026-10-08",
            systems: systems, games: dumps))
        let timestamp = now
        return RefreshKnownDumpMetadata(builds: builds, settings: store ?? settings, index: index, now: { timestamp })
    }
}

private enum RefreshTestError: Error { case failed }

private struct FailingRefreshSettings: SettingsStore {
    let inner: InMemorySettingsStore
    func valueJSON(key: String, scope: SettingsScope) throws -> String? { try inner.valueJSON(key: key, scope: scope) }
    func setValueJSON(_ valueJSON: String, key: String, scope: SettingsScope) throws { throw RefreshTestError.failed }
    func removeValue(key: String, scope: SettingsScope) throws { try inner.removeValue(key: key, scope: scope) }
}

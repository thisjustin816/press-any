import EmulatorApplication
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import Importing
import Testing

@Suite("Clearing GBDK header revisions")
struct ClearGBDKHeaderRevisionsTests {
    @Test("a header Revision on a GBDK, GB Studio or ZGB Build is cleared once",
          arguments: ["gbdk450-dmg.gb", "gbstudio-dmg.gb", "zgb-dmg.gb"])
    func clearsHeaderRevision(filename: String) throws {
        let fixture = Fixture()
        let build = try fixture.add(filename, source: .romHeader, offered: "1")
        #expect(try fixture.cleanup().execute() == [build.id])

        let updated = try #require(try fixture.builds.fetchBuild(id: build.id))
        #expect(updated.revision == nil)
        #expect(updated.modifiedAt == fixture.now)
        let row = try #require(try fixture.builds.fetchMetadataProvenance(ownerID: build.id).first { $0.field == .revision })
        #expect(row.source == .romHeader)
        #expect(row.providedValue == nil)
        #expect(try fixture.cleanup().execute().isEmpty)
    }

    @Test("a Revision the player set, or the filename gave, stays", arguments: [MetadataSource.player, .filename])
    func keepsOtherSources(source: MetadataSource) throws {
        let fixture = Fixture()
        let build = try fixture.add("gbdk450-dmg.gb", source: source, offered: source == .player ? nil : "1")
        #expect(try fixture.cleanup().execute().isEmpty)
        #expect(try fixture.builds.fetchBuild(id: build.id) == build)
    }

    @Test("a header Revision on an image not built with GBDK stays")
    func keepsOtherToolchains() throws {
        let fixture = Fixture()
        var image = try TestROMFixtures.rom("rgbds-dmg.gb")
        image[0x14c] = 1
        let build = try fixture.add("rgbds-dmg.gb", image: image, source: .romHeader, offered: "1")
        #expect(try fixture.cleanup().execute().isEmpty)
        #expect(try fixture.builds.fetchBuild(id: build.id)?.revision == "1")
    }

    @Test("a Build whose image can't be read doesn't stop the others")
    func unreadableImage() throws {
        let fixture = Fixture()
        let missing = try fixture.add("gbdk450-dmg.gb", source: nil, offered: nil)
        fixture.removeImage(buildID: missing.id)
        let build = try fixture.add("gbdk450-dmg.gb", source: .romHeader, offered: "1")
        #expect(try fixture.cleanup().execute() == [build.id])
        #expect(try fixture.builds.fetchBuild(id: missing.id)?.revision == "1")
    }

    @Test("with no provenance, a Revision matching the header byte is cleared unless the filename names it",
          arguments: [("gbdk450-dmg.gb", true), ("Homebrew (Rev 1).gb", false)])
    func noProvenance(importedAs filename: String, clears: Bool) throws {
        let fixture = Fixture()
        let build = try fixture.add("gbdk450-dmg.gb", importedAs: filename, source: nil, offered: nil)
        #expect(try fixture.cleanup().execute() == (clears ? [build.id] : []))
        #expect(try fixture.builds.fetchBuild(id: build.id)?.revision == (clears ? nil : "1"))
    }
}

private final class Fixture: @unchecked Sendable {
    let builds = InMemoryBuildRepository()
    let assets = InMemoryAssetRepository()
    let reports = InMemoryToolchainReportRepository()
    let before = Date(timeIntervalSince1970: 10)
    let now = Date(timeIntervalSince1970: 20)
    private var images: [UUID: Data] = [:]

    /// A Build as import stored it before GBDK images were told apart, with the header's Revision 1.
    /// `source` nil leaves no provenance row.
    func add(_ fixture: String, image: Data? = nil, importedAs filename: String? = nil,
             source: MetadataSource?, offered: String?) throws -> Build {
        let asset = ManagedAsset(id: UUID(), kind: .sourceImage, storageClass: .source, contentSHA256: fixture,
            byteLength: 32_768, relativePath: "Source/ROM/\(UUID().uuidString)", originalFilename: filename ?? fixture, createdAt: before)
        try assets.insertAsset(asset)
        let build = Build(id: UUID(), gameID: UUID(), system: .gameBoy, displayName: "Original",
            imageAssetID: asset.id, imageSHA256: fixture, sourceKind: .importedImage, revision: "1",
            createdAt: before, modifiedAt: before)
        try builds.insertBuild(build)
        images[build.id] = try image ?? TestROMFixtures.rom(fixture)
        if let source {
            try builds.saveMetadataProvenance(MetadataProvenance(field: .revision, source: source,
                providedValue: offered, recordedAt: before), ownerID: build.id)
        }
        return build
    }

    func removeImage(buildID: UUID) { images[buildID] = nil }

    func cleanup() -> ClearGBDKHeaderRevisions {
        ClearGBDKHeaderRevisions(builds: builds, assets: assets, reports: reports,
            images: ImageTable(images: images), knownDumps: nil, now: { [now] in now })
    }
}

private struct ImageTable: BuildImageResolving {
    let images: [UUID: Data]

    func resolveImageURL(buildID: UUID) throws -> URL { URL(fileURLWithPath: "/unused") }

    func readImage(buildID: UUID) throws -> Data {
        guard let image = images[buildID] else { throw CocoaError(.fileNoSuchFile) }
        return image
    }
}

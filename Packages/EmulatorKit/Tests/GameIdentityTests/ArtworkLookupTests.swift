import EmulatorApplication
import EmulatorDomain
import Foundation
import GameIdentity
import XCTest

final class ArtworkLookupTests: XCTestCase {
    func testLookupUsesTheVerifiedRegionalNameAndThenOmitsItsRevision() throws {
        let dump = KnownDump(name: "Example (Japan) (Rev 1)", system: .gameBoyColor,
            title: "Example", region: "Japan", version: "Rev 1", files: [.init(sha1: "known", size: 32768)])
        let index = try index([dump])
        let build = build(sha1: "known")
        XCTAssertEqual(index.artworkLookup(for: build, lookup: { _ in nil }),
            ArtworkLookup(system: .gameBoyColor, releaseNames: [dump.name, "Example (Japan)"], inherited: false))
    }

    func testUnknownAndBadDumpsDoNotGuessFromTheirDisplayNames() throws {
        let bad = KnownDump(name: "Example (USA)", system: .gameBoyColor, title: "Example",
            files: [.init(sha1: "bad", size: 32768, bad: true)])
        let index = try index([bad])
        XCTAssertNil(index.artworkLookup(for: build(sha1: "unknown"), lookup: { _ in nil }))
        XCTAssertNil(index.artworkLookup(for: build(sha1: "bad"), lookup: { _ in nil }))
    }

    func testAPatchedBuildInheritsItsVerifiedBaseArtwork() throws {
        let dump = KnownDump(name: "Example (USA)", system: .gameBoyColor, title: "Example",
            files: [.init(sha1: "known", size: 32768)])
        let index = try index([dump])
        let base = build(sha1: "known")
        let patched = build(parent: base.id)
        XCTAssertEqual(index.artworkLookup(for: patched, lookup: { $0 == base.id ? base : nil }),
            ArtworkLookup(system: .gameBoyColor, releaseNames: [dump.name], inherited: true))
    }

    func testAConfirmedBaseReferenceIsMatchedToTheCatalog() throws {
        let dump = KnownDump(name: "Example (USA)", system: .gameBoyColor, title: "Example", files: [])
        let index = try index([dump])
        var hack = build()
        hack.baseGameReference = index.reference(to: dump)
        XCTAssertEqual(index.artworkLookup(for: hack, lookup: { _ in nil }),
            ArtworkLookup(system: .gameBoyColor, releaseNames: [dump.name], inherited: true))
        hack.baseGameReference = BaseGameReference(title: "Example", system: .gameBoy, releaseName: dump.name)
        XCTAssertNil(index.artworkLookup(for: hack, lookup: { _ in nil }))
    }

    func testAColorizedBuildInheritsFromItsGameBoyBase() throws {
        let dump = KnownDump(name: "Example (USA)", system: .gameBoy, title: "Example",
            files: [.init(sha1: "known", size: 32768)])
        let index = try index([dump])
        let base = build(sha1: "known", system: .gameBoy)
        let colorized = build(parent: base.id)
        XCTAssertEqual(index.artworkLookup(for: colorized, lookup: { $0 == base.id ? base : nil }),
            ArtworkLookup(system: .gameBoy, releaseNames: [dump.name], inherited: true))
    }

    private func index(_ games: [KnownDump]) throws -> KnownDumpIndex {
        try KnownDumpIndex(catalog: .init(source: "synthetic", generated: "", systems: [], games: games))
    }

    private func build(sha1: String? = nil, parent: UUID? = nil, system: GameSystem = .gameBoyColor) -> Build {
        Build(id: UUID(), gameID: UUID(), system: system, displayName: "Renamed by player",
            imageAssetID: UUID(), imageSHA256: "synthetic", imageSHA1: sha1,
            sourceKind: parent == nil ? .importedImage : .patchRecipe, parentBuildID: parent,
            createdAt: .distantPast, modifiedAt: .distantPast)
    }
}

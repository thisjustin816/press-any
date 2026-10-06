import EmulatorDomain
import Foundation
import GameIdentity
import XCTest

final class KnownDumpIndexTests: XCTestCase {
    private let red = KnownDump(sha256: "AA01", name: "Pocket Critters - Red Version (USA, Europe)", size: 1, system: .gameBoy, regions: ["USA", "EUR"])
    private let aka = KnownDump(sha256: "bb02", name: "Pocket Critters - Aka (Japan)", size: 1, system: .gameBoy, parent: "Pocket Critters - Red Version (USA, Europe)", regions: ["JPN"])
    private let akaRev = KnownDump(sha256: "bb03", name: "Pocket Critters - Aka (Japan) (Rev 1)", size: 1, system: .gameBoy, parent: "Pocket Critters - Red Version (USA, Europe)")
    private let moon = KnownDump(sha256: "dd04", name: "Moon Garden (World) (Aftermarket) (Unl)", size: 1, system: .gameBoy)
    // The same name in the other system is another game.
    private let colorRed = KnownDump(sha256: "ee05", name: "Pocket Critters - Red Version (USA, Europe)", size: 1, system: .gameBoyColor)

    private func catalog(_ dumps: [KnownDump], gb: Int? = nil, gbc: Int? = nil) -> KnownDumpCatalog {
        KnownDumpCatalog(
            source: "test",
            generated: "2026-10-06",
            systems: [
                .init(system: .gameBoy, dat: "Nintendo - Game Boy", version: "1", dumps: gb ?? dumps.filter { $0.system == .gameBoy }.count),
                .init(system: .gameBoyColor, dat: "Nintendo - Game Boy Color", version: "1", dumps: gbc ?? dumps.filter { $0.system == .gameBoyColor }.count),
            ],
            dumps: dumps
        )
    }

    private func index() throws -> KnownDumpIndex {
        try KnownDumpIndex(catalog: catalog([akaRev, colorRed, red, moon, aka]))
    }

    func testTheBundledFileLoads() throws {
        let bundled = try KnownDumpIndex.bundled()
        XCTAssertEqual(bundled.catalog.systems.map(\.system), [.gameBoy, .gameBoyColor])
        XCTAssertTrue(bundled.catalog.source.hasPrefix("No-Intro"))
    }

    func testLookupIgnoresTheCaseOfTheHash() throws {
        let index = try index()
        XCTAssertEqual(index.dump(sha256: "aa01"), red)
        XCTAssertEqual(index.dump(sha256: "BB02"), aka)
        XCTAssertNil(index.dump(sha256: "ff"))
    }

    func testAFamilyIsItsParentThenItsClonesFromAnyMember() throws {
        let index = try index()
        XCTAssertEqual(index.family(of: aka), [red, aka, akaRev])
        XCTAssertEqual(index.family(of: red), [red, aka, akaRev])
        XCTAssertEqual(index.family(of: moon), [moon])
        XCTAssertEqual(index.family(of: colorRed), [colorRed], "a family stays within its system")
    }

    func testTheTitleIsTheNameBeforeItsTags() {
        XCTAssertEqual(aka.title, "Pocket Critters - Aka")
        XCTAssertEqual(moon.title, "Moon Garden")
        XCTAssertEqual(KnownDump(sha256: "1", name: "Plain", size: 1, system: .gameBoy).title, "Plain")
        XCTAssertEqual(KnownDump(sha256: "2", name: "Bracketed [b]", size: 1, system: .gameBoy).title, "Bracketed")
    }

    func testVerificationFollowsPatchesBackToTheirDump() throws {
        let index = try index()
        let created = Date(timeIntervalSince1970: 0)
        func build(_ hash: String, parent: Build? = nil) -> Build {
            Build(
                id: UUID(), gameID: UUID(), system: .gameBoy, displayName: hash, imageAssetID: UUID(),
                imageSHA256: hash, sourceKind: parent == nil ? .importedImage : .patchRecipe,
                parentBuildID: parent?.id, createdAt: created, modifiedAt: created
            )
        }
        let verified = build("aa01")
        let patched = build("0101", parent: verified)
        let patchedTwice = build("0202", parent: patched)
        let officialRevision = build("bb03", parent: verified)
        let homebrew = build("0303")
        let lookup = Dictionary(uniqueKeysWithValues: [verified, patched, patchedTwice].map { ($0.id, $0) })

        XCTAssertEqual(index.verification(of: verified) { lookup[$0] }, .verified(red))
        XCTAssertEqual(index.verification(of: patched) { lookup[$0] }, .modified(from: red))
        XCTAssertEqual(index.verification(of: patchedTwice) { lookup[$0] }, .modified(from: red))
        XCTAssertEqual(index.verification(of: officialRevision) { lookup[$0] }, .verified(akaRev))
        XCTAssertEqual(index.verification(of: homebrew) { lookup[$0] }, .unknown)
        XCTAssertEqual(index.verification(of: build("0404", parent: homebrew)) { _ in nil }, .unknown, "a missing base ends the chain")
    }

    func testAFileThatBreaksItsPromisesIsRefused() {
        XCTAssertThrowsError(try KnownDumpIndex(catalog: catalog([red, KnownDump(sha256: "aa01", name: "Copy", size: 1, system: .gameBoy)]))) {
            XCTAssertEqual($0 as? KnownDumpError, .repeatedHash("aa01"))
        }
        XCTAssertThrowsError(try KnownDumpIndex(catalog: catalog([aka]))) {
            XCTAssertEqual($0 as? KnownDumpError, .unknownParent(dump: aka.name, parent: red.name))
        }
        XCTAssertThrowsError(try KnownDumpIndex(catalog: catalog([red], gb: 2))) {
            XCTAssertEqual($0 as? KnownDumpError, .countMismatch(system: .gameBoy, stated: 2, found: 1))
        }
    }

    func testTheGeneratorsOutputDecodes() throws {
        let json = #"""
        {"source": "No-Intro, DAT-o-MATIC Parent/Clone XML", "generated": "2026-10-06",
         "systems": [{"system": "gb", "dat": "Nintendo - Game Boy", "version": "20261006-105659", "dumps": 2},
                     {"system": "gbc", "dat": "Nintendo - Game Boy Color", "version": "20261006-110346", "dumps": 0}],
         "dumps": [{"sha256": "aa01", "name": "Pocket Critters - Red Version (USA, Europe)", "size": 1048576, "system": "gb", "regions": ["USA", "EUR"]},
                   {"sha256": "bb02", "name": "Pocket Critters - Aka (Japan)", "size": 524288, "system": "gb", "parent": "Pocket Critters - Red Version (USA, Europe)", "regions": ["JPN"]}]}
        """#
        let index = try KnownDumpIndex(data: Data(json.utf8))
        XCTAssertEqual(index.dump(sha256: "bb02")?.parent, red.name)
        XCTAssertEqual(index.dump(sha256: "aa01")?.size, 1_048_576)
        XCTAssertEqual(index.catalog.systems.first?.version, "20261006-105659")
    }
}

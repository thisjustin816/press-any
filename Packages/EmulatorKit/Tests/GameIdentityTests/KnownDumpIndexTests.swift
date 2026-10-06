import EmulatorDomain
import Foundation
import GameIdentity
import XCTest

final class KnownDumpIndexTests: XCTestCase {
    private let red = KnownDump(
        name: "Pocket Critters - Red Version (USA, Europe)", system: .gameBoy, title: "Pocket Critters - Red Version",
        region: "USA, Europe", languages: "En", files: [KnownDumpFile(sha1: "AA01", size: 1)]
    )
    // A good copy and a bad one of the same game.
    private let aka = KnownDump(
        name: "Pocket Critters - Aka (Japan)", system: .gameBoy, title: "Pocket Critters - Aka",
        parent: "Pocket Critters - Red Version (USA, Europe)",
        files: [KnownDumpFile(sha1: "bb02", size: 1), KnownDumpFile(sha1: "cc06", size: 1, bad: true)]
    )
    private let akaRev = KnownDump(
        name: "Pocket Critters - Aka (Japan) (Rev 1)", system: .gameBoy, title: "Pocket Critters - Aka",
        version: "Rev 1", parent: "Pocket Critters - Red Version (USA, Europe)", files: [KnownDumpFile(sha1: "bb03", size: 1)]
    )
    private let moon = KnownDump(
        name: "Moon Garden (World) (Aftermarket) (Unl)", system: .gameBoy, title: "Moon Garden",
        aftermarket: true, unlicensed: true, files: [KnownDumpFile(sha1: "dd04", size: 1)]
    )
    // The same name in the other system is another game.
    private let colorRed = KnownDump(
        name: "Pocket Critters - Red Version (USA, Europe)", system: .gameBoyColor, title: "Pocket Critters - Red Version",
        files: [KnownDumpFile(sha1: "ee05", size: 1)]
    )

    private func catalog(_ games: [KnownDump], gb: Int? = nil) -> KnownDumpCatalog {
        func count(_ system: GameSystem) -> (games: Int, files: Int) {
            let found = games.filter { $0.system == system }
            return (found.count, found.reduce(0) { $0 + $1.files.count })
        }
        return KnownDumpCatalog(
            source: "test",
            generated: "2026-10-06",
            systems: [
                .init(system: .gameBoy, dat: "Nintendo - Game Boy", version: "1", games: gb ?? count(.gameBoy).games, files: count(.gameBoy).files),
                .init(system: .gameBoyColor, dat: "Nintendo - Game Boy Color", version: "1", games: count(.gameBoyColor).games, files: count(.gameBoyColor).files),
            ],
            games: games
        )
    }

    private func index() throws -> KnownDumpIndex {
        try KnownDumpIndex(catalog: catalog([akaRev, colorRed, red, moon, aka]))
    }

    func testTheBundledFileLoads() throws {
        let bundled = try KnownDumpIndex.bundled()
        XCTAssertEqual(bundled.catalog.systems.map(\.system), [.gameBoy, .gameBoyColor])
        XCTAssertTrue(bundled.catalog.source.hasPrefix("No-Intro"))
        XCTAssertFalse(bundled.catalog.games.isEmpty)
        XCTAssertTrue(bundled.catalog.games.allSatisfy { !$0.files.isEmpty && $0.files.allSatisfy { $0.sha1.count == 40 } }, "every key is a SHA-1")
    }

    func testEveryFileOfAGameLeadsToItIgnoringTheCaseOfTheHash() throws {
        let index = try index()
        XCTAssertEqual(index.dump(sha1: "aa01"), red)
        XCTAssertEqual(index.dump(sha1: "BB02"), aka)
        XCTAssertEqual(index.dump(sha1: "cc06"), aka, "a bad copy is still a copy of the game")
        XCTAssertEqual(index.file(sha1: "cc06")?.bad, true)
        XCTAssertEqual(index.file(sha1: "bb02")?.bad, false)
        XCTAssertNil(index.dump(sha1: "ff"))
    }

    func testAFamilyIsItsRootThenItsClonesFromAnyMember() throws {
        let index = try index()
        XCTAssertEqual(index.family(of: aka), [red, aka, akaRev])
        XCTAssertEqual(index.family(of: red), [red, aka, akaRev])
        XCTAssertEqual(index.family(of: moon), [moon])
        XCTAssertEqual(index.family(of: colorRed), [colorRed], "a family stays within its system")
    }

    func testVerificationFollowsPatchesBackToTheirGame() throws {
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
        let bad = build("cc06")
        let patchedFromBad = build("0505", parent: bad)
        let lookup = Dictionary(uniqueKeysWithValues: [verified, patched, patchedTwice, bad].map { ($0.id, $0) })
        // The test Builds' image hashes stand in for their SHA-1.
        func check(_ build: Build) -> DumpVerification {
            index.verification(of: build, sha1: { $0.imageSHA256 }, lookup: { lookup[$0] })
        }

        XCTAssertEqual(check(verified), .verified(red))
        XCTAssertEqual(check(patched), .modified(from: red))
        XCTAssertEqual(check(patchedTwice), .modified(from: red))
        XCTAssertEqual(check(officialRevision), .verified(akaRev))
        XCTAssertEqual(check(homebrew), .unknown)
        XCTAssertEqual(check(bad), .badDump(aka))
        XCTAssertEqual(check(patchedFromBad), .unknown, "a patch on a bad copy isn't a modified known game")
        XCTAssertEqual(
            index.verification(of: build("0404", parent: homebrew), sha1: { $0.imageSHA256 }, lookup: { _ in nil }),
            .unknown,
            "a missing base ends the chain"
        )
        XCTAssertEqual(index.verification(of: verified, sha1: { _ in nil }, lookup: { lookup[$0] }), .unknown, "no SHA-1, no match")
    }

    func testAFileThatBreaksItsPromisesIsRefused() {
        let copy = KnownDump(name: "Copy", system: .gameBoy, title: "Copy", files: [KnownDumpFile(sha1: "aa01", size: 1)])
        XCTAssertThrowsError(try KnownDumpIndex(catalog: catalog([red, copy]))) {
            XCTAssertEqual($0 as? KnownDumpError, .repeatedHash("aa01"))
        }
        XCTAssertThrowsError(try KnownDumpIndex(catalog: catalog([aka]))) {
            XCTAssertEqual($0 as? KnownDumpError, .unknownParent(game: aka.name, parent: red.name))
        }
        XCTAssertThrowsError(try KnownDumpIndex(catalog: catalog([red], gb: 2))) {
            XCTAssertEqual($0 as? KnownDumpError, .countMismatch(system: .gameBoy, stated: 2, found: 1))
        }
    }

    func testTheGeneratorsOutputDecodes() throws {
        let json = #"""
        {"source": "No-Intro, DAT-o-MATIC DB Export", "generated": "2026-10-06",
         "systems": [{"system": "gb", "dat": "Nintendo - Game Boy", "version": "20261006-105659", "games": 2, "files": 3},
                     {"system": "gbc", "dat": "Nintendo - Game Boy Color", "version": "20261006-110346", "games": 0, "files": 0}],
         "games": [
          {"name":"Moon Garden (World) (v1.1) (Aftermarket) (Unl)","system":"gb","title":"Moon Garden","region":"World","version":"v1.1","aftermarket":true,"unlicensed":true,"files":[{"sha1":"dd04","size":65536}]},
          {"name":"Pocket Critters - Aka (Japan)","system":"gb","title":"Pocket Critters - Aka","region":"Japan","languages":"Ja","status":"Beta 2","parent":"Moon Garden (World) (v1.1) (Aftermarket) (Unl)","files":[{"sha1":"bb02","size":524288},{"sha1":"cc06","size":524288,"bad":true}]}
         ]}
        """#
        let index = try KnownDumpIndex(data: Data(json.utf8))
        let aka = try XCTUnwrap(index.dump(sha1: "bb02"))
        XCTAssertEqual(aka.parent, "Moon Garden (World) (v1.1) (Aftermarket) (Unl)")
        XCTAssertEqual(aka.status, "Beta 2")
        XCTAssertEqual(aka.languages, "Ja")
        XCTAssertFalse(aka.aftermarket)
        XCTAssertEqual(index.file(sha1: "cc06")?.bad, true)
        let moon = try XCTUnwrap(index.dump(sha1: "dd04"))
        XCTAssertEqual(moon.version, "v1.1")
        XCTAssertTrue(moon.aftermarket && moon.unlicensed)
        XCTAssertEqual(index.catalog.systems.first?.files, 3)
    }
}

final class SHA1DigestTests: XCTestCase {
    func testKnownVectors() {
        XCTAssertEqual(SHA1Digest.data(Data()), "da39a3ee5e6b4b0d3255bfef95601890afd80709")
        XCTAssertEqual(SHA1Digest.data(Data("abc".utf8)), "a9993e364706816aba3e25717850c26c9cd0d89d")
        XCTAssertEqual(
            SHA1Digest.data(Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)),
            "84983e441c3bd26ebaae4aa1f95129e5e54670f1"
        )
        XCTAssertEqual(SHA1Digest.data(Data(repeating: UInt8(ascii: "a"), count: 1_000_000)), "34aa973cd4c4daa4f61eeb2bdbad27316534016f")
    }

    func testAFileReadInChunksHashesLikeItsBytes() throws {
        let bytes = Data((0..<10_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sha1-\(UUID()).bin")
        try bytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        // A chunk size that splits blocks unevenly exercises the partial-block path.
        XCTAssertEqual(try SHA1Digest.file(at: url, chunkSize: 37), SHA1Digest.data(bytes))
    }
}

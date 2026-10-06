import EmulatorDomain
import Foundation
import GameIdentity
import XCTest

final class KnownDumpIndexTests: XCTestCase {
    private let red = KnownDump(sha1: "AA01", name: "Pocket Critters - Red Version (USA, Europe)", size: 1, system: .gameBoy, regions: ["USA", "EUR"])
    private let aka = KnownDump(sha1: "bb02", name: "Pocket Critters - Aka (Japan)", size: 1, system: .gameBoy, parent: "Pocket Critters - Red Version (USA, Europe)", regions: ["JPN"])
    private let akaRev = KnownDump(sha1: "bb03", name: "Pocket Critters - Aka (Japan) (Rev 1)", size: 1, system: .gameBoy, parent: "Pocket Critters - Red Version (USA, Europe)")
    private let moon = KnownDump(sha1: "dd04", name: "Moon Garden (World) (Aftermarket) (Unl)", size: 1, system: .gameBoy)
    private let badCopy = KnownDump(sha1: "cc06", name: "Moon Garden (World) (Aftermarket) (Unl) [b]", size: 1, system: .gameBoy, bad: true)
    // The same name in the other system is another game.
    private let colorRed = KnownDump(sha1: "ee05", name: "Pocket Critters - Red Version (USA, Europe)", size: 1, system: .gameBoyColor)

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
        try KnownDumpIndex(catalog: catalog([akaRev, colorRed, red, moon, aka, badCopy]))
    }

    func testTheBundledFileLoads() throws {
        let bundled = try KnownDumpIndex.bundled()
        XCTAssertEqual(bundled.catalog.systems.map(\.system), [.gameBoy, .gameBoyColor])
        XCTAssertTrue(bundled.catalog.source.hasPrefix("No-Intro"))
        XCTAssertFalse(bundled.catalog.dumps.isEmpty)
        XCTAssertTrue(bundled.catalog.dumps.allSatisfy { $0.sha1.count == 40 }, "every key is a SHA-1")
    }

    func testLookupIgnoresTheCaseOfTheHash() throws {
        let index = try index()
        XCTAssertEqual(index.dump(sha1: "aa01"), red)
        XCTAssertEqual(index.dump(sha1: "BB02"), aka)
        XCTAssertNil(index.dump(sha1: "ff"))
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
        XCTAssertEqual(KnownDump(sha1: "1", name: "Plain", size: 1, system: .gameBoy).title, "Plain")
        XCTAssertEqual(KnownDump(sha1: "2", name: "Bracketed [b]", size: 1, system: .gameBoy).title, "Bracketed")
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
        XCTAssertEqual(check(bad), .badDump(badCopy))
        XCTAssertEqual(check(patchedFromBad), .unknown, "a patch on a bad dump isn't a modified known dump")
        XCTAssertEqual(
            index.verification(of: build("0404", parent: homebrew), sha1: { $0.imageSHA256 }, lookup: { _ in nil }),
            .unknown,
            "a missing base ends the chain"
        )
        XCTAssertEqual(index.verification(of: verified, sha1: { _ in nil }, lookup: { lookup[$0] }), .unknown, "no SHA-1, no match")
    }

    func testAFileThatBreaksItsPromisesIsRefused() {
        XCTAssertThrowsError(try KnownDumpIndex(catalog: catalog([red, KnownDump(sha1: "aa01", name: "Copy", size: 1, system: .gameBoy)]))) {
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
         "dumps": [{"sha1": "aa01", "name": "Pocket Critters - Red Version (USA, Europe)", "size": 1048576, "system": "gb", "regions": ["USA", "EUR"], "bad": true},
                   {"sha1": "bb02", "name": "Pocket Critters - Aka (Japan)", "size": 524288, "system": "gb", "parent": "Pocket Critters - Red Version (USA, Europe)", "regions": ["JPN"]}]}
        """#
        let index = try KnownDumpIndex(data: Data(json.utf8))
        XCTAssertEqual(index.dump(sha1: "bb02")?.parent, red.name)
        XCTAssertEqual(index.dump(sha1: "aa01")?.size, 1_048_576)
        XCTAssertEqual(index.dump(sha1: "aa01")?.bad, true)
        XCTAssertEqual(index.dump(sha1: "bb02")?.bad, false)
        XCTAssertEqual(index.catalog.systems.first?.version, "20261006-105659")
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

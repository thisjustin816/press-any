import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import Importing
import Testing

@Suite("Development Build matching")
struct DevelopmentBuildMatcherTests {
    private func fingerprint(_ title: String = "MOON", hashes: [UInt64] = [1, 2, 3, 4],
                             cart: UInt8 = 1, ram: UInt8 = 2, cgb: UInt8 = 0) -> ImageFingerprint {
        ImageFingerprint(imageSHA256: UUID().uuidString, bankSize: 0x4000, bankHashes: hashes,
            headerTitle: title, cartridgeType: cart, ramSizeCode: ram, cgbFlag: cgb)
    }

    private func game(_ title: String = "Moon Garden", aliases: [String] = []) -> Game {
        Game(id: UUID(), primaryTitle: title, systemFamily: "gameboy", aliases: aliases, createdAt: .distantPast, modifiedAt: .distantPast)
    }

    private func match(_ incoming: ImageFingerprint, _ other: ImageFingerprint,
                       filename: String = "build.gb", game: Game? = nil,
                       reports: [ToolchainDetectionReport] = [], otherReports: [ToolchainDetectionReport] = []) -> [DevelopmentBuildMatcher.Candidate] {
        DevelopmentBuildMatcher.match(arriving: .init(fingerprint: incoming,
            filenameMetadata: FilenameMetadataParser.parse(filename: filename), reports: reports),
            games: [.init(game: game ?? self.game(), builds: [.init(fingerprint: other, reports: otherReports)])])
    }

    @Test("each strong signal alone offers medium confidence", arguments: ["header", "title", "banks"])
    func strongAlone(signal: String) throws {
        let incoming = fingerprint(hashes: [1, 2, 3, 4])
        let other = fingerprint(signal == "header" ? "MOON" : "SUN", hashes: signal == "banks" ? [1, 2, 5, 6] : [5, 6, 7, 8], cart: 9, ram: 9, cgb: 0x80)
        let candidate = try #require(match(incoming, other, filename: signal == "title" ? "Moon Garden.gb" : "build.gb").first)
        #expect(candidate.confidence == .medium)
        #expect(candidate.reasons.count == 1)
    }

    @Test("two strong signals preselect with a clear lead")
    func twoStrong() throws {
        let result = try #require(match(fingerprint(), fingerprint(cart: 9, ram: 9, cgb: 0x80)).first)
        #expect(result.confidence == .high)
        #expect(result.reasons.contains("same header title"))
        #expect(result.reasons.contains("100% of ROM banks shared"))
    }

    @Test("one strong and two supporting signals give high confidence")
    func supporting() throws {
        let candidate = try #require(match(fingerprint(), fingerprint(hashes: [5, 6, 7, 8])).first)
        #expect(candidate.confidence == .high)
    }

    @Test("uniform banks are skipped and moved banks still match")
    func movedBanks() throws {
        let a = Data(repeating: 0x11, count: 0x4000)
        let b = Data(repeating: 0x22, count: 0x4000)
        let zero = Data(repeating: 0, count: 0x4000)
        let ff = Data(repeating: 0xff, count: 0x4000)
        let rom = TestROM.make(title: "MOON", banks: [zero, a, b, ff])
        let moved = TestROM.make(title: "SUN", banks: [ff, b, a, zero])
        let left = ROMBankFingerprint.make(image: rom, sha256: "a", header: try GBROMHeaderParser.parse(rom))
        let right = ROMBankFingerprint.make(image: moved, sha256: "b", header: try GBROMHeaderParser.parse(moved))
        #expect(left.bankHashes.count == 3)
        #expect(right.bankHashes.count == 3)
        #expect(match(left, right).first?.reasons.contains("67% of ROM banks shared") == true)
    }

    @Test("generic and short header titles match nothing", arguments: ["AB", "", "DEMO", "GB Studio", "UNTITLED", "GAME", "TEST"])
    func ignoredHeaders(title: String) {
        #expect(match(fingerprint(title), fingerprint(title, hashes: [5, 6, 7, 8], cart: 9, cgb: 0x80)).isEmpty)
        #expect(match(fingerprint(title), fingerprint("OTHER", hashes: [5, 6, 7, 8], cart: 9, cgb: 0x80), game: game(title)).isEmpty)
    }

    private func report(_ family: String = "GBDK", engine: String? = nil, high: Bool = true) -> ToolchainDetectionReport {
        let evidence = (0..<(high ? 2 : 1)).map { ToolchainEvidence(signature: "signature\($0)", offset: $0) }
        var components = [DetectedToolchainComponent(kind: .toolchain, name: family, version: "1", evidence: evidence)]
        if let engine { components.append(.init(kind: .engine, name: engine, version: "1", evidence: evidence)) }
        return .init(detector: "synthetic", detectorVersion: "1", corpusRevision: "1", components: components)
    }

    @Test("banks already in two Games don't count")
    func commonBanks() {
        // Banks 1 and 2 are in both library Games, so only 3 and 4 tell projects apart.
        let incoming = fingerprint("SUN", hashes: [1, 2, 3, 4], cart: 9, ram: 9, cgb: 0x80)
        let first = fingerprint("ONE", hashes: [1, 2, 5, 6])
        let second = fingerprint("TWO", hashes: [1, 2, 7, 8])
        let result = DevelopmentBuildMatcher.match(arriving: .init(fingerprint: incoming,
            filenameMetadata: FilenameMetadataParser.parse(filename: "build.gb")),
            games: [.init(game: game("First"), builds: [.init(fingerprint: first)]),
                    .init(game: game("Second"), builds: [.init(fingerprint: second)])])
        #expect(result.isEmpty)
    }

    @Test("one engine's shared banks only support")
    func sameEngineBanks() throws {
        let engine = report("GBDK", engine: "GB Studio")
        let incoming = fingerprint("SUN", hashes: [1, 2, 3, 4])
        let other = fingerprint("STAR", hashes: [1, 2, 3, 9])
        let candidate = try #require(match(incoming, other, reports: [engine], otherReports: [engine]).first)
        #expect(candidate.confidence == .medium, "an unrelated game on the same engine is never preselected from banks")
        #expect(candidate.reasons.contains("75% of ROM banks shared"))
        // The header title still decides a real rebuild.
        let rebuild = try #require(match(incoming, fingerprint("SUN", hashes: [1, 2, 3, 9]), reports: [engine], otherReports: [engine]).first)
        #expect(rebuild.confidence == .high)
    }

    @Test("a header shared across Games is not a strong signal")
    func sharedHeader() {
        let input = fingerprint()
        let entries = (0..<2).map { i in
            DevelopmentBuildMatcher.GameSignals(game: game(i == 0 ? "MOON" : "Other"),
                builds: [.init(fingerprint: fingerprint(hashes: [5, 6, 7, 8]))])
        }
        #expect(DevelopmentBuildMatcher.match(arriving: .init(fingerprint: input,
            filenameMetadata: FilenameMetadataParser.parse(filename: "build.gb")), games: entries).isEmpty)
    }

    @Test("bank sets ignore repetition and empty fingerprints")
    func bankSets() throws {
        let repeated = try #require(match(fingerprint("NEW", hashes: [1, 1, 2, 2, 3, 3, 4, 4]),
            fingerprint("OLD", hashes: [1, 1, 2, 2, 8, 8, 9, 9], cart: 9, cgb: 0x80)).first)
        #expect(repeated.reasons == ["50% of ROM banks shared"])
        #expect(match(fingerprint("NEW", hashes: []), fingerprint("OLD", hashes: [], cart: 9, cgb: 0x80)).isEmpty)
    }

    @Test("a quarter of banks and two other supports offer medium confidence")
    func sharedQuarter() throws {
        let candidate = try #require(match(fingerprint("NEW"), fingerprint("OLD", hashes: [1, 5, 6, 7])).first)
        #expect(candidate.confidence == .medium)
        #expect(candidate.reasons.contains("25% of ROM banks shared"))
        #expect(match(fingerprint("NEW"), fingerprint("OLD", hashes: [1, 5, 6, 7], cart: 9)).isEmpty)
    }

    @Test("different high-confidence toolchains exclude even two strong signals")
    func toolConflict() {
        #expect(match(fingerprint(), fingerprint(), reports: [report()], otherReports: [report("RGBDS")]).isEmpty)
        #expect(!match(fingerprint(), fingerprint(), reports: [report(high: false)], otherReports: [report("RGBDS")]).isEmpty)
    }

    @Test("DMG-only and exclusively CGB-only Builds conflict in either direction", arguments: [false, true])
    func colorConflict(reverse: Bool) {
        #expect(match(fingerprint(cgb: reverse ? 0xc0 : 0), fingerprint(cgb: reverse ? 0 : 0xc0)).isEmpty)
    }

    @Test("a mixed-color Game does not conflict")
    func mixedColor() {
        let candidates = DevelopmentBuildMatcher.match(arriving: .init(fingerprint: fingerprint(),
            filenameMetadata: FilenameMetadataParser.parse(filename: "build.gb")), games: [
                .init(game: game(), builds: [.init(fingerprint: fingerprint(cgb: 0xc0)), .init(fingerprint: fingerprint())]),
            ])
        #expect(candidates.first?.confidence == .high)
    }

    @Test("toolchain support requires the same engine when detected")
    func engineSupport() throws {
        let incoming = fingerprint()
        let other = fingerprint(hashes: [5, 6, 7, 8], cart: 9)
        let supported = try #require(match(incoming, other, reports: [report(engine: "GB Studio")],
            otherReports: [report(engine: "GB Studio")]).first)
        #expect(supported.confidence == .high)
        #expect(supported.reasons.contains("both GBDK with GB Studio"))
        let different = try #require(match(incoming, other, reports: [report(engine: "GB Studio")],
            otherReports: [report(engine: "ZGB")]).first)
        #expect(different.confidence == .medium)
        #expect(match(incoming, other, reports: [report(engine: "GB Studio")], otherReports: [report()]).first?.confidence == .medium)
    }

    @Test("whole titles, aliases and hack bases match without prefix matching", arguments: ["Moon Garden.gb", "Lunar Garden.gb", "Moon Garden - Better [Hack].gb"])
    func titleAliases(filename: String) throws {
        let candidate = try #require(match(fingerprint("NEW"), fingerprint("OLD", hashes: [5, 6, 7, 8], cart: 9, cgb: 0x80),
            filename: filename, game: game(aliases: ["Lunar Garden"])).first)
        #expect(candidate.confidence == .medium)
        #expect(candidate.reasons == ["title or alias matches"])
        #expect(match(fingerprint("NEW"), fingerprint("OLD", hashes: [5, 6, 7, 8]), filename: "Moon Garden 2.gb").isEmpty)
    }

    @Test("a one-point lead offers ranked candidates but preselects neither")
    func closeScores() throws {
        let first = game("First")
        let second = game("Second")
        // Banks 1 and 2 are common to both Games; each shares one of its own with the arriving ROM.
        let candidates = DevelopmentBuildMatcher.match(arriving: .init(fingerprint: fingerprint("NEW"),
            filenameMetadata: FilenameMetadataParser.parse(filename: "build.gb")), games: [
                .init(game: second, builds: [.init(fingerprint: fingerprint("OLD", hashes: [1, 2, 4, 11], cart: 9))]),
                .init(game: first, builds: [.init(fingerprint: fingerprint("OLD", hashes: [1, 2, 3, 10]))]),
            ])
        #expect(candidates.map(\.gameID) == [first.id, second.id])
        #expect(candidates.allSatisfy { $0.confidence == .medium })
        #expect(candidates[0].score - candidates[1].score == DevelopmentBuildMatcher.highConfidenceMargin - 1)
    }

    @Test("equal top evidence suggests neither Game")
    func tied() {
        let candidates = DevelopmentBuildMatcher.match(arriving: .init(fingerprint: fingerprint("NEW"),
            filenameMetadata: FilenameMetadataParser.parse(filename: "build.gb")), games: [
                .init(game: game("First"), builds: [.init(fingerprint: fingerprint("OLD"))]),
                .init(game: game("Second"), builds: [.init(fingerprint: fingerprint("OLD"))]),
            ])
        #expect(candidates.isEmpty)
    }

    @Test("matching 200 Builds compares fingerprints in memory within one second")
    func performance() {
        let incoming = fingerprint("NEW", hashes: Array(0..<UInt64(128)))
        let entries = (0..<200).map { i in
            DevelopmentBuildMatcher.GameSignals(game: game("Project \(i)"),
                builds: [.init(fingerprint: fingerprint("OLD\(i)", hashes: Array(UInt64(i)..<UInt64(i + 128))))])
        }
        let started = ContinuousClock.now
        _ = DevelopmentBuildMatcher.match(arriving: .init(fingerprint: incoming,
            filenameMetadata: FilenameMetadataParser.parse(filename: "build.gb")), games: entries)
        #expect(started.duration(to: .now) < .seconds(1))
    }


    @Test("a DMG title byte in the CGB flag position still conflicts with CGB-only Builds")
    func dmgTitleByte() {
        #expect(match(fingerprint(cgb: 0x41), fingerprint(cgb: 0xc0)).isEmpty)
        #expect(match(fingerprint(cgb: 0xc0), fingerprint(cgb: 0x41)).isEmpty)
    }

    @Test("an incomplete trailing bank contributes no hash")
    func partialBank() throws {
        var image = TestROM.make(title: "MOON", payloadByte: 1)
        let header = try GBROMHeaderParser.parse(image)
        let full = ROMBankFingerprint.make(image: image, sha256: "a", header: header)
        image.append(Data(repeating: 2, count: 0x1000))
        #expect(ROMBankFingerprint.make(image: image, sha256: "b", header: header).bankHashes == full.bankHashes)
    }

}

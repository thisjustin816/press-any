import EmulatorDomain
import GameIdentity
import XCTest
@testable import Importing

/// What a matched No-Intro dump supplies as a Build's status, checked against the filename
/// parser so the same release reads the same either way.
final class KnownDumpStatusTests: XCTestCase {
    private func dump(
        _ name: String, status: String? = nil, aftermarket: Bool = false, unlicensed: Bool = false
    ) -> KnownDump {
        KnownDump(
            name: name, system: .gameBoy, title: "Example", region: "USA", status: status,
            aftermarket: aftermarket, unlicensed: unlicensed,
            files: [KnownDumpFile(sha1: "aa01", size: 1)]
        )
    }

    func testADevelopmentStatusFillsFromTheDumpAndMakesItADevelopmentBuild() {
        for status in ["Beta", "Beta 2", "Demo", "Sample", "Debug", "Alpha", "Prototype 3"] {
            let naming = FilenameMetadata(knownDump: dump("Example (USA) (\(status))", status: status), fileExtension: "gb")
            XCTAssertEqual(naming.buildMetadata.status, status)
            XCTAssertEqual(naming.releaseKind, .development, status)
            XCTAssertEqual(naming.suggestedBuildName, status, status)
        }
    }

    func testNoIntroSpellsPrototypeTheWayTheFilenameParserDoes() {
        // DAT-o-MATIC writes "Proto"; a file named "(Proto)" is a "Prototype" to the parser.
        for (written, canonical) in [("Proto", "Prototype"), ("Proto 2", "Prototype 2")] {
            let fromDump = BuildImportMetadata(knownDump: dump("Example (USA) (\(written))", status: written))
            let fromFilename = FilenameMetadataParser.parse(filename: "Example (USA) (\(written)).gb").buildMetadata
            XCTAssertEqual(fromDump.status, canonical)
            XCTAssertEqual(fromDump.status, fromFilename.status)
        }
    }

    func testStatusNoIntroWritesInItsOwnWordsStaysAsWritten() {
        for status in ["Possible Proto", "Test Program", "Web", "2021 Jam Version"] {
            XCTAssertEqual(BuildImportMetadata(knownDump: dump("Example (USA)", status: status)).status, status)
        }
    }

    func testAftermarketAndUnlicensedDescribeTheReleaseAndLeaveStatusEmpty() {
        let garden = dump("Example (USA) (Aftermarket) (Unl)", aftermarket: true, unlicensed: true)
        let naming = FilenameMetadata(knownDump: garden, fileExtension: "gb")
        XCTAssertNil(naming.buildMetadata.status)
        XCTAssertEqual(naming.releaseKind, .standard)
        XCTAssertEqual(BuildImportMetadata(knownDump: garden), BuildImportMetadata(region: "USA"))
        let fromFilename = FilenameMetadataParser.parse(filename: "Example (USA) (Aftermarket) (Unl).gb")
        XCTAssertEqual(fromFilename.buildMetadata.status, naming.buildMetadata.status)
        XCTAssertEqual(fromFilename.releaseKind, naming.releaseKind)
    }

    func testAnAftermarketPrototypeKeepsItsDevelopmentStatus() {
        let pizza = dump("Example (USA) (Proto) (Aftermarket) (Unl)", status: "Proto", aftermarket: true, unlicensed: true)
        let naming = FilenameMetadata(knownDump: pizza, fileExtension: "gb")
        XCTAssertEqual(naming.buildMetadata.status, "Prototype")
        XCTAssertEqual(naming.releaseKind, .development)
    }

    func testAPirateReleaseHasNoStatusBecauseNoIntroRecordsNone() {
        let naming = FilenameMetadata(knownDump: dump("Example (USA) (Pirate)"), fileExtension: "gb")
        XCTAssertNil(naming.buildMetadata.status)
        XCTAssertEqual(naming.releaseKind, .standard)
    }
}

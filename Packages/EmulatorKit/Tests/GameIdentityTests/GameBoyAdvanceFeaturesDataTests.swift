import EmulatorDomain
import GameIdentity
import XCTest

/// The games Automatic plays on a Game Boy Advance are listed by No-Intro release; the bundled
/// No-Intro data checks each entry and that no release of their families is missed by accident.
final class GameBoyAdvanceFeaturesDataTests: XCTestCase {
    func testEachReleaseIsAGoodGameBoyColorDumpUnderItsNoIntroName() throws {
        let index = try KnownDumpIndex.bundled()
        for release in GameBoyAdvanceFeatures.releases {
            let dump = try XCTUnwrap(index.dump(named: release.name, system: .gameBoyColor), release.name)
            XCTAssertEqual(index.dump(sha1: release.sha1), dump, release.name)
            XCTAssertEqual(index.file(sha1: release.sha1)?.bad, false, release.name)
            XCTAssertNil(dump.status, "\(release.name) is a finished release")
        }
    }

    /// A refreshed No-Intro file that adds a release to one of these families fails here until the
    /// release is listed or left out on purpose.
    func testEveryReleaseOfTheListedFamiliesIsListedOrLeftOutOnPurpose() throws {
        let index = try KnownDumpIndex.bundled()
        let listed = Set(GameBoyAdvanceFeatures.releases.map(\.name))
        var families = Set<String>()
        for release in GameBoyAdvanceFeatures.releases {
            let dump = try XCTUnwrap(index.dump(named: release.name, system: .gameBoyColor))
            for member in index.family(of: dump) {
                families.insert(member.name)
            }
        }
        // Shantae's beta, and the two images No-Intro took from its later re-release on another
        // console, which aren't cartridges.
        let leftOut = families.subtracting(listed)
        XCTAssertEqual(leftOut.count, 3, "\(leftOut.sorted())")
        XCTAssertTrue(leftOut.allSatisfy { $0.hasPrefix("Shantae (") }, "\(leftOut.sorted())")
        XCTAssertEqual(leftOut.filter { index.dump(named: $0, system: .gameBoyColor)?.status == "Beta" }.count, 1)
    }
}

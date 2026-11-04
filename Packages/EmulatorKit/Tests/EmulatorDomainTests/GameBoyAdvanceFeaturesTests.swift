import EmulatorDomain
import Foundation
import XCTest

/// The games Automatic plays on a Game Boy Advance, and the Builds that count as one of them.
/// Builds here are records only: the list matches the SHA-1 a Build stores, so no image is needed.
final class GameBoyAdvanceFeaturesTests: XCTestCase {
    private let gameID = UUID()
    private let otherSHA1 = String(repeating: "ab", count: 20)

    private func build(
        sha1: String? = nil,
        gameID: UUID? = nil,
        source: BuildSourceKind = .importedImage,
        parent: UUID? = nil,
        isBase: Bool = false,
        reference: BaseGameReference? = nil,
        title: String = "Shantae"
    ) -> Build {
        Build(
            id: UUID(), gameID: gameID ?? self.gameID, system: .gameBoyColor, displayName: title,
            imageAssetID: UUID(), imageSHA256: UUID().uuidString, imageSHA1: sha1, sourceKind: source,
            parentBuildID: parent, isBase: isBase, baseGameReference: reference, baseTitle: title,
            createdAt: .distantPast, modifiedAt: .distantPast
        )
    }

    private func includes(_ build: Build, among builds: [Build] = []) -> Bool {
        let all = builds + [build]
        return GameBoyAdvanceFeatures.includes(
            build,
            lookup: { id in all.first { $0.id == id } },
            gameBuilds: { id in all.filter { $0.gameID == id } }
        )
    }

    func testTheListIsEveryCartridgeReleaseOfTheFourGames() {
        let names = GameBoyAdvanceFeatures.releases.map(\.name)
        XCTAssertEqual(names.count, 9)
        XCTAssertEqual(Set(names).count, 9)
        XCTAssertEqual(Set(GameBoyAdvanceFeatures.releases.map(\.sha1)).count, 9)
        XCTAssertEqual(names.filter { $0.hasPrefix("Wendy - Every Witch Way") }.count, 1)
        XCTAssertEqual(names.filter { $0.hasPrefix("Shantae") }.count, 2)
        XCTAssertEqual(names.filter { $0.contains("Oracle of Seasons") || $0.contains("Daichi no Shou") }.count, 3)
        XCTAssertEqual(names.filter { $0.contains("Oracle of Ages") || $0.contains("Jikuu no Shou") }.count, 3)
        for release in GameBoyAdvanceFeatures.releases {
            XCTAssertEqual(release.sha1, release.sha1.lowercased())
            XCTAssertEqual(release.sha1.count, 40)
            XCTAssertTrue(GameBoyAdvanceFeatures.lists(sha1: release.sha1.uppercased()), release.name)
            XCTAssertTrue(includes(build(sha1: release.sha1)), release.name)
        }
        XCTAssertEqual(names.filter { $0.hasPrefix("Shantae") }, ["Shantae (USA)", "Shantae (World) (Limited Run Games)"], "only cartridges")
    }

    /// A homebrew or hack with the same title, header and Game name ties to nothing listed.
    func testTheSameTitleWithoutLineageIsNotListed() {
        XCTAssertFalse(includes(build(sha1: otherSHA1)))
        XCTAssertFalse(includes(build()), "no SHA-1 yet")
        let byTitle = BaseGameReference(title: "Shantae", system: .gameBoyColor)
        XCTAssertFalse(includes(build(sha1: otherSHA1, reference: byTitle)), "a title the player typed names no release")
        let family = BaseGameReference(title: "Shantae", system: .gameBoyColor, familyName: "Shantae (USA)")
        XCTAssertFalse(includes(build(sha1: otherSHA1, reference: family)), "a family alone names no release")
    }

    func testAPatchedBuildFollowsItsPatchesBackToAListedRelease() throws {
        let release = try XCTUnwrap(GameBoyAdvanceFeatures.releases.first { $0.name.contains("Oracle of Ages (USA") })
        let base = build(sha1: release.sha1)
        // Patched Builds have no SHA-1 of their own.
        let first = build(source: .patchRecipe, parent: base.id)
        let second = build(source: .patchRecipe, parent: first.id)
        XCTAssertTrue(includes(first, among: [base]))
        XCTAssertTrue(includes(second, among: [base, first]))
        XCTAssertFalse(includes(second, among: [first]), "the chain ends at a missing Build")

        let unlisted = build(sha1: otherSHA1)
        XCTAssertFalse(includes(build(source: .patchRecipe, parent: unlisted.id), among: [unlisted]))
        // An imported Build's parent isn't a patch source, so the chain stops there.
        XCTAssertFalse(includes(build(sha1: otherSHA1, parent: base.id), among: [base]))
    }

    func testABuildInAGameWhoseBaseIsListedIsListed() throws {
        let release = try XCTUnwrap(GameBoyAdvanceFeatures.releases.first { $0.name.hasPrefix("Wendy") })
        let base = build(sha1: release.sha1, isBase: true)
        XCTAssertTrue(includes(build(sha1: otherSHA1), among: [base]))
        XCTAssertFalse(includes(build(sha1: otherSHA1, gameID: UUID()), among: [base]), "another Game's Base")

        // A Base patched from a listed release counts, as does one identified as patched from one.
        let source = build(sha1: release.sha1, gameID: UUID())
        let patchedBase = build(source: .patchRecipe, parent: source.id, isBase: true)
        XCTAssertTrue(includes(build(sha1: otherSHA1), among: [source, patchedBase]))

        // A patch made from a Build that counts through its Game's Base counts too.
        let sibling = build(sha1: otherSHA1)
        XCTAssertTrue(includes(build(gameID: UUID(), source: .patchRecipe, parent: sibling.id), among: [base, sibling]))

        // Only the Base speaks for the Game: a listed Build that isn't the Base doesn't.
        let listedSibling = build(sha1: release.sha1)
        let unlistedBase = build(sha1: otherSHA1, isBase: true)
        XCTAssertFalse(includes(build(sha1: otherSHA1), among: [listedSibling, unlistedBase]))
    }

    /// An imported hack whose base game the player matched to a No-Intro release.
    func testAnImportedHackIdentifiedAsPatchedFromAListedReleaseIsListed() {
        func reference(_ name: String, system: GameSystem = .gameBoyColor) -> BaseGameReference {
            BaseGameReference(title: "Title", system: system, familyName: name, releaseName: name)
        }
        XCTAssertTrue(includes(build(sha1: otherSHA1, reference: reference("Shantae (USA)"))))
        XCTAssertTrue(includes(build(sha1: otherSHA1, reference: reference("Zelda no Densetsu - Fushigi no Kinomi - Daichi no Shou (Japan)"))))
        XCTAssertFalse(includes(build(sha1: otherSHA1, reference: reference("Shantae (USA)", system: .gameBoy))), "another system's release")
        XCTAssertFalse(includes(build(sha1: otherSHA1, reference: reference("Shantae (USA) (Beta)"))), "an unlisted release")
        XCTAssertFalse(includes(build(sha1: otherSHA1, reference: reference("Homebrew (World) (Aftermarket) (Unl)"))))
    }

    func testACycleOfPatchesEnds() {
        var first = build(source: .patchRecipe)
        let second = build(source: .patchRecipe, parent: first.id)
        first = Build(
            id: first.id, gameID: gameID, system: .gameBoyColor, displayName: "Loop", imageAssetID: UUID(),
            imageSHA256: "x", sourceKind: .patchRecipe, parentBuildID: second.id,
            createdAt: .distantPast, modifiedAt: .distantPast
        )
        XCTAssertFalse(includes(first, among: [second]))
    }
}

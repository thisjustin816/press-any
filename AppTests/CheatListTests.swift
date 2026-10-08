import EmulatorApplication
import EmulatorDomain
import Foundation
import XCTest
@testable import PressAny

/// The cheat list checks codes with SameBoy, the core that plays these Builds.
@MainActor
final class CheatListTests: XCTestCase {
    func testABadLineSavesNothingAndIsNamed() throws {
        let fixture = try CheatListFixture()
        defer { fixture.remove() }
        let model = fixture.model()
        model.reload()
        model.startAdding()
        model.nameDraft = "Moon Garden Lives"
        model.codesDraft = "014200C0\n\nNOT-A-CODE\n990-00B"
        model.saveDraft()
        XCTAssertTrue(model.isEditing, "the sheet stays open")
        XCTAssertEqual(model.draftError, "Line 3 isn’t a Game Genie or GameShark code.")
        XCTAssertTrue(model.cheats.isEmpty)
        XCTAssertTrue(try fixture.container.buildCheats.cheats(buildID: fixture.build.id).isEmpty)
        XCTAssertEqual(fixture.changes, 0)

        model.nameDraft = "  "
        model.codesDraft = "014200C0"
        model.saveDraft()
        XCTAssertEqual(model.draftError, BuildCheatError.missingName.localizedDescription)
        XCTAssertTrue(model.cheats.isEmpty)

        model.nameDraft = "Moon Garden Lives"
        model.codesDraft = "014200c0\n 990-00B "
        model.saveDraft()
        XCTAssertFalse(model.isEditing)
        XCTAssertNil(model.draftError)
        XCTAssertEqual(model.cheats.map(\.codes), [["014200C0", "990-00B"]])
        XCTAssertEqual(fixture.changes, 1)
    }

    func testEditingTogglingReorderingAndDeletingSaveAndApplyAtOnce() throws {
        let fixture = try CheatListFixture()
        defer { fixture.remove() }
        let model = fixture.model()
        model.reload()
        for (name, code) in [("Lives", "014200C0"), ("Jump", "010100C1"), ("Time", "990-00B")] {
            model.startAdding()
            model.nameDraft = name
            model.codesDraft = code
            model.saveDraft()
        }
        XCTAssertEqual(model.cheats.map(\.name), ["Lives", "Jump", "Time"])
        XCTAssertEqual(fixture.changes, 3)

        let jump = model.cheats[1]
        model.startEditing(jump)
        XCTAssertEqual(model.nameDraft, "Jump")
        XCTAssertEqual(model.codesDraft, "010100C1")
        model.codesDraft = "010100C1\nBAD"
        model.saveDraft()
        XCTAssertEqual(model.draftError, "Line 2 isn’t a Game Genie or GameShark code.")
        XCTAssertEqual(model.cheats[1].codes, ["010100C1"])
        model.nameDraft = "Moon Jump"
        model.codesDraft = "010100C1\n010200C2"
        model.saveDraft()
        XCTAssertEqual(model.cheats[1].name, "Moon Jump")
        XCTAssertEqual(model.cheats[1].codes, ["010100C1", "010200C2"])
        XCTAssertEqual(model.cheats[1].id, jump.id)

        model.setEnabled(model.cheats[0], false)
        XCTAssertEqual(model.cheats.map(\.isEnabled), [false, true, true])

        model.reorder([model.cheats[2].id, model.cheats[0].id, model.cheats[1].id])
        XCTAssertEqual(model.cheats.map(\.name), ["Time", "Lives", "Moon Jump"])

        let lives = model.cheats[1]
        model.requestDeletion(of: lives)
        XCTAssertEqual(model.pendingDeletion, lives)
        model.confirmDeletion(of: lives)
        XCTAssertNil(model.pendingDeletion)
        XCTAssertEqual(model.cheats.map(\.name), ["Time", "Moon Jump"])
        XCTAssertEqual(model.cheats.map(\.position), [0, 1])
        XCTAssertEqual(fixture.changes, 7)

        let reopened = try AppContainer(rootURL: fixture.root)
        XCTAssertEqual(try reopened.buildCheats.cheats(buildID: fixture.build.id).map(\.name), ["Time", "Moon Jump"])
    }

    func testTheCheatsOnSwitchSavesAndApplies() throws {
        let fixture = try CheatListFixture()
        defer { fixture.remove() }
        let model = fixture.model()
        model.reload()
        XCTAssertTrue(model.cheatsEnabled)
        model.setCheatsEnabled(false)
        XCTAssertFalse(model.cheatsEnabled)
        XCTAssertEqual(fixture.changes, 1)
        XCTAssertEqual(try fixture.container.repositories.builds.fetchBuild(id: fixture.build.id)?.cheatsEnabled, false)
        model.setCheatsEnabled(true)
        XCTAssertTrue(model.cheatsEnabled)
        XCTAssertEqual(fixture.changes, 2)
    }

    func testAChangeTheGameCantApplyIsStillSavedAndReported() throws {
        let fixture = try CheatListFixture()
        defer { fixture.remove() }
        struct Unavailable: LocalizedError { var errorDescription: String? { "No game is running." } }
        let model = CheatListViewModel(buildID: fixture.build.id, builds: fixture.container.repositories.builds,
            operations: fixture.container.buildCheats, isValid: fixture.container.cheatCodeChecker(buildID: fixture.build.id),
            onChange: { throw Unavailable() })
        model.setCheatsEnabled(false)
        XCTAssertFalse(model.cheatsEnabled)
        XCTAssertEqual(model.errorMessage, "The change was saved, but the game couldn’t apply it: No game is running.")
    }

    func testTheCoreChecksCodesForTheBuild() throws {
        let fixture = try CheatListFixture()
        defer { fixture.remove() }
        let isValid = fixture.container.cheatCodeChecker(buildID: fixture.build.id)
        XCTAssertTrue(isValid("014200C0"))
        XCTAssertTrue(isValid("990-00B-EFA"))
        XCTAssertFalse(isValid("123-456"))
        XCTAssertFalse(isValid("NOT-A-CODE"))
        XCTAssertFalse(fixture.container.cheatCodeChecker(buildID: UUID())("014200C0"), "an unknown Build reads nothing")
    }
}

@MainActor
private final class CheatListFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let container: AppContainer
    let build: Build
    private(set) var changes = 0

    init() throws {
        container = try AppContainer(rootURL: root)
        let file = root.appendingPathComponent("Moon Garden.gb")
        try Data(repeating: 0, count: 0x8000).write(to: file)
        let coordinator = ImportCoordinator(analyzer: container.importAnalyzer, committer: container.importCommitter,
            assetStore: container.fileStore)
        let review = ImportReviewViewModel(analysis: try coordinator.analyzeROM(at: file), games: [], coordinator: coordinator)
        build = try review.commit().build
    }

    func model() -> CheatListViewModel {
        CheatListViewModel(buildID: build.id, builds: container.repositories.builds, operations: container.buildCheats,
            isValid: container.cheatCodeChecker(buildID: build.id), onChange: { [weak self] in self?.changes += 1 })
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

import EmulatorDomain
import Importing
import XCTest

final class SaveFileMatcherTests: XCTestCase {
    private func game(_ title: String) -> Game {
        Game(id: UUID(), primaryTitle: title, systemFamily: "gb", createdAt: .now, modifiedAt: .now)
    }

    func testASaveNamedLikeAROMFilePicksThatROMsGame() {
        let moleMania = game("Mole Mania")
        let match = SaveFileMatcher.matchingGameID(
            forSaveNamed: "Mole_Mania_USA_Europe_SGB_Enhanced.srm",
            games: [moleMania, game("Tetris")],
            romFilenames: [(moleMania.id, "Mole_Mania_USA_Europe_SGB_Enhanced.gb")]
        )
        XCTAssertEqual(match, moleMania.id)
    }

    func testOtherwiseTheSavesTitleMatchesAGame() {
        let moleMania = game("Mole Mania")
        let match = SaveFileMatcher.matchingGameID(
            forSaveNamed: "Mole Mania (USA, Europe) (SGB Enhanced).sav",
            games: [moleMania, game("Tetris")],
            romFilenames: []
        )
        XCTAssertEqual(match, moleMania.id)
    }

    func testAROMFilenameInTwoGamesMatchesNeither() {
        let first = game("Mole Mania")
        let second = game("Mole Mania DX")
        let match = SaveFileMatcher.matchingGameID(
            forSaveNamed: "Mole Mania.sav",
            games: [first, second],
            romFilenames: [(first.id, "Mole Mania.gb"), (second.id, "Mole Mania.gbc")]
        )
        XCTAssertNil(match)
    }
}

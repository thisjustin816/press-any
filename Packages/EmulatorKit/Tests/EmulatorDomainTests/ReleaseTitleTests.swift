import EmulatorDomain
import XCTest

final class ReleaseTitleTests: XCTestCase {
    func testSharedTitleSelectionRanksRegionsAndLanguagesAndKeepsStableTies() {
        let japan = ReleaseTitle(title: "Japan title", region: "Japan", language: "Ja")
        let french = ReleaseTitle(title: "French title", region: "Europe", language: "Fr")
        let english = ReleaseTitle(title: "English title", region: "Europe", language: "En")
        let usa = ReleaseTitle(title: "USA title", region: "USA, Europe", language: "En")
        let preference = ReleasePreference()
        XCTAssertNil(preference.preferredTitle(among: [], currentTitle: "Homebrew"))
        XCTAssertEqual(preference.preferredTitle(among: [japan, french, english, usa], currentTitle: japan.title), usa)
        XCTAssertEqual(preference.preferredTitle(among: [japan, french, english], currentTitle: french.title), english)
        let tied = ReleaseTitle(title: "Another title", region: "USA", language: "En")
        let lowerCurrent = ReleaseTitle(title: tied.title, region: "Japan", language: "Ja")
        XCTAssertEqual(preference.preferredTitle(among: [lowerCurrent, usa, tied], currentTitle: tied.title), tied)
        XCTAssertEqual(preference.preferredTitle(among: [usa, tied], currentTitle: tied.title), tied)
        XCTAssertEqual(preference.preferredTitle(among: [usa, tied], currentTitle: "Other"), usa)
    }
}

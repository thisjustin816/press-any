import EmulatorApplication
import EmulatorDomain
import Importing
import XCTest
@testable import PressAny

@MainActor
final class ColorDisplaySettingsTests: XCTestCase {
    func testLaunchAndOpenGameResolveInheritedColorsAndDefaults() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try AppContainer(rootURL: root)
        let file = root.appendingPathComponent("Colors.gb")
        try Data(repeating: 0, count: 0x8000).write(to: file)
        let analysis = try container.importAnalyzer.analyzeROM(at: file, targetGameID: nil)
        let result = try container.importCommitter.commit(ROMImportPlan(
            analysis: analysis, disposition: .createGame(title: "Colors"),
            buildDisplayName: "Original", markAsBase: true
        ))
        let context = LaunchContext(gameID: result.build.gameID, buildID: result.build.id, saveProfileID: UUID())
        let target = try XCTUnwrap(container.gameplaySettingsTarget(for: context))
        XCTAssertEqual(container.colorCorrection(for: context), .balanced)
        XCTAssertEqual(container.dmgPalette(for: context), .dmgGreen)
        XCTAssertEqual(container.colorCorrection(system: .gameBoyColor), .balanced)
        XCTAssertEqual(container.dmgPalette(system: .gameBoy), .dmgGreen)
        let store = container.repositories.settings
        let correctionKey = SettingKey.colorCorrection.rawValue
        let paletteKey = SettingKey.dmgPalette.rawValue
        let scopes: [SettingsScope] = [.app, .system(.gameBoy), .game(context.gameID), .build(context.buildID)]
        let corrections: [ColorCorrection] = [.off, .accurate, .boostContrast, .lowContrast]
        let palettes: [DMGPalette] = [.cgbUpA, .cgbDownB, .cgbLeftA, .cgbRightB]
        for index in scopes.indices {
            try store.set(corrections[index], key: correctionKey, scope: scopes[index])
            try store.set(palettes[index], key: paletteKey, scope: scopes[index])
            XCTAssertEqual(container.colorCorrection(for: context), corrections[index])
            XCTAssertEqual(container.dmgPalette(for: context), palettes[index])
            let display = container.gameplayDisplay(for: target)
            XCTAssertEqual(display.colorCorrection, corrections[index])
            XCTAssertEqual(display.dmgPalette, palettes[index])
        }
        XCTAssertEqual(container.colorCorrection(system: .gameBoy), .accurate)
        XCTAssertEqual(container.dmgPalette(system: .gameBoy), .cgbDownB)
        XCTAssertEqual(container.colorCorrection(system: .gameBoyColor), .off)
        XCTAssertEqual(container.dmgPalette(system: .gameBoyColor), .cgbUpA)
        let reopened = try AppContainer(rootURL: root)
        XCTAssertEqual(reopened.colorCorrection(for: context), .lowContrast)
        XCTAssertEqual(reopened.dmgPalette(for: context), .cgbRightB)
        for scope in scopes.reversed() {
            try store.removeValue(key: correctionKey, scope: scope)
            try store.removeValue(key: paletteKey, scope: scope)
        }
        XCTAssertEqual(container.colorCorrection(for: context), .balanced)
        XCTAssertEqual(container.dmgPalette(for: context), .dmgGreen)
        try store.setValueJSON("\"unknown\"", key: correctionKey, scope: .build(context.buildID))
        try store.setValueJSON("\"unknown\"", key: paletteKey, scope: .build(context.buildID))
        XCTAssertEqual(container.colorCorrection(for: context), .balanced)
        XCTAssertEqual(container.dmgPalette(for: context), .dmgGreen)
    }

    func testScreenColorsPickerOffersBootPalettesOnlyForOriginalGamesWithoutPlus() throws {
        let store = InMemorySettingsStore()
        for system in [GameSystem.gameBoy, .gameBoyColor] {
            let view = ScopedSettingsView(
                title: "Settings", scope: .system(system), system: system,
                gameID: nil, buildID: nil, store: store, plus: .fixed(ownsPlus: false)
            )
            switch view.screenColorChoices {
            case .dmg(let choices):
                XCTAssertEqual(system, .gameBoy)
                XCTAssertEqual(Array(choices.prefix(4)), [.dmgGreen, .pocket, .light, .grey])
                XCTAssertEqual(choices.dropFirst(4).map(\.displayName), [
                    "Up", "Up + A", "Up + B", "Down", "Down + A", "Down + B",
                    "Left", "Left + A", "Left + B", "Right", "Right + A", "Right + B",
                ])
            case .correction(let choices):
                XCTAssertEqual(system, .gameBoyColor)
                XCTAssertEqual(choices, [.balanced, .accurate, .boostContrast, .reduceContrast, .lowContrast, .off])
            }
        }
    }
}

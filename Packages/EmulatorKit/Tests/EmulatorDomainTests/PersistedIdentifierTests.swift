import EmulatorDomain
import XCTest

/// The database stores these raw values, so renaming a case must not change them.
final class PersistedIdentifierTests: XCTestCase {
    func testToolchainComponentKindRawValuesAreStable() {
        // Stored inside each Build's toolchain report JSON.
        XCTAssertEqual(
            [ToolchainComponentKind.toolchain, .engine, .musicDriver, .soundEffectsDriver].map(\.rawValue),
            ["toolchain", "engine", "musicDriver", "soundEffectsDriver"]
        )
    }

    func testManagedAssetKindRawValuesAreStable() {
        XCTAssertEqual(ManagedAssetKind.sourceImage.rawValue, "sourceROM")
        XCTAssertEqual(ManagedAssetKind.sourcePatch.rawValue, "sourcePatch")
        XCTAssertEqual(ManagedAssetKind.generatedImage.rawValue, "generatedROM")
        XCTAssertEqual(ManagedAssetKind.persistentSave.rawValue, "batterySave")
        XCTAssertEqual(ManagedAssetKind.saveState.rawValue, "saveState")
        XCTAssertEqual(ManagedAssetKind.stateThumbnail.rawValue, "stateThumbnail")
        XCTAssertEqual(ManagedAssetKind.quickPlayImage.rawValue, "quickPlayROM")
        XCTAssertEqual(ManagedAssetKind.artwork.rawValue, "artwork")
    }

    func testSettingKeysAreStable() {
        XCTAssertEqual(SettingKey.skipBootAnimation.rawValue, "skipBootAnimation")
        XCTAssertEqual(SettingKey.autoResumePolicy.rawValue, "autoResumePolicy")
        XCTAssertEqual(SettingKey.controllerLayout.rawValue, "controllerLayout")
        XCTAssertEqual(SettingKey.soundMode.rawValue, "soundMode")
        XCTAssertEqual(SettingKey.controllerTheme.rawValue, "controllerTheme")
        XCTAssertEqual(SettingKey.tapGameForMenu.rawValue, "tapGameForMenu")
        XCTAssertEqual(SettingKey.screenScaling.rawValue, "screenScaling")
    }

    func testSettingValuesAreStable() {
        XCTAssertEqual(AutoResumePolicy.allCases.map(\.rawValue), ["always", "ask", "never"])
        XCTAssertEqual(SoundMode.allCases.map(\.rawValue), ["followSilentSwitch", "alwaysOn", "alwaysOff"])
    }

    func testBuildSourceKindRawValuesAreStable() {
        XCTAssertEqual(BuildSourceKind.importedImage.rawValue, "importedROM")
        XCTAssertEqual(BuildSourceKind.patchRecipe.rawValue, "patchRecipe")
    }
}

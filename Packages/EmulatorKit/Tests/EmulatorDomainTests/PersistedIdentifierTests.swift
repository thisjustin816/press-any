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

    func testVariableMapRawValuesAreStable() {
        XCTAssertEqual(BuildVariableMap.Format.gbStudioGlobals.rawValue, "gbStudioGlobals")
        XCTAssertEqual(BuildVariableMap.Format.symbolFile.rawValue, "symbolFile")
        XCTAssertEqual(BuildVariableMap.Source.userImport.rawValue, "userImport")
        XCTAssertEqual(ManagedAssetKind.variableMap.rawValue, "variableMap")
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
        XCTAssertEqual(SettingKey.hideTouchControlsWithController.rawValue, "hideTouchControlsWithController")
        XCTAssertEqual(SettingKey.touchHaptics.rawValue, "touchHaptics")
        XCTAssertEqual(SettingKey.screenScaling.rawValue, "screenScaling")
        XCTAssertEqual(SettingKey.lcdFilter.rawValue, "lcdFilter")
        XCTAssertEqual(SettingKey.frameBlending.rawValue, "frameBlending")
        XCTAssertEqual(SettingKey.fastForwardSpeed.rawValue, "fastForwardSpeed")
    }

    func testSettingValuesAreStable() {
        XCTAssertEqual(AutoResumePolicy.allCases.map(\.rawValue), ["always", "ask", "never"])
        XCTAssertEqual(SoundMode.allCases.map(\.rawValue), ["followSilentSwitch", "alwaysOn", "alwaysOff"])
        XCTAssertEqual(TouchHaptics.allCases.map(\.rawValue), ["off", "light", "medium"])
        XCTAssertEqual(LCDFilter.allCases.map(\.rawValue), ["off", "lcd1x", "lcd3x"])
        XCTAssertEqual(FastForwardSpeed.allCases.map(\.rawValue), ["x1_5", "x2", "x3", "x4", "x8", "unlimited"])
        XCTAssertEqual(FastForwardSpeed.allCases.map(\.multiplier), [1.5, 2, 3, 4, 8, nil])
        XCTAssertEqual(FrameBlending.allCases.map(\.rawValue), ["off", "blend", "ghosting"])
    }

    func testBuildSourceKindRawValuesAreStable() {
        XCTAssertEqual(BuildSourceKind.importedImage.rawValue, "importedROM")
        XCTAssertEqual(BuildSourceKind.patchRecipe.rawValue, "patchRecipe")
    }
}

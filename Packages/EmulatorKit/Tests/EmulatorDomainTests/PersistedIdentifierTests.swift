import EmulatorDomain
import XCTest

/// The database stores these raw values, so renaming a case must not change them.
final class PersistedIdentifierTests: XCTestCase {
    func testManagedAssetKindRawValuesAreStable() {
        XCTAssertEqual(ManagedAssetKind.sourceImage.rawValue, "sourceROM")
        XCTAssertEqual(ManagedAssetKind.sourcePatch.rawValue, "sourcePatch")
        XCTAssertEqual(ManagedAssetKind.generatedImage.rawValue, "generatedROM")
        XCTAssertEqual(ManagedAssetKind.persistentSave.rawValue, "batterySave")
        XCTAssertEqual(ManagedAssetKind.saveState.rawValue, "saveState")
        XCTAssertEqual(ManagedAssetKind.stateThumbnail.rawValue, "stateThumbnail")
        XCTAssertEqual(ManagedAssetKind.quickPlayImage.rawValue, "quickPlayROM")
    }

    func testSettingKeysAreStable() {
        XCTAssertEqual(SettingKey.skipBootAnimation.rawValue, "skipBootAnimation")
    }

    func testBuildSourceKindRawValuesAreStable() {
        XCTAssertEqual(BuildSourceKind.importedImage.rawValue, "importedROM")
        XCTAssertEqual(BuildSourceKind.patchRecipe.rawValue, "patchRecipe")
    }
}

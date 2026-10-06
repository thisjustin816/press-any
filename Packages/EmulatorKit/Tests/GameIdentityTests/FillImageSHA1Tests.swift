import AssetStorage
import EmulatorDomain
import EmulatorKitTestSupport
import Foundation
import GameIdentity
import XCTest

final class FillImageSHA1Tests: XCTestCase {
    func testImportedBuildsGainTheirSHA1AndOthersAreLeftAlone() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FillSHA1-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try ManagedFileStore(rootURL: root)
        let created = Date(timeIntervalSince1970: 0)

        func imported(_ bytes: Data, onDisk: Bool) throws -> Build {
            let sha256 = store.hashData(bytes)
            if onDisk {
                let staged = root.appendingPathComponent("\(UUID()).gb")
                try bytes.write(to: staged)
                _ = try store.commitSourceROM(stagedURL: staged, sha256: sha256)
            }
            return Build(
                id: UUID(), gameID: UUID(), system: .gameBoy, displayName: "Build", imageAssetID: UUID(),
                imageSHA256: sha256, sourceKind: .importedImage, createdAt: created, modifiedAt: created
            )
        }
        let present = try imported(Data([1, 2, 3]), onDisk: true)
        let missing = try imported(Data([4, 5, 6]), onDisk: false)
        let alreadyFilled = Build(
            id: UUID(), gameID: UUID(), system: .gameBoy, displayName: "Filled", imageAssetID: UUID(),
            imageSHA256: String(repeating: "f", count: 64), imageSHA1: String(repeating: "a", count: 40),
            sourceKind: .importedImage, createdAt: created, modifiedAt: created
        )
        let patched = Build(
            id: UUID(), gameID: UUID(), system: .gameBoy, displayName: "Patched", imageAssetID: UUID(),
            imageSHA256: String(repeating: "e", count: 64), sourceKind: .patchRecipe, parentBuildID: present.id,
            createdAt: created, modifiedAt: created
        )
        let builds = InMemoryBuildRepository([present, missing, alreadyFilled, patched])

        let filled = try FillImageSHA1(builds: builds, assetStore: store).execute()

        XCTAssertEqual(filled, 1)
        XCTAssertEqual(try builds.fetchBuild(id: present.id)?.imageSHA1, SHA1Digest.data(Data([1, 2, 3])))
        XCTAssertNil(try builds.fetchBuild(id: missing.id)?.imageSHA1, "a missing file is tried again next launch")
        XCTAssertEqual(try builds.fetchBuild(id: alreadyFilled.id)?.imageSHA1, alreadyFilled.imageSHA1)
        XCTAssertNil(try builds.fetchBuild(id: patched.id)?.imageSHA1)
        XCTAssertEqual(try FillImageSHA1(builds: builds, assetStore: store).execute(), 0, "a second run finds only the missing file")
    }
}

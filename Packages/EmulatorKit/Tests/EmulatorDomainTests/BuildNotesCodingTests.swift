import EmulatorDomain
import Foundation
import XCTest

final class BuildNotesCodingTests: XCTestCase {
    func testNotesAndPlaytimeRoundTripAndOlderBuildsDecodeWithDefaults() throws {
        let build = Build(
            id: UUID(), gameID: UUID(), system: .gameBoy, displayName: "Test",
            imageAssetID: UUID(), imageSHA256: String(repeating: "a", count: 64), sourceKind: .importedImage,
            notes: "Test route\n# Plain text", totalPlaytimeSeconds: 12.5, createdAt: .now, modifiedAt: .now
        )
        let data = try JSONEncoder().encode(build)
        XCTAssertEqual(try JSONDecoder().decode(Build.self, from: data), build)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "notes")
        legacy.removeValue(forKey: "totalPlaytimeSeconds")
        let decoded = try JSONDecoder().decode(Build.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(decoded.notes, "")
        XCTAssertEqual(decoded.totalPlaytimeSeconds, 0)
        XCTAssertEqual(decoded.imageSHA256, build.imageSHA256)
    }
}

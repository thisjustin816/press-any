import EmulatorDomain
import Foundation
import XCTest
@testable import QuickPlay

/// session.json outlives the code that wrote it, so its keys must not follow Swift renames.
final class QuickPlaySessionCodingTests: XCTestCase {
    private let session = QuickPlaySession(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        imageSHA256: String(repeating: "a", count: 64),
        originalFilename: "game.gb",
        system: .gameBoy,
        rootURL: URL(fileURLWithPath: "/tmp/quickplay/1"),
        startedAt: Date(timeIntervalSince1970: 0),
        expiresAt: Date(timeIntervalSince1970: 86_400),
        sourceSaveProfileID: nil
    )

    func testEncodedKeysAreStable() throws {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(session))
        let keys = try XCTUnwrap(object as? [String: Any]).keys
        XCTAssertEqual(Set(keys), [
            "id", "romSHA256", "originalFilename", "system", "rootURL", "startedAt", "expiresAt",
        ])
    }

    func testDecodesSessionWrittenWithStoredKeys() throws {
        let stored = try JSONEncoder().encode(session)
        XCTAssertEqual(try JSONDecoder().decode(QuickPlaySession.self, from: stored), session)

        let json = #"{"id":"00000000-0000-0000-0000-000000000002","romSHA256":"\#(String(repeating: "b", count: 64))","originalFilename":"old.gbc","system":"gbc","rootURL":"file:///tmp/quickplay/2","startedAt":0,"expiresAt":86400}"#
        let decoded = try JSONDecoder().decode(QuickPlaySession.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.imageSHA256, String(repeating: "b", count: 64))
        XCTAssertEqual(decoded.system, .gameBoyColor)
    }
}

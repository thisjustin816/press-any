import EmulatorDomain
import Foundation
import Testing

@Suite("Patch recipe item coding")
struct PatchRecipeItemCodingTests {
    @Test("a recorded input hash survives Codable")
    func roundTrip() throws {
        let item = PatchRecipeItem(position: 1, patchAssetID: UUID(), expectedInputSHA256: String(repeating: "a", count: 64))
        #expect(try JSONDecoder().decode(PatchRecipeItem.self, from: JSONEncoder().encode(item)) == item)
    }

    @Test("disabled items discard a supplied input hash")
    func disabledItem() {
        let item = PatchRecipeItem(position: 0, patchAssetID: UUID(), enabled: false, expectedInputSHA256: "unused")
        #expect(item.expectedInputSHA256 == nil)
    }

    @Test("items encoded without an input hash decode as not recorded")
    func legacyItem() throws {
        let id = UUID()
        let json = Data("""
        {"position":0,"patchAssetID":"\(id.uuidString)","enabled":true,"ignoresBaseMismatch":false}
        """.utf8)
        let item = try JSONDecoder().decode(PatchRecipeItem.self, from: json)
        #expect(item.expectedInputSHA256 == nil)
        #expect(item.patchAssetID == id)
    }
}

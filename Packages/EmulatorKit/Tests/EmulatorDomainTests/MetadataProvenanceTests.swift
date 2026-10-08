import EmulatorDomain
import Foundation
import Testing

@Suite("Metadata provenance")
struct MetadataProvenanceTests {
    @Test("player corrections retain the value offered by the source")
    func playerCorrection() {
        let offered = MetadataProvenance(field: .title, source: .filename, confidence: .medium,
            providedValue: "Offered", recordedAt: Date(timeIntervalSince1970: 100))
        let corrected = offered.playerOverride(recordedAt: Date(timeIntervalSince1970: 200))
        #expect(corrected.source == .player)
        #expect(corrected.confidence == nil)
        #expect(corrected.providedValue == "Offered")
        #expect(corrected.recordedAt == Date(timeIntervalSince1970: 200))
    }
}

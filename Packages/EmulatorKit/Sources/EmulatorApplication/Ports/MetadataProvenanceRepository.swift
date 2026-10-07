import EmulatorDomain
import Foundation

/// Owner-scoped provenance. Game and Build repositories use their respective tables.
public protocol MetadataProvenanceRepository: Sendable {
    /// Recently Deleted owners are hidden. An empty result means provenance was not recorded.
    func fetchMetadataProvenance(ownerID: UUID) throws -> [MetadataProvenance]
    func saveMetadataProvenance(_ provenance: MetadataProvenance, ownerID: UUID) throws
}

extension MetadataProvenanceRepository {
    public func recordPlayerOverride(field: MetadataField, value: String?, ownerID: UUID, at date: Date) throws {
        let previous = try fetchMetadataProvenance(ownerID: ownerID).first { $0.field == field }
        try saveMetadataProvenance(
            previous?.playerOverride(recordedAt: date)
                ?? MetadataProvenance(field: field, source: .player, providedValue: value, recordedAt: date),
            ownerID: ownerID
        )
    }
}

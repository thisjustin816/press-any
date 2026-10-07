import EmulatorApplication
import EmulatorDomain
import Foundation
import GRDB

extension GRDBGameRepository {
    public func fetchMetadataProvenance(ownerID: UUID) throws -> [MetadataProvenance] {
        try read { try MetadataProvenanceSQL.fetch(ownerID: ownerID, ownerTable: "games", db: $0) }
    }

    public func saveMetadataProvenance(_ provenance: MetadataProvenance, ownerID: UUID) throws {
        try write { db in
            try MetadataProvenanceSQL.save(provenance, ownerID: ownerID, ownerTable: "games", db: db)
            try db.execute(sql: "UPDATE games SET has_player_title = ? WHERE id = ?",
                arguments: [provenance.source == .player, PersistenceCodec.uuid(ownerID)])
        }
    }
}

extension GRDBBuildRepository {
    public func fetchMetadataProvenance(ownerID: UUID) throws -> [MetadataProvenance] {
        try read { try MetadataProvenanceSQL.fetch(ownerID: ownerID, ownerTable: "builds", db: $0) }
    }

    public func saveMetadataProvenance(_ provenance: MetadataProvenance, ownerID: UUID) throws {
        try write { try MetadataProvenanceSQL.save(provenance, ownerID: ownerID, ownerTable: "builds", db: $0) }
    }
}

enum MetadataProvenanceSQL {
    private static func table(for ownerTable: String) -> (name: String, ownerColumn: String) {
        ownerTable == "games" ? ("game_metadata_provenance", "game_id") : ("build_metadata_provenance", "build_id")
    }

    static func fetch(ownerID: UUID, ownerTable: String, db: Database) throws -> [MetadataProvenance] {
        let table = table(for: ownerTable)
        return try Row.fetchAll(db, sql: """
            SELECT provenance.* FROM \(table.name) provenance
            JOIN \(ownerTable) owner ON owner.id = provenance.\(table.ownerColumn)
            WHERE owner.id = ? AND owner.deletion_id IS NULL ORDER BY provenance.field
            """, arguments: [PersistenceCodec.uuid(ownerID)]).map { row in
                let fieldValue: String = row["field"]
                let sourceValue: String = row["source"]
                let confidenceValue: String? = row["confidence"]
                guard let field = MetadataField(rawValue: fieldValue) else {
                    throw PersistenceError.invalidEnum(type: "MetadataField", value: fieldValue)
                }
                guard let source = MetadataSource(rawValue: sourceValue) else {
                    throw PersistenceError.invalidEnum(type: "MetadataSource", value: sourceValue)
                }
                let confidence = try confidenceValue.map { value in
                    guard let confidence = MetadataConfidence(rawValue: value) else {
                        throw PersistenceError.invalidEnum(type: "MetadataConfidence", value: value)
                    }
                    return confidence
                }
                return MetadataProvenance(field: field, source: source, confidence: confidence,
                    providedValue: row["provided_value"], recordedAt: try PersistenceCodec.date(row["recorded_at"] as String))
            }
    }

    static func save(_ provenance: MetadataProvenance, ownerID: UUID, ownerTable: String, db: Database) throws {
        let table = table(for: ownerTable)
        try db.execute(sql: """
            INSERT INTO \(table.name) (\(table.ownerColumn), field, source, confidence, provided_value, recorded_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(\(table.ownerColumn), field) DO UPDATE SET source = excluded.source,
                confidence = excluded.confidence, provided_value = excluded.provided_value, recorded_at = excluded.recorded_at
            """, arguments: [PersistenceCodec.uuid(ownerID), provenance.field.rawValue, provenance.source.rawValue,
                provenance.confidence?.rawValue, provenance.providedValue, PersistenceCodec.date(provenance.recordedAt)])
    }

    static func recordPlayerOverride(field: MetadataField, value: String?, ownerID: UUID,
                                    ownerTable: String, at date: Date, db: Database) throws {
        let previous = try fetch(ownerID: ownerID, ownerTable: ownerTable, db: db).first { $0.field == field }
        try save(previous?.playerOverride(recordedAt: date)
            ?? MetadataProvenance(field: field, source: .player, providedValue: value, recordedAt: date),
            ownerID: ownerID, ownerTable: ownerTable, db: db)
    }
}

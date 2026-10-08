import EmulatorApplication
import EmulatorDomain
import Foundation
import GRDB

public final class GRDBImageFingerprintRepository: ImageFingerprintRepository, GRDBRepositoryBacking, @unchecked Sendable {
    let writer: any DatabaseWriter

    init(writer: any DatabaseWriter) { self.writer = writer }

    public func saveFingerprint(_ fingerprint: ImageFingerprint) throws {
        // Each hash occupies eight little-endian bytes in the blob.
        let blob = Data(fingerprint.bankHashes.flatMap { hash in
            (0..<8).map { UInt8(truncatingIfNeeded: hash >> ($0 * 8)) }
        })
        try write { db in
            try db.execute(sql: """
                INSERT INTO image_fingerprints (image_sha256, bank_size, bank_hashes, header_title, cartridge_type, ram_size_code, cgb_flag)
                SELECT ?, ?, ?, ?, ?, ?, ? WHERE EXISTS (
                    SELECT 1 FROM managed_assets WHERE kind = 'sourceROM' AND content_sha256 = ?
                )
                ON CONFLICT(image_sha256) DO UPDATE SET bank_size = excluded.bank_size,
                    bank_hashes = excluded.bank_hashes, header_title = excluded.header_title,
                    cartridge_type = excluded.cartridge_type, ram_size_code = excluded.ram_size_code, cgb_flag = excluded.cgb_flag
                """, arguments: [fingerprint.imageSHA256, fingerprint.bankSize, blob, fingerprint.headerTitle,
                    Int(fingerprint.cartridgeType), Int(fingerprint.ramSizeCode), Int(fingerprint.cgbFlag), fingerprint.imageSHA256])
        }
    }

    public func fetchFingerprints(imageSHA256s: [String]) throws -> [String: ImageFingerprint] {
        guard !imageSHA256s.isEmpty else { return [:] }
        let wanted = Set(imageSHA256s)
        // Reading the small metadata table once keeps the query count bounded even above SQLite's
        // parameter limit. No ROM bytes are read during matching.
        return try read { db in
            var result: [String: ImageFingerprint] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT * FROM image_fingerprints") {
                let sha256: String = row["image_sha256"]
                guard wanted.contains(sha256) else { continue }
                let blob: Data = row["bank_hashes"]
                let hashes = stride(from: 0, to: blob.count, by: 8).map { start in
                    (0..<8).reduce(UInt64(0)) { $0 | UInt64(blob[start + $1]) << ($1 * 8) }
                }
                result[sha256] = ImageFingerprint(imageSHA256: sha256, bankSize: row["bank_size"], bankHashes: hashes,
                    headerTitle: row["header_title"], cartridgeType: UInt8(row["cartridge_type"] as Int),
                    ramSizeCode: UInt8(row["ram_size_code"] as Int), cgbFlag: UInt8(row["cgb_flag"] as Int))
            }
            return result
        }
    }

    public func deleteFingerprint(imageSHA256: String) throws {
        try write { db in
            try db.execute(sql: "DELETE FROM image_fingerprints WHERE image_sha256 = ?", arguments: [imageSHA256])
        }
    }
}

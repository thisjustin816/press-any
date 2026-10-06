import EmulatorApplication
import EmulatorDomain
import Foundation
import GRDB

/// Recently Deleted in SQLite. A deleted record keeps its row with `deletion_id` set, which every
/// other repository read leaves out, so its files stay referenced and `managed_assets` keeps them.
public final class GRDBLibraryDeletionRepository: LibraryDeletionRepository, GRDBRepositoryBacking, @unchecked Sendable {
    let writer: any DatabaseWriter

    /// The tables a deletion marks, with the record kind each holds.
    private static let tables: [(table: String, kind: LibraryRecordKind)] = [
        ("games", .game), ("builds", .build), ("save_profiles", .saveProfile), ("save_states", .saveState),
    ]

    init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    public func insertDeletion(_ deletion: LibraryDeletion) throws {
        try write { db in
            let deletionID = PersistenceCodec.uuid(deletion.id)
            try db.execute(
                sql: "INSERT INTO library_deletions (id, kind, title, game_id, deleted_at) VALUES (?, ?, ?, ?, ?)",
                arguments: [
                    deletionID, deletion.kind.rawValue, deletion.title,
                    PersistenceCodec.uuid(deletion.gameID), PersistenceCodec.date(deletion.deletedAt),
                ]
            )
            let records = deletion.records
            for (table, ids) in [
                ("games", records.gameIDs), ("builds", records.buildIDs),
                ("save_profiles", records.saveProfileIDs), ("save_states", records.saveStateIDs),
            ] {
                for id in ids {
                    try db.execute(
                        sql: "UPDATE \(table) SET deletion_id = ? WHERE id = ? AND deletion_id IS NULL",
                        arguments: [deletionID, PersistenceCodec.uuid(id)]
                    )
                }
            }
        }
    }

    public func fetchDeletions() throws -> [LibraryDeletion] {
        try read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM library_deletions ORDER BY deleted_at DESC, id")
                .map { try Self.deletion($0, db: db) }
        }
    }

    public func restoreDeletion(id: UUID) throws {
        try write { db in
            let deletionID = PersistenceCodec.uuid(id)
            // The Game may have gained the same ROM again, which would make two live copies.
            if let conflict = try String.fetchOne(
                db,
                sql: """
                SELECT deleted.id FROM builds deleted
                JOIN builds live ON live.game_id = deleted.game_id AND live.rom_sha256 = deleted.rom_sha256
                WHERE deleted.deletion_id = ? AND live.deletion_id IS NULL
                LIMIT 1
                """,
                arguments: [deletionID]
            ) {
                throw LibraryDeletionError.romAlreadyInGame(try PersistenceCodec.uuid(conflict))
            }
            // The Game may have a new Base since; it keeps that one.
            try db.execute(
                sql: """
                UPDATE builds SET is_base = 0
                WHERE deletion_id = ? AND is_base = 1 AND EXISTS (
                    SELECT 1 FROM builds other
                    WHERE other.game_id = builds.game_id AND other.is_base = 1 AND other.deletion_id IS NULL
                )
                """,
                arguments: [deletionID]
            )
            for (table, _) in Self.tables {
                try db.execute(sql: "UPDATE \(table) SET deletion_id = NULL WHERE deletion_id = ?", arguments: [deletionID])
            }
            try db.execute(sql: "DELETE FROM library_deletions WHERE id = ?", arguments: [deletionID])
        }
    }

    public func purgeDeletion(id: UUID, at date: Date) throws -> [ManagedAsset] {
        try write { db in
            var purged = [PersistenceCodec.uuid(id)]
            guard try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM library_deletions WHERE id = ?", arguments: [purged[0]]) == 1 else {
                return []
            }
            // A deleted patched Build elsewhere can't be rebuilt once its base goes, so its
            // deletion goes too, and so on down the line.
            while true {
                let list = Self.placeholders(purged.count)
                let dependents = try String.fetchAll(
                    db,
                    sql: """
                    SELECT DISTINCT result.deletion_id FROM patch_recipes recipe
                    JOIN builds result ON result.id = recipe.result_build_id
                    JOIN builds base ON base.id = recipe.base_build_id
                    WHERE base.deletion_id IN \(list) AND result.deletion_id IS NOT NULL
                        AND result.deletion_id NOT IN \(list)
                    """,
                    arguments: StatementArguments(purged + purged)
                )
                if dependents.isEmpty { break }
                purged += dependents
            }
            let list = Self.placeholders(purged.count)
            let inPurged = StatementArguments(purged)

            let deletions = try Row.fetchAll(
                db,
                sql: "SELECT * FROM library_deletions WHERE id IN \(list)",
                arguments: inPurged
            ).map { try Self.deletion($0, db: db) }

            let candidates = try Set(String.fetchAll(
                db,
                sql: """
                SELECT artwork_asset_id FROM games WHERE deletion_id IN \(list) AND artwork_asset_id IS NOT NULL
                UNION SELECT rom_asset_id FROM builds WHERE deletion_id IN \(list)
                UNION SELECT item.patch_asset_id FROM patch_recipe_items item
                    JOIN patch_recipes recipe ON recipe.id = item.recipe_id
                    JOIN builds result ON result.id = recipe.result_build_id
                    WHERE result.deletion_id IN \(list)
                UNION SELECT map.asset_id FROM build_variable_maps map
                    JOIN builds build ON build.id = map.build_id WHERE build.deletion_id IN \(list)
                UNION SELECT battery_asset_id FROM save_profiles WHERE deletion_id IN \(list) AND battery_asset_id IS NOT NULL
                UNION SELECT state_asset_id FROM save_states WHERE deletion_id IN \(list)
                UNION SELECT screenshot_asset_id FROM save_states WHERE deletion_id IN \(list) AND screenshot_asset_id IS NOT NULL
                """,
                arguments: StatementArguments(Array(repeating: purged, count: 7).flatMap { $0 })
            ))

            // settings_overrides has no foreign keys, since its scope can also be the app or a system.
            try db.execute(
                sql: """
                DELETE FROM settings_overrides
                WHERE (scope_type = 'build' AND scope_id IN (SELECT id FROM builds WHERE deletion_id IN \(list)))
                   OR (scope_type = 'game' AND scope_id IN (SELECT id FROM games WHERE deletion_id IN \(list)))
                """,
                arguments: StatementArguments(purged + purged)
            )
            // A patch's base is protected from deletion, so results go before the Builds they use.
            try db.execute(
                sql: "DELETE FROM patch_recipes WHERE result_build_id IN (SELECT id FROM builds WHERE deletion_id IN \(list))",
                arguments: inPurged
            )
            for table in ["save_states", "save_profiles", "builds", "games"] {
                try db.execute(sql: "DELETE FROM \(table) WHERE deletion_id IN \(list)", arguments: inPurged)
            }

            let purgedAt = PersistenceCodec.date(date)
            for deletion in deletions {
                for record in deletion.records.all {
                    try db.execute(
                        sql: "INSERT OR IGNORE INTO tombstones (record_id, record_kind, deleted_at, purged_at) VALUES (?, ?, ?, ?)",
                        arguments: [
                            PersistenceCodec.uuid(record.id), record.kind.rawValue,
                            PersistenceCodec.date(deletion.deletedAt), purgedAt,
                        ]
                    )
                }
            }
            try db.execute(sql: "DELETE FROM library_deletions WHERE id IN \(list)", arguments: inPurged)

            var released: [ManagedAsset] = []
            for assetID in candidates.sorted() where try !Self.isReferenced(assetID, db: db) {
                guard let asset = try ManagedAssetRecord.fetchOne(
                    db,
                    sql: "SELECT * FROM managed_assets WHERE id = ?",
                    arguments: [assetID]
                )?.domain() else { continue }
                try db.execute(sql: "DELETE FROM managed_assets WHERE id = ?", arguments: [assetID])
                released.append(asset)
            }
            return released
        }
    }

    public func fetchTombstones() throws -> [Tombstone] {
        try read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM tombstones ORDER BY purged_at, record_id").map { row in
                guard let kind = LibraryRecordKind(rawValue: row["record_kind"]) else {
                    throw PersistenceError.invalidEnum(type: "LibraryRecordKind", value: row["record_kind"])
                }
                return Tombstone(
                    recordID: try PersistenceCodec.uuid(row["record_id"] as String),
                    kind: kind,
                    deletedAt: try PersistenceCodec.date(row["deleted_at"] as String),
                    purgedAt: try PersistenceCodec.date(row["purged_at"] as String)
                )
            }
        }
    }

    private static func deletion(_ row: Row, db: Database) throws -> LibraryDeletion {
        let id: String = row["id"]
        guard let kind = LibraryDeletion.Kind(rawValue: row["kind"]) else {
            throw PersistenceError.invalidEnum(type: "LibraryDeletion.Kind", value: row["kind"])
        }
        func ids(_ table: String) throws -> [UUID] {
            try String.fetchAll(db, sql: "SELECT id FROM \(table) WHERE deletion_id = ? ORDER BY id", arguments: [id])
                .map { try PersistenceCodec.uuid($0) }
        }
        return LibraryDeletion(
            id: try PersistenceCodec.uuid(id),
            kind: kind,
            title: row["title"],
            gameID: try PersistenceCodec.uuid(row["game_id"] as String),
            deletedAt: try PersistenceCodec.date(row["deleted_at"] as String),
            records: LibraryRecordSet(
                gameIDs: try ids("games"),
                buildIDs: try ids("builds"),
                saveProfileIDs: try ids("save_profiles"),
                saveStateIDs: try ids("save_states")
            )
        )
    }

    /// Whether any record, live or waiting in Recently Deleted, still uses the asset.
    private static func isReferenced(_ assetID: String, db: Database) throws -> Bool {
        try Int.fetchOne(
            db,
            sql: """
            SELECT (SELECT COUNT(*) FROM games WHERE artwork_asset_id = ?)
                 + (SELECT COUNT(*) FROM builds WHERE rom_asset_id = ?)
                 + (SELECT COUNT(*) FROM patch_recipe_items WHERE patch_asset_id = ?)
                 + (SELECT COUNT(*) FROM build_variable_maps WHERE asset_id = ?)
                 + (SELECT COUNT(*) FROM save_profiles WHERE battery_asset_id = ?)
                 + (SELECT COUNT(*) FROM save_states WHERE state_asset_id = ? OR screenshot_asset_id = ?)
            """,
            arguments: StatementArguments(Array(repeating: assetID, count: 7))
        ) ?? 0 > 0
    }

    private static func placeholders(_ count: Int) -> String {
        "(" + Array(repeating: "?", count: count).joined(separator: ", ") + ")"
    }
}

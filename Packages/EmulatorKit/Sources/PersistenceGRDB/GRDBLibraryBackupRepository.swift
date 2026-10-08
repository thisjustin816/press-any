import EmulatorApplication
import EmulatorDomain
import Foundation
import GRDB

public enum GRDBLibraryBackupError: LocalizedError, Equatable {
    case deletedRecord(table: String, id: UUID)

    public var errorDescription: String? {
        switch self {
        case .deletedRecord:
            "This backup would bring back an item that is in Recently Deleted or was deleted for good. The library has not changed."
        }
    }
}

public final class GRDBLibraryBackupRepository: LibraryBackupRepository, GRDBRepositoryBacking, @unchecked Sendable {
    let writer: any DatabaseWriter
    private static let reportKey = "backup.lastRestoreReport"

    init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    public func readSnapshot<T: Sendable>(
        _ operation: @Sendable (LibraryBackupSnapshot) throws -> T
    ) throws -> T {
        try read { db in
            try GRDBTransactionContext.withDatabase(db) {
                try operation(snapshot(db: db))
            }
        }
    }

    public func commitSnapshot<T: Sendable>(
        replacingLibrary: Bool,
        _ operation: @Sendable (LibraryBackupSnapshot) throws -> (LibraryBackupSnapshot, RestoreReport, T)
    ) throws -> T {
        try write { db in
            try GRDBTransactionContext.withDatabase(db) {
                let current = try snapshot(db: db)
                let (restored, report, result) = try operation(current)
                try db.execute(sql: "PRAGMA defer_foreign_keys = ON")
                if replacingLibrary {
                    try clearLibrary(db: db)
                } else {
                    try refuseDeletedIDs(in: restored, db: db)
                }
                try persist(restored, db: db)
                if !replacingLibrary { try releaseReplacedAssets(current: current, restored: restored, db: db) }
                try GRDBSettingsStore(writer: writer).set(report, key: Self.reportKey, scope: .app)
                return result
            }
        }
    }

    public func lastRestoreReport() throws -> RestoreReport? {
        try read { db in
            guard let json = try String.fetchOne(db, sql: """
                SELECT value_json FROM settings_overrides
                WHERE scope_type = 'app' AND scope_id = 'app' AND key = ?
                """, arguments: [Self.reportKey]) else { return nil }
            return try JSONDecoder().decode(RestoreReport.self, from: Data(json.utf8))
        }
    }

    private func snapshot(db: Database) throws -> LibraryBackupSnapshot {
        let repositories = GRDBRepositorySet(writer: writer)
        var value = LibraryBackupSnapshot(migrationID: try String.fetchOne(db,
            sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid DESC LIMIT 1") ?? "")
        value.games = try repositories.games.fetchGames()
        value.manualPositions = try repositories.games.fetchManualPositions().map {
            BackupManualPosition(gameID: $0.key, position: $0.value)
        }.sorted { $0.gameID.uuidString < $1.gameID.uuidString }
        value.builds = try repositories.builds.fetchAllBuilds()
        value.profiles = try repositories.saveProfiles.fetchAllSaveProfiles()
        value.states = try SaveStateRecord.fetchAll(db, sql: """
            SELECT state.* FROM save_states state
            JOIN builds build ON build.id = state.build_id
            JOIN save_profiles profile ON profile.id = state.save_profile_id
            WHERE state.deletion_id IS NULL AND build.deletion_id IS NULL AND profile.deletion_id IS NULL
                AND state.kind <> 'crashRecovery'
            ORDER BY state.created_at, state.id
            """).map { try $0.domain() }

        let liveBuildIDs = Set(value.builds.map(\.id))
        var declarations = Set<BuildSaveDeclaration>()
        for game in value.games {
            let provenance = try repositories.games.fetchMetadataProvenance(ownerID: game.id)
            if !provenance.isEmpty {
                value.gameProvenance.append(BackupProvenance(ownerID: game.id, values: provenance))
            }
        }
        for build in value.builds {
            if let recipe = try repositories.patchRecipes.fetchPatchRecipe(resultBuildID: build.id),
               liveBuildIDs.contains(recipe.baseBuildID) {
                value.recipes.append(recipe)
            }
            value.variableMaps += try repositories.variableMaps.fetchVariableMaps(buildID: build.id)
            let provenance = try repositories.builds.fetchMetadataProvenance(ownerID: build.id)
            if !provenance.isEmpty {
                value.buildProvenance.append(BackupProvenance(ownerID: build.id, values: provenance))
            }
            declarations.formUnion(try repositories.builds.fetchSaveDeclarations(buildID: build.id))
        }
        value.declarations = declarations.sorted {
            ($0.firstBuildID.uuidString, $0.secondBuildID.uuidString)
                < ($1.firstBuildID.uuidString, $1.secondBuildID.uuidString)
        }
        value.reports = try Row.fetchAll(db, sql: """
            SELECT report.* FROM build_toolchain_reports report
            JOIN builds build ON build.id = report.build_id
            WHERE build.deletion_id IS NULL ORDER BY report.build_id, report.detector
            """).map { row in
                let json: String = row["report_json"]
                return BackupToolchainReport(buildID: try PersistenceCodec.uuid(row["build_id"] as String),
                    report: try JSONDecoder().decode(ToolchainDetectionReport.self, from: Data(json.utf8)),
                    detectedAt: try PersistenceCodec.date(row["detected_at"] as String))
            }
        value.settings = try Row.fetchAll(db, sql: """
            SELECT * FROM settings_overrides WHERE \(Self.portableSettingsPredicate)
            ORDER BY scope_type, scope_id, key
            """).map { row in
                BackupSetting(scopeType: row["scope_type"], scopeID: row["scope_id"],
                    key: row["key"], valueJSON: row["value_json"])
            }

        var assetIDs = Set(value.builds.map(\.imageAssetID))
        assetIDs.formUnion(value.games.compactMap(\.artworkAssetID))
        assetIDs.formUnion(value.profiles.compactMap(\.persistentSaveAssetID))
        assetIDs.formUnion(value.states.map(\.stateAssetID))
        assetIDs.formUnion(value.states.compactMap(\.screenshotAssetID))
        assetIDs.formUnion(value.recipes.flatMap { $0.items.map(\.patchAssetID) })
        assetIDs.formUnion(value.variableMaps.map(\.assetID))
        let inventory = try repositories.assets.fetchAssets()
        value.assets = inventory.filter { assetIDs.contains($0.id) }
        value.retained = RetainedLibraryRecords(recordIDs: try deletedRecordIDs(db: db),
            assets: inventory.filter { !assetIDs.contains($0.id) }.sorted { $0.id.uuidString < $1.id.uuidString })
        return value
    }

    private func deletedRecordIDs(db: Database) throws -> Set<UUID> {
        let ids = try String.fetchAll(db, sql: """
            SELECT id FROM games WHERE deletion_id IS NOT NULL
            UNION SELECT id FROM builds WHERE deletion_id IS NOT NULL
            UNION SELECT id FROM save_profiles WHERE deletion_id IS NOT NULL
            UNION SELECT id FROM save_states WHERE deletion_id IS NOT NULL
            UNION SELECT record_id FROM tombstones
            UNION SELECT recipe.id FROM patch_recipes recipe
                JOIN builds result ON result.id = recipe.result_build_id
                JOIN builds base ON base.id = recipe.base_build_id
                WHERE result.deletion_id IS NOT NULL OR base.deletion_id IS NOT NULL
            UNION SELECT map.id FROM build_variable_maps map JOIN builds build ON build.id = map.build_id
                WHERE build.deletion_id IS NOT NULL
            """)
        return Set(try ids.map { try PersistenceCodec.uuid($0) })
    }

    /// A replaced save or state leaves its old row behind, still holding the profile's or state's
    /// canonical path; the next write to that path would then fail. Its bytes were already copied
    /// to a "before restore" record, so the row goes unless a Recently Deleted record uses it.
    private func releaseReplacedAssets(current: LibraryBackupSnapshot, restored: LibraryBackupSnapshot, db: Database) throws {
        let kept = Set(restored.assets.map(\.id))
        for asset in current.assets where !kept.contains(asset.id) {
            let id = PersistenceCodec.uuid(asset.id)
            guard try !GRDBLibraryDeletionRepository.isReferenced(id, db: db) else { continue }
            try db.execute(sql: "DELETE FROM managed_assets WHERE id = ?", arguments: [id])
        }
    }

    private static let portableSettingsPredicate = """
        key NOT IN (\(BackupSetting.excludedKeys.sorted().map { "'\($0)'" }.joined(separator: ", "))) AND (
            (scope_type = 'app' AND scope_id = 'app') OR scope_type = 'system' OR
            (scope_type = 'game' AND scope_id IN (SELECT id FROM games WHERE deletion_id IS NULL)) OR
            (scope_type = 'build' AND scope_id IN (SELECT id FROM builds WHERE deletion_id IS NULL))
        )
        """

    private func refuseDeletedIDs(in value: LibraryBackupSnapshot, db: Database) throws {
        let records: [(String, LibraryRecordKind, [UUID])] = [
            ("games", .game, value.games.map(\.id)),
            ("builds", .build, value.builds.map(\.id)),
            ("save_profiles", .saveProfile, value.profiles.map(\.id)),
            ("save_states", .saveState, value.states.map(\.id)),
        ]
        for (table, kind, ids) in records {
            let deleted = Set(try String.fetchAll(db, sql: """
                SELECT id FROM \(table) WHERE deletion_id IS NOT NULL
                UNION SELECT record_id FROM tombstones WHERE record_kind = ?
                """, arguments: [kind.rawValue]))
            for id in ids where deleted.contains(PersistenceCodec.uuid(id)) {
                throw GRDBLibraryBackupError.deletedRecord(table: table, id: id)
            }
        }
        let auxiliary: [(String, [UUID], String)] = [
            ("patch_recipes", value.recipes.map(\.id), """
                SELECT recipe.id FROM patch_recipes recipe
                JOIN builds result ON result.id = recipe.result_build_id
                JOIN builds base ON base.id = recipe.base_build_id
                WHERE result.deletion_id IS NOT NULL OR base.deletion_id IS NOT NULL
                """),
            ("build_variable_maps", value.variableMaps.map(\.id), """
                SELECT map.id FROM build_variable_maps map JOIN builds build ON build.id = map.build_id
                WHERE build.deletion_id IS NOT NULL
                """),
        ]
        for (table, ids, sql) in auxiliary {
            let deleted = Set(try String.fetchAll(db, sql: sql))
            for id in ids where deleted.contains(PersistenceCodec.uuid(id)) {
                throw GRDBLibraryBackupError.deletedRecord(table: table, id: id)
            }
        }
    }

    private func clearLibrary(db: Database) throws {
        for table in [
            "save_states", "patch_recipe_items", "patch_recipes", "build_variable_maps",
            "build_toolchain_reports", "build_save_declarations", "build_metadata_provenance",
            "game_metadata_provenance", "game_aliases", "game_manual_positions", "save_profiles", "builds", "games",
            "managed_assets", "library_deletions", "tombstones", "settings_overrides", "image_fingerprints",
        ] {
            try db.execute(sql: "DELETE FROM \(table)")
        }
    }

    private func persist(_ value: LibraryBackupSnapshot, db: Database) throws {
        let repositories = GRDBRepositorySet(writer: writer)
        for asset in value.assets { try ManagedAssetRecord(asset).save(db) }
        for game in value.games {
            try GameRecord(game).save(db)
            try db.execute(sql: "DELETE FROM game_aliases WHERE game_id = ?", arguments: [PersistenceCodec.uuid(game.id)])
            for alias in game.aliases {
                try db.execute(sql: "INSERT OR IGNORE INTO game_aliases (game_id, title) VALUES (?, ?)",
                    arguments: [PersistenceCodec.uuid(game.id), alias])
            }
        }
        try db.execute(sql: """
            DELETE FROM game_manual_positions
            WHERE game_id IN (SELECT id FROM games WHERE deletion_id IS NULL)
            """)
        for value in value.manualPositions {
            try db.execute(sql: "INSERT INTO game_manual_positions (game_id, position) VALUES (?, ?)",
                arguments: [PersistenceCodec.uuid(value.gameID), value.position])
        }

        // Unique Base and slot assignments may trade owners within the same restore.
        for build in value.builds {
            try db.execute(sql: "UPDATE builds SET is_base = 0 WHERE id = ?", arguments: [PersistenceCodec.uuid(build.id)])
        }
        for state in value.states {
            try db.execute(sql: "UPDATE save_states SET slot = NULL WHERE id = ?", arguments: [PersistenceCodec.uuid(state.id)])
        }
        for build in value.builds {
            try BuildRecord(build).save(db)
            // Ordinary metadata writes omit nil SHA-1; restore must also restore an explicit nil.
            try db.execute(sql: "UPDATE builds SET rom_sha1 = ? WHERE id = ?",
                arguments: [build.imageSHA1, PersistenceCodec.uuid(build.id)])
        }
        for profile in value.profiles { try SaveProfileRecord(profile).save(db) }
        for state in value.states { try SaveStateRecord(state).save(db) }
        for recipe in value.recipes {
            try PatchRecipeRecord(recipe).save(db)
            try db.execute(sql: "DELETE FROM patch_recipe_items WHERE recipe_id = ?", arguments: [PersistenceCodec.uuid(recipe.id)])
            for item in recipe.items { try PatchRecipeItemRecord(recipeID: recipe.id, value: item).insert(db) }
        }
        for map in value.variableMaps {
            try db.execute(sql: """
                INSERT INTO build_variable_maps (id, build_id, asset_id, format, source, original_filename, attached_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET build_id = excluded.build_id, asset_id = excluded.asset_id,
                    format = excluded.format, source = excluded.source, original_filename = excluded.original_filename,
                    attached_at = excluded.attached_at
                """, arguments: [PersistenceCodec.uuid(map.id), PersistenceCodec.uuid(map.buildID),
                    PersistenceCodec.uuid(map.assetID), map.format.rawValue, map.source.rawValue,
                    map.originalFilename, PersistenceCodec.date(map.attachedAt)])
        }

        for game in value.games {
            try db.execute(sql: "DELETE FROM game_metadata_provenance WHERE game_id = ?", arguments: [PersistenceCodec.uuid(game.id)])
        }
        for build in value.builds {
            try db.execute(sql: "DELETE FROM build_metadata_provenance WHERE build_id = ?", arguments: [PersistenceCodec.uuid(build.id)])
            try db.execute(sql: "DELETE FROM build_toolchain_reports WHERE build_id = ?", arguments: [PersistenceCodec.uuid(build.id)])
        }
        for owner in value.gameProvenance {
            for provenance in owner.values {
                try MetadataProvenanceSQL.save(provenance, ownerID: owner.ownerID, ownerTable: "games", db: db)
            }
        }
        for owner in value.buildProvenance {
            for provenance in owner.values {
                try MetadataProvenanceSQL.save(provenance, ownerID: owner.ownerID, ownerTable: "builds", db: db)
            }
        }
        for report in value.reports {
            try repositories.toolchainReports.saveReport(report.report, buildID: report.buildID, detectedAt: report.detectedAt)
        }
        try db.execute(sql: """
            DELETE FROM build_save_declarations
            WHERE first_build_id IN (SELECT id FROM builds WHERE deletion_id IS NULL)
                AND second_build_id IN (SELECT id FROM builds WHERE deletion_id IS NULL)
            """)
        for declaration in value.declarations {
            // Declarations remain valid after a Build moves to another Game.
            try db.execute(sql: """
                INSERT INTO build_save_declarations (first_build_id, second_build_id, compatibility) VALUES (?, ?, ?)
                """, arguments: [PersistenceCodec.uuid(declaration.firstBuildID),
                    PersistenceCodec.uuid(declaration.secondBuildID), declaration.compatibility.rawValue])
        }
        try db.execute(sql: "DELETE FROM settings_overrides WHERE \(Self.portableSettingsPredicate)")
        for setting in value.settings where !BackupSetting.excludedKeys.contains(setting.key) {
            try db.execute(sql: """
                INSERT INTO settings_overrides (scope_type, scope_id, key, value_json) VALUES (?, ?, ?, ?)
                ON CONFLICT(scope_type, scope_id, key) DO UPDATE SET value_json = excluded.value_json
                """, arguments: [setting.scopeType, setting.scopeID, setting.key, setting.valueJSON])
        }
    }
}

enum BackupCoverage {
    static let tables: [String: String] = [
        "grdb_migrations": "Newest applied identifier only; migration history belongs to the destination.",
        "games": "All live Game metadata.",
        "game_aliases": "Canonical aliases of live Games.",
        "game_manual_positions": "Manual sort positions of live Games; follows the Game conflict choice.",
        "builds": "All live Build metadata, source and generated image references, and playtime.",
        "save_profiles": "All live Save Profiles, battery references, RTC, and session history.",
        "save_states": "Live states and thumbnails except crash recovery checkpoints.",
        "patch_recipes": "Recipes whose result and base Builds are live.",
        "patch_recipe_items": "All steps of included recipes, including disabled steps and input hashes.",
        "build_variable_maps": "Maps attached to live Builds.",
        "managed_assets": "Assets referenced by included records, including source and generated images. Rows held only by Recently Deleted records stay in the destination and are reused by hash.",
        "game_metadata_provenance": "Canonical provenance of live Games.",
        "build_metadata_provenance": "Canonical provenance of live Builds.",
        "build_toolchain_reports": "Domain reports of live Builds with their stored detection timestamps.",
        "build_save_declarations": "Canonical pairs whose two Builds are live, even across Games.",
        "settings_overrides": "App, System, and live Game/Build settings, including release preferences and manual sorting; excludes launch markers, the last restore report, and No-Intro backfill markers.",
        "library_deletions": "Excluded; merge preserves it and leaves the backup's copies of its records alone; replacement clears it.",
        "tombstones": "Excluded; merge preserves it and leaves the backup's copies of its records alone; replacement clears it.",
        "image_fingerprints": "Excluded derived matching cache; cleared by replacement.",
    ]

    /// Every column of every table, as the decisions above cover them. Columns that hold
    /// Recently Deleted state (`deletion_id`) or derived matching data stay out of backups with
    /// their table's decision. A new column fails the coverage test until it is listed here and
    /// the backup carries it or a decision above says why not.
    static let columns: [String: Set<String>] = [
        "build_metadata_provenance": ["build_id", "field", "source", "confidence", "provided_value", "recorded_at"],
        "build_save_declarations": ["first_build_id", "second_build_id", "compatibility"],
        "build_toolchain_reports": [
            "build_id", "detector", "detector_version", "corpus_revision", "report_json", "detected_at"
        ],
        "build_variable_maps": ["id", "build_id", "asset_id", "format", "source", "original_filename", "attached_at"],
        "builds": [
            "id", "game_id", "system", "display_name", "rom_asset_id", "rom_sha256", "source_kind",
            "parent_build_id", "is_base", "region", "language", "revision", "version_string", "version_sort_key",
            "preferred_save_profile_id", "pinned_core_id", "pinned_core_version", "core_pinned_at", "created_at",
            "modified_at", "base_title", "hack_title", "author", "translation", "status", "deletion_id", "rom_sha1",
            "base_game_reference_json", "notes", "total_playtime_seconds"
        ],
        "game_aliases": ["game_id", "title"],
        "game_manual_positions": ["game_id", "position"],
        "game_metadata_provenance": ["game_id", "field", "source", "confidence", "provided_value", "recorded_at"],
        "games": [
            "id", "primary_title", "system_family", "preferred_build_id", "preferred_save_profile_id", "created_at",
            "modified_at", "artwork_asset_id", "lineage_source_game_id", "lineage_source_title", "deletion_id",
            "has_player_title", "is_favorite"
        ],
        "grdb_migrations": ["identifier"],
        "image_fingerprints": [
            "image_sha256", "bank_size", "bank_hashes", "header_title", "cartridge_type", "ram_size_code",
            "cgb_flag"
        ],
        "library_deletions": ["id", "kind", "title", "game_id", "deleted_at"],
        "managed_assets": [
            "id", "kind", "storage_class", "content_sha256", "byte_length", "relative_path", "original_filename",
            "provenance_json", "integrity_status", "created_at"
        ],
        "patch_recipe_items": [
            "recipe_id", "position", "patch_asset_id", "enabled", "ignores_base_mismatch", "expected_input_sha256"
        ],
        "patch_recipes": ["id", "result_build_id", "base_build_id", "expected_result_sha256", "created_at"],
        "save_profiles": [
            "id", "game_id", "display_name", "badge", "battery_asset_id", "copied_from_profile_id",
            "rtc_context_json", "total_playtime_seconds", "session_count", "last_played_at", "created_at",
            "modified_at", "save_written_by_build_id", "deletion_id"
        ],
        "save_states": [
            "id", "build_id", "save_profile_id", "core_id", "core_version", "state_serialization_version",
            "state_asset_id", "screenshot_asset_id", "kind", "auto_sequence", "label", "playtime_seconds",
            "created_at", "deletion_id", "slot", "is_pinned"
        ],
        "settings_overrides": ["scope_type", "scope_id", "key", "value_json"],
        "tombstones": ["record_id", "record_kind", "deleted_at", "purged_at"],
    ]

    static let ports: [String: String] = [
        "GameRepository": "Live Games, aliases and manual sort positions.",
        "BuildRepository": "Live Builds and save compatibility declarations.",
        "SaveProfileRepository": "Live Save Profiles.",
        "SaveStateRepository": "Live states except crash recovery.",
        "PatchRecipeRepository": "Live recipes and their steps.",
        "BuildVariableMapRepository": "Maps of live Builds.",
        "ManagedAssetRepository": "Referenced assets.",
        "ManagedAssetInventoryRepository": "Inventory filtered to referenced assets.",
        "MetadataProvenanceRepository": "Live Game and Build provenance.",
        "ToolchainReportRepository": "Live reports with persisted detection timestamps.",
        "SettingsStore": "Portable settings with explicit operational exclusions.",
        "LibraryDeletionRepository": "Excluded deletion history; merge preserves it.",
        "ImageFingerprintRepository": "Excluded derived matching cache.",
        "LibraryBackupRepository": "Snapshot orchestration; restore reports excluded from snapshots.",
        "LibraryTransactionRunner": "Transaction orchestration; no stored records.",
        "AssetStore": "Files belong to the archive caller, outside SQLite.",
        "BuildImageResolving": "Generated image resolution; no separate stored records.",
        "PatchApplying": "Patch execution; no separate stored records.",
    ]
}

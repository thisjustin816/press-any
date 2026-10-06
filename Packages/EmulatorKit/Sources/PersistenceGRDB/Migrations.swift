import GRDB

extension AppDatabase {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("mvp-v1") { db in
            try db.execute(sql: MVPV1Schema.sql)
        }
        migrator.registerMigration("mvp-v2") { db in
            try db.execute(sql: MVPV2Schema.sql)
        }
        migrator.registerMigration("mvp-v3") { db in
            try db.execute(sql: MVPV3Schema.sql)
        }
        migrator.registerMigration("v1-v4-naming") { db in
            try db.execute(sql: V1V4NamingSchema.sql)
        }
        migrator.registerMigration("v1-v5-single-base") { db in
            try db.execute(sql: V1V5SingleBaseSchema.sql)
        }
        migrator.registerMigration("v1-v6-release-sort-marker") { db in
            try db.execute(sql: V1V6ReleaseSortMarkerSchema.sql)
        }
        // Rebuilds `builds`, so it relies on the migrator's default of checking foreign keys only
        // once the migration is done.
        migrator.registerMigration("v1-v7-recently-deleted") { db in
            try db.execute(sql: V1V7RecentlyDeletedSchema.sql)
        }
        return migrator
    }
}

/// Recently Deleted. A deleted Game, Build, Save Profile or state keeps its row, marked with the
/// deletion that hid it, until it is purged; a purged record leaves a tombstone for good.
///
/// A deleted Build keeps its ROM hash, so `builds` is rebuilt to let the one-ROM-per-Game rule and
/// the one-Base rule count only live Builds; SQLite can't drop a table constraint in place.
enum V1V7RecentlyDeletedSchema {
    private static let buildColumns = """
    id, game_id, system, display_name, rom_asset_id, rom_sha256, source_kind, parent_build_id,
    is_base, region, language, revision, version_string, version_sort_key,
    preferred_save_profile_id, pinned_core_id, pinned_core_version, core_pinned_at,
    created_at, modified_at, base_title, hack_title, author, translation, status
    """

    static let sql = #"""
    CREATE TABLE builds_new (
        id TEXT PRIMARY KEY NOT NULL,
        game_id TEXT NOT NULL REFERENCES games(id) ON DELETE CASCADE,
        system TEXT NOT NULL,
        display_name TEXT NOT NULL,
        rom_asset_id TEXT NOT NULL REFERENCES managed_assets(id),
        rom_sha256 TEXT NOT NULL,
        source_kind TEXT NOT NULL,
        parent_build_id TEXT REFERENCES builds(id) ON DELETE SET NULL,
        is_base INTEGER NOT NULL DEFAULT 0 CHECK (is_base IN (0, 1)),
        region TEXT,
        language TEXT,
        revision TEXT,
        version_string TEXT,
        version_sort_key TEXT,
        preferred_save_profile_id TEXT,
        pinned_core_id TEXT,
        pinned_core_version TEXT,
        core_pinned_at TEXT,
        created_at TEXT NOT NULL,
        modified_at TEXT NOT NULL,
        base_title TEXT,
        hack_title TEXT,
        author TEXT,
        translation TEXT,
        status TEXT,
        deletion_id TEXT
    );
    INSERT INTO builds_new (\#(buildColumns)) SELECT \#(buildColumns) FROM builds;
    DROP TABLE builds;
    ALTER TABLE builds_new RENAME TO builds;
    CREATE INDEX builds_game_id ON builds(game_id);
    CREATE INDEX builds_rom_sha256 ON builds(rom_sha256);
    CREATE UNIQUE INDEX builds_live_rom ON builds(game_id, rom_sha256) WHERE deletion_id IS NULL;
    CREATE UNIQUE INDEX builds_single_base ON builds(game_id) WHERE is_base = 1 AND deletion_id IS NULL;

    ALTER TABLE games ADD COLUMN deletion_id TEXT;
    ALTER TABLE save_profiles ADD COLUMN deletion_id TEXT;
    ALTER TABLE save_states ADD COLUMN deletion_id TEXT;

    CREATE TABLE library_deletions (
        id TEXT PRIMARY KEY NOT NULL,
        kind TEXT NOT NULL,
        title TEXT NOT NULL,
        game_id TEXT NOT NULL,
        deleted_at TEXT NOT NULL
    );

    CREATE TABLE tombstones (
        record_id TEXT PRIMARY KEY NOT NULL,
        record_kind TEXT NOT NULL,
        deleted_at TEXT NOT NULL,
        purged_at TEXT NOT NULL
    );
    """#
}

/// Version sort keys gained a suffix so a prerelease sorts before its release: "~" ends a release's
/// key. Keys stored before then were only ever a release's numbers, so each gains the "~".
enum V1V6ReleaseSortMarkerSchema {
    static let sql = #"""
    UPDATE builds SET version_sort_key = version_sort_key || '~'
    WHERE version_sort_key IS NOT NULL AND version_sort_key NOT GLOB '*[^0-9.]*';
    """#
}

enum V1V5SingleBaseSchema {
    static let sql = #"""
    UPDATE builds SET is_base = 0
    WHERE is_base = 1 AND id NOT IN (
        SELECT id FROM (
            SELECT builds.id,
                   ROW_NUMBER() OVER (
                       PARTITION BY game_id
                       ORDER BY CASE WHEN builds.id = games.preferred_build_id THEN 0 ELSE 1 END,
                                builds.created_at DESC, builds.id
                   ) AS base_rank
            FROM builds JOIN games ON games.id = builds.game_id
            WHERE is_base = 1 AND source_kind = 'importedROM'
        ) WHERE base_rank = 1
    );

    CREATE UNIQUE INDEX builds_single_base ON builds(game_id) WHERE is_base = 1;
    """#
}

enum V1V4NamingSchema {
    static let sql = #"""
    ALTER TABLE builds ADD COLUMN base_title TEXT;
    ALTER TABLE builds ADD COLUMN hack_title TEXT;
    ALTER TABLE builds ADD COLUMN author TEXT;
    ALTER TABLE builds ADD COLUMN translation TEXT;
    ALTER TABLE builds ADD COLUMN status TEXT;
    """#
}

enum MVPV1Schema {
    static let sql = #"""
    PRAGMA foreign_keys = ON;

    CREATE TABLE games (
        id TEXT PRIMARY KEY NOT NULL,
        primary_title TEXT NOT NULL,
        system_family TEXT NOT NULL,
        preferred_build_id TEXT,
        preferred_save_profile_id TEXT,
        created_at TEXT NOT NULL,
        modified_at TEXT NOT NULL
    );

    CREATE TABLE managed_assets (
        id TEXT PRIMARY KEY NOT NULL,
        kind TEXT NOT NULL,
        storage_class TEXT NOT NULL,
        content_sha256 TEXT NOT NULL,
        byte_length INTEGER NOT NULL CHECK (byte_length >= 0),
        relative_path TEXT NOT NULL UNIQUE,
        original_filename TEXT,
        provenance_json TEXT,
        integrity_status TEXT NOT NULL,
        created_at TEXT NOT NULL
    );

    CREATE UNIQUE INDEX managed_assets_dedup_source
    ON managed_assets(kind, content_sha256)
    WHERE storage_class = 'source';

    CREATE TABLE builds (
        id TEXT PRIMARY KEY NOT NULL,
        game_id TEXT NOT NULL REFERENCES games(id) ON DELETE CASCADE,
        system TEXT NOT NULL,
        display_name TEXT NOT NULL,
        rom_asset_id TEXT NOT NULL REFERENCES managed_assets(id),
        rom_sha256 TEXT NOT NULL,
        source_kind TEXT NOT NULL,
        parent_build_id TEXT REFERENCES builds(id) ON DELETE SET NULL,
        is_base INTEGER NOT NULL DEFAULT 0 CHECK (is_base IN (0, 1)),
        region TEXT,
        language TEXT,
        revision TEXT,
        version_string TEXT,
        version_sort_key TEXT,
        preferred_save_profile_id TEXT,
        pinned_core_id TEXT,
        pinned_core_version TEXT,
        core_pinned_at TEXT,
        created_at TEXT NOT NULL,
        modified_at TEXT NOT NULL,
        UNIQUE(game_id, rom_sha256)
    );

    CREATE INDEX builds_game_id ON builds(game_id);
    CREATE INDEX builds_rom_sha256 ON builds(rom_sha256);

    CREATE TABLE save_profiles (
        id TEXT PRIMARY KEY NOT NULL,
        game_id TEXT NOT NULL REFERENCES games(id) ON DELETE CASCADE,
        display_name TEXT NOT NULL,
        badge TEXT,
        battery_asset_id TEXT REFERENCES managed_assets(id) ON DELETE SET NULL,
        copied_from_profile_id TEXT REFERENCES save_profiles(id) ON DELETE SET NULL,
        rtc_context_json TEXT,
        total_playtime_seconds REAL NOT NULL DEFAULT 0,
        session_count INTEGER NOT NULL DEFAULT 0,
        last_played_at TEXT,
        created_at TEXT NOT NULL,
        modified_at TEXT NOT NULL
    );

    CREATE INDEX save_profiles_game_id ON save_profiles(game_id);

    CREATE TABLE save_states (
        id TEXT PRIMARY KEY NOT NULL,
        build_id TEXT NOT NULL REFERENCES builds(id) ON DELETE CASCADE,
        save_profile_id TEXT NOT NULL REFERENCES save_profiles(id) ON DELETE CASCADE,
        core_id TEXT NOT NULL,
        core_version TEXT NOT NULL,
        state_serialization_version TEXT NOT NULL,
        state_asset_id TEXT NOT NULL REFERENCES managed_assets(id),
        screenshot_asset_id TEXT REFERENCES managed_assets(id) ON DELETE SET NULL,
        kind TEXT NOT NULL,
        auto_sequence INTEGER,
        label TEXT,
        playtime_seconds REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
    );

    CREATE INDEX save_states_context
    ON save_states(build_id, save_profile_id, created_at DESC);

    CREATE TABLE patch_recipes (
        id TEXT PRIMARY KEY NOT NULL,
        result_build_id TEXT NOT NULL UNIQUE REFERENCES builds(id) ON DELETE CASCADE,
        base_build_id TEXT NOT NULL REFERENCES builds(id) ON DELETE RESTRICT,
        expected_result_sha256 TEXT NOT NULL,
        created_at TEXT NOT NULL
    );

    CREATE TABLE patch_recipe_items (
        recipe_id TEXT NOT NULL REFERENCES patch_recipes(id) ON DELETE CASCADE,
        position INTEGER NOT NULL CHECK (position >= 0),
        patch_asset_id TEXT NOT NULL REFERENCES managed_assets(id) ON DELETE RESTRICT,
        enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
        PRIMARY KEY(recipe_id, position)
    );

    CREATE TABLE settings_overrides (
        scope_type TEXT NOT NULL,
        scope_id TEXT NOT NULL,
        key TEXT NOT NULL,
        value_json TEXT NOT NULL,
        PRIMARY KEY(scope_type, scope_id, key)
    );
    """#
}

/// Apply Anyway on patch recipes, and manually assigned Game artwork.
enum MVPV2Schema {
    static let sql = #"""
    ALTER TABLE patch_recipe_items
    ADD COLUMN ignores_base_mismatch INTEGER NOT NULL DEFAULT 0 CHECK (ignores_base_mismatch IN (0, 1));

    ALTER TABLE games
    ADD COLUMN artwork_asset_id TEXT REFERENCES managed_assets(id) ON DELETE SET NULL;
    """#
}

enum MVPV3Schema {
    static let sql = #"""
    CREATE TABLE build_toolchain_reports (
        build_id TEXT NOT NULL REFERENCES builds(id) ON DELETE CASCADE,
        detector TEXT NOT NULL,
        detector_version TEXT NOT NULL,
        corpus_revision TEXT NOT NULL,
        report_json TEXT NOT NULL,
        detected_at TEXT NOT NULL,
        PRIMARY KEY (build_id, detector)
    );

    ALTER TABLE save_profiles
    ADD COLUMN save_written_by_build_id TEXT REFERENCES builds(id) ON DELETE SET NULL;

    CREATE TABLE build_variable_maps (
        id TEXT PRIMARY KEY NOT NULL,
        build_id TEXT NOT NULL REFERENCES builds(id) ON DELETE CASCADE,
        asset_id TEXT NOT NULL REFERENCES managed_assets(id),
        format TEXT NOT NULL,
        source TEXT NOT NULL,
        original_filename TEXT NOT NULL,
        attached_at TEXT NOT NULL,
        UNIQUE (build_id, asset_id)
    );

    ALTER TABLE games
    ADD COLUMN lineage_source_game_id TEXT REFERENCES games(id) ON DELETE SET NULL;

    ALTER TABLE games
    ADD COLUMN lineage_source_title TEXT;
    """#
}

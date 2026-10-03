import GRDB

extension AppDatabase {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("mvp-v1") { db in
            try db.execute(sql: MVPV1Schema.sql)
        }
        return migrator
    }
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

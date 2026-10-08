# Library Backup format

A Library Backup or Game package is an ordinary `.zip` file. It has no custom extension or
UTType. The filename is `<app display name> Backup <UTC date>.zip`, with a number added if
that name already exists. Only the contents identify a backup; renaming the file is safe.

The app recognizes `backup-manifest.json` at the archive root before looking for ROMs.
A manifest inside another folder does not identify a backup.

## Manifest

`backup-manifest.json` is readable JSON. Format version 1 has these fields:

| Field | Meaning |
|---|---|
| `formatVersion` | Integer format version, starting at 1 |
| `appVersion`, `appBuild` | The writing app's version and build strings |
| `migrationID` | Newest database migration applied when the snapshot was taken |
| `createdAt` | Creation date |
| `includesROMs` | Whether source ROM files were requested |
| `isEncrypted` | Whether password support is required; exports currently write `false` |
| `isGamePackage` | Whether this archive is scoped to a Game |
| `gameID` | The selected Game's stable UUID for a Game package; absent for a library backup |
| `recordCounts` | Counts keyed by the record kinds below |
| `files` | Object keyed by relative filename; each value has `sha256` and `byteLength` |
| `notCarriedOver` | Descriptions of exclusions and source ROMs already missing at export |

The file inventory covers every payload file. It excludes the manifest itself: a file cannot
contain its own SHA-256. The zip CRC-32 checks the manifest bytes. SHA-256 values are lowercase
hex, lengths are integer byte counts, and UUIDs retain record identity. Dates use Foundation's
Codable JSON representation: seconds since January 1, 2001 UTC, including fractions.

A newer `formatVersion` requires an app update and is refused before library changes.
The migration ID is descriptive; restore decodes domain models and never replays SQL rows or
archive migrations. Optional model and manifest fields have decoding defaults. A format change
that cannot be read this way needs a new version. Unknown payload files are refused with an
update message so their data cannot disappear during restore.

## Record files

Each file is a JSON array of the domain models, or a small owner wrapper where the repository
stores ownership separately. A recipe includes its ordered items in its JSON. Field names and
persistent enum values come from the Codable models in `EmulatorDomain`.

| Filename | Count key | Records |
|---|---|---|
| `games.json` | `games` | Games, aliases, title choice, favorite, preferences, artwork reference, lineage and dates |
| `manual-positions.json` | `manualPositions` | `gameID` and zero-based `position` for Games with a manual sort position |
| `builds.json` | `builds` | Builds, immutable image identity, metadata, notes, playtime, lineage and core pins |
| `profiles.json` | `profiles` | Save Profiles, battery reference, recorded writer, copy lineage, RTC and statistics |
| `states.json` | `states` | Manual, Quick, numbered-slot and Auto States, thumbnail references, labels and pins |
| `recipes.json` | `recipes` | Patch recipes and all enabled and disabled items, input hashes and Apply Anyway flags |
| `variable-maps.json` | `variableMaps` | Build variable maps and their file references |
| `managed-assets.json` | `assets` | Referenced asset metadata, including image rows whose files are omitted |
| `game-provenance.json` | `gameProvenance` | `ownerID` and domain provenance `values` for Games |
| `build-provenance.json` | `buildProvenance` | `ownerID` and domain provenance `values` for Builds |
| `toolchain-reports.json` | `reports` | `buildID`, domain `report`, and its stored `detectedAt` |
| `save-declarations.json` | `declarations` | Symmetric Build pairs and their compatibility declarations |
| `settings.json` | `settings` | `scopeType`, `scopeID`, `key`, and `valueJSON` for stored overrides |

Settings include App, System, Game and Build scopes, plus region and language ordering.
Manual positions travel separately and follow the Game conflict choice. Device view
preferences in UserDefaults stay on the device. The
launch marker, last restore report and No-Intro backfill marker are operational records and
are excluded. Lineage pointers to excluded records are omitted from the archive; merge keeps
the destination's pointers when its version is chosen. There are no full Save Profile settings overrides in the current schema.

The coverage test compares all SQLite tables and application repository ports with explicit
backup decisions. Adding either without a decision fails the test.

## Asset files and limits

Asset files use their managed relative paths under `Source/` and `UserData/`. Source ROMs are
included only when requested. Their metadata is always included, so a Build can be restored
with a missing ROM. Source patches, battery saves, states, thumbnails, artwork and variable
maps are included. A missing or changed user file stops export instead of producing a partial
backup. A source ROM already missing is recorded as omitted.

Generated patched ROM files, image fingerprints, crash recovery checkpoints, Quick Play,
staged files and Recently Deleted are excluded. A generated image's asset row and recipe
remain, so launch can rebuild it. Merge leaves the destination's Recently Deleted entries
alone; replacement clears them.

The writer uses the stored method (no compression), UTF-8 paths and CRC-32 from zlib. The
reader also supports deflate. Both refuse Zip64 and enforce 4,096 entries and the existing
32 MiB encoded archive limit. The reader checks a 64 MiB limit per backup entry and a 256 MiB
combined expanded payload before allocating it. Export refuses a backup that exceeds the
encoded limit; it never writes an archive this app cannot open.

Unsafe or repeated paths, links, overlapping entries, malformed headers and mismatched CRCs
are refused. Restore checks every inventoried payload's SHA-256 and length, then checks
record identities and references before starting a library transaction.

## Game packages

A Game package uses the same files and merge rules. It includes the selected Game's Builds,
profiles, states, recipes, patches, artwork, notes, declarations, maps, reports, provenance and
scoped settings. A patch's base Build and its parent chain travel with it, including their
owning Game when necessary. That dependency is visible in the review's contents. Unrelated
Games and App/System settings stay out of a Game package. Whole-library replacement is not
available for a Game package.

## Merge and replacement

Records match by stable ID. Source assets match by content hash. Mutable saves get independent
paths when copied so later play cannot change a preserved copy. Identical records are skipped;
differing versions are conflicts. There is no shared sync baseline, so every difference is
reviewed, with the newer timestamp suggested and ties favoring the library. Saves and states
require an explicit choice.

A Save Profile can be copied as `<name> from backup`. A replaced battery save is copied as
`<profile> before restore`. A replaced state is retained as a pinned manual state with
`before restore` in its name. A Build cannot be duplicated through a conflict choice. A new
state colliding with an occupied numbered slot is kept as a named manual state. Conflicting
immutable Build identities, deleted identities or incompatible record references stop the
restore and leave the library unchanged.

Restore stages files, places them only at unused paths, and commits records and the latest
Migration Report in one transaction. It rechecks the reviewed snapshot before writing. A
failure rolls back metadata and removes the new files; existing files stay intact.

Replace Entire Library first writes an automatic backup to Exports, including ROMs when the
incoming archive includes them. The confirmation names that file. Replacement verifies the
safety backup against the reviewed library and replaces metadata in one transaction. Old
files stay in place; Check Library Files can clean up unreferenced source and cache files.
The latest report records added and skipped items, conflict choices, Builds needing ROMs and
exclusions. The safety filename is shown in the confirmation and immediate result only; it is
never stored in library metadata or used to identify an archive.

## Password encryption

Password encryption is a follow-up. This build exports unencrypted archives and refuses an
archive marked encrypted before any library changes. Password support will encrypt payloads
with CryptoKit AES-GCM and derive the key with PBKDF2-HMAC-SHA256, recording its random salt
and iteration count in the readable manifest. A forgotten password will have no recovery;
a wrong password must leave the library unchanged.

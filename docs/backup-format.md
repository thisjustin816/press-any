# Library Backup format

A Library Backup or Game package is an ordinary `.zip` file. It has no custom extension or
UTType. A library backup is named `<app display name> Backup <UTC date>.zip` and a Game
package `<Game title> <UTC date>.zip`, with a number added if that name already exists. Only
the contents identify a backup; renaming the file is safe.

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
| `isEncrypted` | Always `false`; see "Encryption" below |
| `isGamePackage` | Whether this archive is scoped to a Game |
| `gameID` | The selected Game's stable UUID for a Game package; absent for a library backup |
| `recordCounts` | Counts keyed by the record kinds below |
| `files` | Object keyed by relative filename; each value has `sha256` and `byteLength` |
| `notCarriedOver` | Descriptions of exclusions and of source ROMs missing or changed at export |
| `missingFiles` | Asset paths whose file was missing or damaged when the automatic backup before Replace was written; usually absent |

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
preferences in UserDefaults stay on the device. The launch marker, last restore report and
No-Intro backfill marker are operational records and are excluded. Pointers to records
outside the archive are omitted from it: copy and Game lineage, the Build that last wrote a
save, a parent Build, and a preferred Build or profile. Merge keeps the destination's pointers
when its version is chosen. There are no full Save Profile settings overrides in the current
schema.

The coverage test compares all SQLite tables, their columns and the application repository
ports with explicit backup decisions. Adding any of them without a decision fails the test.

## Asset files and limits

Asset files use their managed relative paths under `Source/` and `UserData/`. Source ROMs are
included only when requested. Their metadata is always included, so a Build can be restored
with a missing ROM. Source patches, battery saves, states, thumbnails, artwork and variable
maps are included. A source ROM that is missing, or whose file no longer matches its hash, is
left out and listed in `notCarriedOver`. A missing or damaged save, state, artwork, patch or
map file stops export with a message naming it, instead of producing a partial backup. A save
or state whose file disagrees with its record is read again once, because a game may be
writing it; if they still disagree, export asks the player to try again in a moment.

The automatic backup before Replace Entire Library must capture what the library still has,
so it leaves a missing or damaged file out instead, lists it in `notCarriedOver`, and records
its path in `missingFiles`. Restore keeps such a record without its file, like a Build without
its ROM.

Generated patched ROM files, image fingerprints, crash recovery checkpoints, Quick Play,
staged files and Recently Deleted are excluded. A generated image's asset row and recipe
remain, so launch can rebuild it.

Export reads the library once, copying each included file to a staging folder inside that one
database read. It then checks the copies against their recorded hashes and streams the zip to
a file, so the database is not held while the archive is written. The manifest's inventory uses
each asset's recorded hash and length.

The writer uses the stored method (no compression), UTF-8 paths and CRC-32 from zlib. The
reader also supports deflate. Both refuse Zip64. A backup or Game package can be up to 2 GiB,
which keeps every zip offset and size in 32 bits. It can hold 4,096 entries, 64 MiB per entry
and 2 GiB of expanded payload. A zip of ROMs, patches or saves opened for import keeps its own
32 MiB limit. Export estimates the archive size from the library and refuses a backup over the
limit before reading any file; it never writes an archive this app cannot open. Restore maps
the archive file and extracts one entry at a time, so memory holds a single file.

Unsafe or repeated paths, links, overlapping entries, malformed headers and mismatched CRCs
are refused in a backup. Restore checks every inventoried payload's SHA-256 and length, then
checks record identities and references before starting a library transaction. A zip of game
files is read leniently instead: entries that are not ROMs, patches or saves are skipped
unread, along with links and bytes after the end of the archive.

## Game packages

A Game package uses the same files and merge rules. It includes the selected Game's Builds,
profiles, states, recipes, patches, artwork, notes, declarations, maps, reports, provenance and
scoped settings. A patch's base Build and its parent chain travel with it, including their
owning Game when necessary. That dependency is visible in the review's contents. Unrelated
Games and App/System settings stay out of a Game package, and restore refuses a package that
holds any record exporting its Game would not write. Whole-library replacement is not
available for a Game package.

## Merge and replacement

Records match by stable ID. Source assets match by content hash against every asset row in
the library, including rows that Recently Deleted records still use. A file already at an
asset's path, with no row using it and the right hash, is reused in place, so restoring a
backup without ROMs after Replace reconnects the ROM files Replace left on disk. Mutable saves
get independent paths when copied so later play cannot change a preserved copy. Identical
records are skipped; differing versions are conflicts. A pointer the backup could not carry,
such as the Build in Recently Deleted that last wrote a save, does not count as a difference.
There is no shared sync baseline, so every difference is reviewed, with the newer timestamp
suggested and ties favoring the library. Saves and states require an explicit choice.

Records the library has in Recently Deleted, or deleted for good, are left alone. Review lists
them, the report notes how many there were, and the restore skips them with the records that
depend on them.

A Save Profile can be copied as `<name> from backup`. A replaced battery save is copied as
`<profile> before restore`. A replaced state is retained as a pinned manual state with
`before restore` in its name. Keeping both versions of a profile copies its backup states to
the copy once. The replaced save's or state's old asset row is removed when nothing else uses
it, so the profile's own save path is free for the next save. A library file that is already
missing or damaged has nothing to preserve: restore repairs over it without a before restore
copy and the report says so. A Build cannot be duplicated through a conflict choice. A new
state colliding with an occupied numbered slot, or a second Quick State for the same Build and
profile, is kept as a named manual state. Conflicting immutable Build identities or
incompatible record references stop the restore and leave the library unchanged; the message
names the Game or record, such as a Game that would have two Base Builds.

Restore stages files, places them only at unused paths, and commits records and the latest
Migration Report in one transaction. It rechecks the reviewed snapshot before writing. A
failure rolls back metadata and removes the new files; existing files stay intact.

Replace Entire Library first writes an automatic backup of the current library to Exports,
always including ROMs. The confirmation names that file and says that Replace removes every
Game, Build, Save Profile and state and empties Recently Deleted for good. Replacement verifies
the safety backup against the reviewed library and replaces metadata in one transaction. Old
files stay in place; Check Library Files can clean up unreferenced source and cache files.
The latest report records added and skipped items, conflict choices, Builds needing ROMs and
exclusions. The safety filename is shown in the confirmation and immediate result only; it is
never stored in library metadata or used to identify an archive.

## Encryption

Backups have no password, and none is planned. The `isEncrypted` field exists only so a reader
refuses an archive that claims to be encrypted, before any library change.

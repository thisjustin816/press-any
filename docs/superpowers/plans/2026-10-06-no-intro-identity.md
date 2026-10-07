# No-Intro Identity Plan

Status: sections 1, 2 and 5 are done (#31 and the import-matching pull request), as is section 3
apart from the title proposal, which waits on section 4. The parser's No-Intro flags are done.

**Goal:** Recognize known Game Boy and Game Boy Color dumps by hash, take their canonical names, and group a family's regional releases under one Game, from data bundled with the app.

The decision behind this plan is "The game database is No-Intro's, bundled, and refreshed by hand" in `docs/decisions.md`. The specs it serves are `dec 17` and `dec 18`, Q156 and Q157, and "Regional releases and No-Intro families".

## 1. The data

DAT-o-MATIC's DB export lists each game as a `game` element holding an `archive` record (the title as `name`, `region`, `languages`, `devstatus`, `version1`, `aftermarket`, `licensed`, and `clone`: `P` on a family's root, otherwise the parent's `number`), then `source` elements for No-Intro's own dumps and `release` elements for scene releases, each with `file` elements carrying `size`, `crc32`, `md5`, `sha1`, sometimes `sha256`, and `bad="1"` on a bad copy. Two exports are needed: "Nintendo - Game Boy" and "Nintendo - Game Boy Color", from the DB column of DAT-o-MATIC's download page. In the 2026-10-06 data they hold every SHA-1 the Parent/Clone XML does and 447 more, about half of them bad copies, and the two formats agree on every family both record. The Parent/Clone XML has no `sha256` at all, and the export lacks it for about 1,300 of 2,919 Game Boy Color files, so SHA-1 is the key.

`Scripts/generate-known-dumps.py <gb export> <gbc export> <output>` writes one JSON file:

- a header: the source, each system's export version, game count and file count, and the day it was generated;
- one record per game, one per line: `name` (the canonical name), `system` (`gb` or `gbc`), `title`, `region`, `languages`, `status`, `version`, `aftermarket`, `unlicensed`, `parent` (the family's root, absent on a root), and `files`, each with `sha1`, `size` and `bad` on a bad copy.

Records sort by system and name, so two runs over the same input give the same bytes. A file listed under both a dump and a release counts once. A clone of a clone points at the root, so a family is one level deep. A clone whose parent the export doesn't include stands alone, and a game with no file is left out; the summary lists both. The script refuses a file shared by two games and the two exports swapped, and prints what changed against the file already committed: games added, removed and renamed.

The file lives at `Packages/EmulatorKit/Sources/GameIdentity/Resources/KnownDumps.json`. `GameIdentity` is a new target that depends only on `EmulatorDomain` and processes its resources, like `SameBoyAdapter`. A test checks that the bundled file loads, that every parent resolves, and that the header's counts match the records.

Refreshing: download the two DB exports from DAT-o-MATIC in a browser (Download, then the DB icon on each system's row), run `make known-dumps GB=<file> GBC=<file>`, read the printed changes, and open a pull request. The pull request body is the printed summary. Nothing fetches from DAT-o-MATIC: see the decision.

## 2. Lookups

`KnownDumpIndex` loads the file once and answers:

- `dump(sha1:)`: the game an image is a copy of, and `file(sha1:)`: the listed image, which says whether it is a bad copy;
- `family(of:)`: the root and every clone of a game's family, the game included;
- `verification(of:sha1:lookup:)`: Verified when the Build's SHA-1 is a good copy of a known game, Bad Dump when it is a listed bad copy, Modified when the Build is patched from a Verified Build, Unknown otherwise.

`SHA1Digest` computes SHA-1 with CryptoKit on Apple platforms and a portable implementation elsewhere, as `SHA256Digest` does.

A known dump's Build Details come from No-Intro's fields, not from its name: the title, region and languages as recorded, `version` split into a revision ("Rev 1") or a version ("v1.1"), and the development status. Aftermarket and Unl never become a status or part of a Build name, since every new homebrew release carries both (owner's call, 2026-10-06). The filename parser still names unknown files; support for No-Intro's other flags is done: numbered development flags retain their numbers, Proto becomes Prototype, and Sample, Kiosk and Debug become statuses. Aftermarket and Unl are recognized and dropped there too. Pirate and Virtual Console remain unknown groups and are preserved in the normalized filename.

## 3. Import

`ROMImportAnalyzer` takes a `KnownDumpIndex` and computes the staged file's SHA-1 beside its SHA-256. A migration adds a nullable `rom_sha1` to `builds`, filled at import; a launch task fills it for Builds imported before, from their source files, so family lookups never read ROMs. When the staged file's SHA-1 is a known dump:

- `filenameMetadata` is parsed from the canonical name, and the analysis records `knownDump` so Import Review can say "Matched No-Intro dump: <name>"; the original filename is preserved as before;
- the analyzer looks up every family member's SHA-1 in the library; the Games that hold one are `familyGameIDs`. One such Game becomes `suggestedGameID` unless the caller named a target. Several leave the choice to the review, which lists them first.

Import Review changes:

- the evidence line names the dump and shows High confidence; the title field is the dump's title;
- when the destination is a family Game and the new release's region ranks higher in the preferred region order than the region of the Game's preferred Build, the review proposes the new release's title for the Game and suggests Preferred; the player sees both before commit, and `ROMImportPlan` carries an optional Game title change;
- `markAsBase` follows the existing rule.

Quick Play promotion and shared patches go through the same review, so they inherit this.

## 4. Preferred region

An App setting, `preferredRegion`, with USA, Europe and Japan as the choices and USA the default; the rest of the order is fixed, World first, then the chosen region, then the other two, then everything else. It decides the title and Preferred suggestions above, and later which regional artwork a Game shows. A fuller ordered list can replace it without changing stored values.

## 5. Technical Info and credits

Build Technical Info gains a Verification row: "Verified · <canonical name>", "Modified · patched from <base name>", or "Unknown". Acknowledgements gains No-Intro, with the data's date and counts from the file header, and `THIRD_PARTY_NOTICES.md` gains a section quoting the Data Usage License.

## 6. Later, in this order

1. Suggest merging Games already in the library that are one family, reviewed like Suggest Build Names: group every Game's Builds by family and propose a merge for each family split across Games.
2. Match Game... for an unknown ROM or hack: choose a known dump as its base, stored on the Build as the dump's canonical name, so the Build groups with that family without the base ROM being owned; offer to link the base when it is imported later. This is the first part needing a column.
3. Regional artwork and the cross-region save check, which read the Build's region as already stored.
4. Signed downloadable updates, once there is a host and a key.

## Tests

- Generator: made-up exports with a root, clones of clones, a bad copy, a file listed twice, a scene-only game, an aftermarket game, a game with no file and a missing parent produce the expected JSON; a shared file and swapped exports each fail.
- `KnownDumpIndex`: lookups, families, titles and verification against a small in-test file.
- Analyzer and review: a known dump takes its canonical name; a clone joins its parent's Game; two Games holding family members make it a choice; a higher-ranked region proposes the title and Preferred; an unknown hash behaves as today.
- Parser corpus: the added No-Intro flags.

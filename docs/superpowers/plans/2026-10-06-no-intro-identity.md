# No-Intro Identity Plan

**Goal:** Recognize known Game Boy and Game Boy Color dumps by hash, take their canonical names, and group a family's regional releases under one Game, from data bundled with the app.

The decision behind this plan is "The game database is No-Intro's, bundled, and refreshed by hand" in `docs/decisions.md`. The specs it serves are `dec 17` and `dec 18`, Q156 and Q157, and "Regional releases and No-Intro families".

## 1. The data

DAT-o-MATIC's Parent/Clone XML DAT lists each dump as a `game` element with a `description`, a `cloneof` attribute on clones naming the parent, one `release` element per region, and a `rom` element carrying `name`, `size`, `crc`, `md5`, `sha1` and, for bad dumps, `status="baddump"`. It has no `sha256`; the standard DATs have it for only some dumps, 838 of 2,040 Game Boy Color ones in the 2026-10-06 data. Two files are needed: "Nintendo - Game Boy" (system 46) and "Nintendo - Game Boy Color" (system 47), with Aftermarket included.

`Scripts/generate-known-dumps.py <gb.xml> <gbc.xml> <output>` writes one JSON file:

- a header: the source, each system's DAT version and dump count, and the day it was generated;
- one record per dump, one per line: `sha1`, `name` (the canonical name without extension), `size`, `system` (`gb` or `gbc`), `parent` (the parent's name, absent on a parent), `regions` (the release regions, in the DAT's order) and `bad` when No-Intro marks it a bad dump.

Records sort by `sha1`, so two runs over the same input give the same bytes. The script refuses a clone whose parent is missing, a hash that appears twice, and the two files swapped. A dump without a SHA-1 can't be matched, so it is left out and listed. The script prints what changed against the file already committed: dumps added, removed and renamed.

The file lives at `Packages/EmulatorKit/Sources/GameIdentity/Resources/KnownDumps.json`. `GameIdentity` is a new target that depends only on `EmulatorDomain` and processes its resources, like `SameBoyAdapter`. A test checks that the bundled file loads, that every parent resolves, and that the header's counts match the records.

Refreshing: download the two P/C XML files from DAT-o-MATIC in a browser (Download, P/C XML, the system, Prepare, Download), run `make known-dumps GB=<file> GBC=<file>`, read the printed changes, and open a pull request. The pull request body is the printed summary. Nothing fetches from DAT-o-MATIC: see the decision.

## 2. Lookups

`KnownDumpIndex` loads the file once and answers:

- `dump(sha1:)`: the record for a hash;
- `family(of:)`: the parent and every clone of a dump's family, the dump included;
- `title(of:)`: the part of the canonical name before its first tag, which the family's releases share only within a region;
- `verification(of:sha1:lookup:)`: Verified when the Build's SHA-1 is a known dump, Bad Dump when that dump is marked bad, Modified when the Build is patched from a Verified Build, Unknown otherwise.

`SHA1Digest` computes SHA-1 with CryptoKit on Apple platforms and a portable implementation elsewhere, as `SHA256Digest` does.

The parser in `Importing` reads the canonical name as it reads a filename: `FilenameMetadataParser.parse(filename: dump.name + ".gb")` gives the title, region, language, revision and status flags, the Build name and the normalized filename. Flags the parser does not know yet, `Proto`, `Sample`, `Unl`, `Aftermarket`, `Pirate`, `Virtual Console` and numbered betas, are added to its status vocabulary so canonical names parse cleanly; the corpus test gains them.

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

- Generator: a fixture P/C XML with a parent, two clones, a multi-region release and an aftermarket dump produces the expected JSON; a missing parent, a missing hash and a repeated hash each fail.
- `KnownDumpIndex`: lookups, families, titles and verification against a small in-test file.
- Analyzer and review: a known dump takes its canonical name; a clone joins its parent's Game; two Games holding family members make it a choice; a higher-ranked region proposes the title and Preferred; an unknown hash behaves as today.
- Parser corpus: the added No-Intro flags.

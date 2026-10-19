# Backlog

What's built and what's left of `docs/product.md`, which says what each item means. Update an
item's row when its status changes, and move it to its area's "Done" line when it's finished.
Targets are releases: v1.0, v1.1, v2.0 or later. v2.0 is a planning target for the larger
roadmap; its final scope and timing are not fixed.

## Release scope

- **v1.0:** the initial App Store candidate, build 110 at `3c4a76f`, submitted for review.
  `app-store-review/1.0-build-110` identifies that candidate. The stable release follows
  publication on the App Store. Submission tags follow `docs/testflight.md`.
- **v1.1:** work completed after build 110. This includes revised branding and app icons;
  the Model setting and hardware-family checks; automatic artwork previews, missing-artwork
  review, provenance and grouped Library settings; Game Boy Camera with Photo! DX color
  capture; Playtiles landscape controls and compatibility checks; and the fixes listed below.
  ZIP globals attachment is being reviewed separately for this release.
- **v2.0:** the larger unfinished roadmap, including save migration, broader multi-asset
  import, documents, rewind, skins, sync and catalog services. Partial rows describe what
  is already built and what remains for this target.

The v1.1 fixes cover import names and matching after restore, exported-name round trips,
Recently Played placing new imports at the top, empty-library game links, backup outcome
placement, menu ordering and dismissal, on-screen buttons resuming a paused game, and saving
shared screenshots to Photos. A capability already present in v1.0 keeps that initial target
in its table row; this list records its v1.1 updates.

## Suggested order

The v1.1 release follows the submitted v1.0 candidate. The larger open roadmap targets v2.0.

The MVP is complete and working. Its device checklist remains a regression record.

Library backend first: everything that decides how the library is stored, identified and kept
safe lands before more play features, so a library built while testing never needs regrouping or
migrating later.

1. Identity and ROM-hack naming are built. Bundled No-Intro data,
   hash matching, family grouping, regional proposals, reviewed family merges and Match Game
   with absent-base lineage are built. "No-Intro data" in `docs/product.md` describes the behavior.
2. Multi-signal development-build matching is built. Metadata provenance,
   Metadata Details and per-step patch input hashes are built, along with Game aliases, rename,
   Build notes, per-Build playtime, favorites, declared save compatibility and the cross-region save check.
3. Library features on that data are built: sorting, play statistics, the storage screen,
   verification on read, cache trimming under storage pressure and in-flight protection.
4. Library Backup export, reviewed merge restore, automatic safety backup before whole-library
   replacement, retained reports and Game packages are built on the settled schema. ROMs are
   optional, backups up to 2 GB carry a library with its ROMs, and archives use documented
   domain JSON with checksums. Backups have no password. Save and ROM exports and the Files
   folder are built.

The rest of the v1.0 core is built: save state slots, naming and cleanup, crash recovery, reopening
the last game, Restart and Start Over, the controller's Menu button, and per-Build Game Genie and
GameShark cheats.

Game Boy Camera, including Photo! DX color capture, is built for v1.1. Its physical-camera checks
remain pending in `docs/mvp-verification.md`.

v1.0 also includes clean screenshot sharing and artwork from a game frame chosen in the menu.
The v1.1 artwork work adds automatic Libretro lookup after import and a reviewed manual
check. The rest waits for v2.0: 7z and multi-asset import, additional artwork providers and documents with the
manual reader, rewind, slow motion, frame advance and Quick Actions, Super Game Boy borders,
shaders and the layout editor with skin import,
a screenshot gallery and gameplay notes, external displays, tags and collections, iCloud sync once the schema has
settled, the Community Catalog and metadata providers, crash reporting and usage counts, Developer
Mode, editable patch stacks, the Build timeline and comparison screen, in-game Build switching,
RTC offsets, rumble routing, Undo, core updates, and the internal registries and descriptors.

## Known bugs

None known.

## Inventory by area

Open items in each area are in the table, finished ones on the line under it.

### Platform / app shell

| Status | Item | Target | Notes |
|---|---|---|---|
| partial | TestFlight then App Store release path (signing, rights, disclosures gate) | v1.0 | TestFlight upload on every main build; a GitHub pre-release adds its build to the public group and submits it for Beta App Review, with notes since the previous release (docs/testflight.md); the initial app and Plus purchase are submitted for App Store review; approval and final release remain manual |
| done | Timed States, a Plus feature | v1.0 | Off or every 1/2/5/10 minutes of running wall time, inherited at App/System/Game/Build; shares Auto State history and pinned retention, stops without Plus, and excludes Quick Play. Clock, persistence, backup and app tests cover it; device check in docs/mvp-verification.md |
| done | Minimal first-launch onboarding (Import, Quick Play, saves/storage, opt-ins) | v1.0 | a one-time welcome screen covers the library, Builds, saves, Quick Play, the game menu and exports, and Settings reopens it; the first game shows "Tap Press Any for the menu" once. v1.0 has nothing to opt into: crash reports and usage counts (v2.0) bring their own opt-in screens, and Developer Mode its introductions |
| missing | Developer Mode toggle (Advanced -> Developer Mode) gating dev tools | v2.0 | none |
| done | Landscape gameplay | v1.0 | Gameplay-only rotation and the inheritable Orientation setting (Automatic, Portrait, Landscape); Game Boy uses a safe-area-aware GBA layout with the menu centered horizontally between the bezel and screen edge, its bottom aligned with the bezel, and a taller viewport. Playtiles fits two clockwise-turned 40 mm bodies and their guides close to the game picture, with at least eight points of clearance. Each compact T-shaped guide joins the original center indent nub to rounded shoulders above and below it, long enough to extend past the Dynamic Island. Both bodies stay inside the phone's edges, reducing the picture when needed, with the menu centered beneath it and remapped buttons (right D-pad Up/Right = A, Left/Down = B). Library and sheets stay portrait. Geometry and input regressions cover both layouts; updated device checks are pending |
| missing | Root docs CONTRIBUTING/SECURITY/PRIVACY/CoC/trademark, DCO signoff | v2.0 | only LICENSE, THIRD_PARTY_NOTICES.md, AGENTS.md, README.md |
| partial | App Store screenshots and previews from homebrew and the original test ROMs only, no third-party game art or logos | v1.0 | Screenshots are uploaded for the initial submission. The manual workflow defaults to the 6.3-inch iPhone 17 Pro and verifies its App Store Connect dimensions; 6.9-inch and 6.5-inch sets are also available (docs/testflight.md). An app preview is optional |

Done: Press Any Plus through StoreKit 2 with price, Buy, Restore Purchases and retry, configured
in App Store Connect, with stand-in app tests and completed physical-device checks; LCD filters,
app icon colorways and Auto State history gated at every scope, retaining stored choices without
Plus; A Press Any folder in Files holding Exports, with the library kept in Application Support and
an empty share Inbox removed at launch; iOS 17.4 minimum; iPhone-first, iPad not deliberately broken; Light + dark appearance;
Offline-first core; Naming: display name only from Info.plist, brand-free IDs; Wordmark (rounded
Corporatus artwork, pink "A" and navy lettering) in library toolbar and controller body; Shared pink/navy/gray
app colors; App icon (smooth front-facing button in a closed oval well with a centered A below; six colorways,
light/dark/tinted and matching previews);
Acknowledgements screen listing code, artwork and data with credits and license notices.

### Architecture seams


| Status | Item | Target | Notes |
|---|---|---|---|
| partial | Registries for platforms, cores, image analyzers, toolchain detectors, patch formats | v2.0 | CoreRegistry + ToolchainDetectorRegistry exist; no platform or analyzer registry; patch formats dispatched by file extension in PatchStackApplier |
| missing | PlatformDescriptor / HardwareDescriptor / DistributionDescriptor / CompatibilityRecord (core target + hardware target) | v2.0 |  |
| missing | Input and memory descriptors | v2.0 |  |

Done: Neutral platform IDs `gb`/`gbc`; Generic `GameImage`/`PersistentSave` contracts.

### Cores

| Status | Item | Target | Notes |
|---|---|---|---|
| missing | Nonintrusive "core update available" notice | v2.0 | none |
| missing | Explicit, reversible core-migration checkpoint (new state lineage, rollback when old core available) | v2.0 | none |
| done | Automatic model selection | v1.0 | CGB flag 0x80/0xC0 -> GBC, else DMG (`HardwareModel.resolved`); SGB never chosen automatically |
| done | Model setting (Plus) at App->System->Game->Build | v1.1 | `hardwareModel`: DMG, MGB, SGB, SGB2, CGB, AGB, GBP, each with its own boot ROM; an open game restarts on a changed Model when its settings close; states refused across hardware families name the models they need and aren't offered by Resume Games; Game Boy Advance Colors shows a GBA game as a GBC would (`advanceColors`); Quick Play uses Automatic. Device check pending |
| partial | SGB mode: palettes, borders, game enhancements (custom border editing deferred) | v2.0 | SGB and SGB2 color the picture; the border (a 256x224 picture) isn't drawn yet |
| missing | Automatic picks Super Game Boy features for games with the SGB flag | v2.0 | after the border is drawn. Read and store the header's SGB flag (0x146 = 0x03). A Game Boy game with it runs on SGB2 under Automatic. A Game Boy Color game with it stays on GBC and shows its SGB border through SameBoy's `GB_BORDER_ALWAYS`, which captures the border on a hidden SGB run, so it plays in full color inside the border (Dragonyhm does this). The Game Boy Player has no SGB border, so it isn't the default for either. A game moved to SGB2 can't load its earlier Game Boy states, so the change needs a plan for them |
| missing | User-chosen alternate core per Build | later |  |
| missing | mGBA/GBA adapter | later | after GB/GBC is feature complete |

Done: SameBoy 1.0.3 GB/GBC behind `EmulatorCore`, no SameBoy types leak; Latest compatible core on
first launch, then pinned per Build; Open SameBoy boot ROMs incl. cgb_boot_fast; Skip Boot Logo:
Quick Play always, library via inheritable setting (default shows logo); Optional capability
protocols: rumble, boot skipping, cheats and camera input implemented; rewind, memory access, RTC,
link cable and printer declared, and a missing one is a failed cast. Accuracy test ROMs: Blargg's
tests and the Mooneye Test Suite run through the bridge on DMG-B and CGB-E in CI whenever the core
or bridge changes, against recorded results; every test for those models passes except Mooneye's
boot_div, boot_hwio and boot_sclk_align, likely because SameBoy's open boot ROMs don't hand off on
the same cycle as Nintendo's. Screenshot suites (dmg-acid2, cgb-acid2, Mealybug Tearoom, Blargg's
halt_bug, interrupt_time and sound tests) and SameSuite remain.

### Persistence / storage

| Status | Item | Target | Notes |
|---|---|---|---|
| done | Storage screen by category, source vs disposable, safe cleanup | v1.0 | Settings > Library > Storage shows asset categories, Quick Play disk usage and device free space; confirmed cache clearing preserves the running Build's ROM; Recently Deleted has no separate total because purgeable assets cannot be listed without purging |
| done | GC coordination / in-flight protection / orphan sweep in the running app | v1.0 | `InFlightFiles` holds files an import, patched Build or variable map places until they're recorded, and a running game's ROM; the launch resolver holds every image it resolves, a patched Build's bases included, and `readImage` holds one until it's read, which export, the save check, toolchain refresh, patch matching and Technical Info use; cache trimming, cache clearing and Check Library Files skip held files, and the sweep looks each orphan up again before removing it. Launch cleanup runs before anything can start |

Done: GRDB/SQLite metadata, binaries on managed FS; SHA-256 identity, content-addressed collision-
safe relative paths; Source-asset dedup; Source vs userData vs cache vs temporary classes; Atomic
save/state writes; Transactional commit, no orphaned permanent asset on failure; Verify important
assets when read or used: launch rehashes the ROM and patches, battery saves and save states are
checked against their recorded SHA-256 before they reach the core, and Check Library Files rehashes
ROMs and patches on demand; Automatic cleanup of disposable data only: expired Quick Play sessions
and staged copies left by interrupted imports go at launch, and patched ROMs are trimmed, least
recently played first, when less than 500 MB is free, at launch and before a patched ROM is written.

### Domain model

| Status | Item | Target | Notes |
|---|---|---|---|
| done | Game aliases/alternate titles (indexed) | v1.0 | normalized indexed alias table in one identity migration; family titles added at import; library search matches aliases, including "Pocket Monsters Crystal" for Pokémon Crystal; FTS5 remains separate |
| done | Metadata source/confidence/provenance + user overrides, Metadata Details UI | v1.0 | Technical Info opens each field's value, source, confidence, date and offered value; edits and Use Offered Value keep the player source and the earlier offer; provenance follows restructuring and deletion |
| done | Presentation-metadata editing (rename Game/Build after creation) | v1.0 | Rename Game in Game Details preserves the former title as an alias and protects the player title; Rename Build; Suggest Names reviews Game titles and Build names, retaining old Game titles as aliases |
| partial | Build toolchain record, variable-map sidecars, artwork/doc overrides, activation history | v1.0 (toolchain and sidecars were MVP) | toolchain reports and variable maps done; artwork/doc overrides and activation history missing |
| done | Build notes | v1.0 | one plain-text note, shown and edited in Build Details; whitespace preserved; clear or cancel edits; notes follow moved and copied Builds; FTS5 note search comes later |
| done | Per-Build playtime | v1.0 | session time added to Build and Save Profile together on background and close, without double counting; shown in Build Details and Game rollups; a separate statistics screen comes later |
| missing | Documents model (Game/Build/both; Manual/README/Changelog/Guide/Map/Other) | v2.0 |  |
| missing | Typed multi-artwork model with primary selection | v2.0 | Game.artworkAssetID is a single image |
| missing | Tags and collections | v2.0 |  |

Done: Game: UUID, primary title, system family, preferred Build/Profile, timestamps; Build: UUID,
gameID, system, concise name, immutable hash, sourceKind, parent lineage, Base marker, preferred
profile, core pin; SaveProfile: name, current save, ancestry, playtime/session count/last
played/created; SaveState exact context (Build + Profile + core + serialization version), playtime,
label, kind; Build region/language/revision/version suggested from recognized filename tags,
nonzero header revision fallback without a No-Intro match, editable or clearable at import (including Quick Play promotion),
numeric version sort key and Technical Info display; PatchRecipe: exact base, ordered items, enabled flag, expected hash, Apply-Anyway flag;
ManagedAsset: hash, kind, length, relative path, original filename, provenance, integrity.

### Library

| Status | Item | Target | Notes |
|---|---|---|---|
| missing | Optional Developer view (Build/version/profile details) | v2.0 |  |
| missing | Manual collections/folders | v2.0 |  |
| missing | Smart collections (GB, GBC, Homebrew, ROM Hacks, Favorites, Recently Played, Builds with updates) | v2.0 |  |
| missing | Tags on Games/Builds via long-press/overflow | v2.0 |  |
| done | Sorting | v1.0 | remembered Sort By in the More menu: title, recent play, added, last Build change, playtime, system, hack author, Build version and date, and manual order; Recently Played uses the later of date added and last played so new imports appear at the top; list second lines follow the sort; Reorder drags Games in the list under Manual, positions survive Recently Deleted; release year/developer/publisher move to v2.0 with metadata providers |
| missing | Sorting by release year, developer and publisher | v2.0 | needs the metadata provider chain for its data |
| done | Multi-select deletion | v1.0 | Select in library grid/list, Game Builds and Save Profiles, Save States, Quick Play Sessions and Recently Deleted; one confirmation with skipped counts and reasons, separate restorable entries, and dependency-ordered Restore |
| done | Favorites | v1.0 | Game Details toolbar star and library long-press menu beside Rename; small star on tiles/list rows; Favorites Only works with search; merge keeps either favorite and promotion carries it |
| done | Play statistics | v1.0 | Game rollups of Build playtime and profile session counts/latest last played in Game Details; played profiles show playtime and last played; Recently Deleted rows excluded; refresh on library changes and game close; a separate statistics screen remains later work |

Done: Box-art grid and compact list; Game detail with Builds and Save Profiles; Preferred Build
one-tap Play; explicit choice never silently changed; Build switch from Game detail; long-press to
play another Build/Save; Build preferred Save Profile falling back to Game preferred.

### Search

| Status | Item | Target | Notes |
|---|---|---|---|
| missing | SQLite FTS5 live index (aliases, filenames, hack title/author/version, system, region, Build names, tags, doc titles) with title-first ranking | v2.0 | no FTS table; v1.0 searches titles and aliases |

Done: Search by primary title and Game aliases.

### ROM identity, naming, metadata

| Status | Item | Target | Notes |
|---|---|---|---|
| done | Automatic No-Intro / ROM-hack naming and structured fields | v1.0 | conservative filename suggestions, hack/base titles, authors, translation/status, confidence and concise Build names are implemented across ROM import, Quick Play promotion and patch-created Builds; the parser recognizes numbered development flags and Sample, Kiosk and Debug, drops Aftermarket and Unl, and reads GoodTools names: short regions, versions, dump codes and `[T+Eng1.03_Group]` translations; dates in joined names and No-Intro's `(2000-02-21)` name the Build, and every exported name reads back as the same fields; a repeated name gains the date the Build was added; Suggest Names reviews existing Build names and regional Game titles |
| missing | Filename parsing tuned against a broader real-world corpus | v2.0 |  |
| done | Header read/validate/display, no editing | v1.0 | GBROMHeaderParser validates header + global checksum; Import Review shows the checksum warning and a Build's Technical Info shows a read-only Header section: title, color support, named cartridge type, ROM and RAM size, revision number, and both checksums as Valid or Invalid |
| done | Normalized No-Intro / ROM-hack filename suggestion | v1.0 | shown in Import Review and used for ROM export: No-Intro's name for a known dump with GoodTools' `[!]` or `[b]`, otherwise No-Intro order and spelling, with a hack's own bracket and GoodTools' translation tag for modifications; original filenames are kept, and renaming the stored file is the v2.0 row below |
| missing | Explicit "Rename File to Canonical Name" (bulk later) | v2.0 | physical renaming is an explicit action |
| missing | Signed/validated downloadable database updates | v2.0 | needs a host and a signing key; the bundled file already carries its date |
| done | Hash match on import: canonical name, region, language, revision and status come from the matched dump, ahead of the filename, with the source shown | v1.0 | matched by SHA-1; a known dump takes its canonical name, region, language, revision and status from the matched data; development statuses (Beta, Proto, Demo, Sample, Debug) are spelled as the filename parser spells them, and Aftermarket, Unl and Pirate describe the release, so they are never a status |
| done | Parent/clone grouping: a release joins its family's Game automatically when unambiguous, even with a different regional title, shown in Import Review before commit; weaker matches are suggestions; regrouping stays possible | v1.0 | one family Game is suggested; several require a choice; regional title and Preferred proposals are confirmed in Import Review |
| done | Suggest merging Games already in the library that are one No-Intro family, reviewed like Suggest Names | v1.0 | Settings > Library review selects Games, survivor and title; confirmation uses the existing merge path, preserving lineage, profiles, states and artwork; overlapping images refused before moving a group |
| done | Preferred region and language order (App setting, USA, Europe, Japan by default) choosing a Game's display title among its releases and which regional Build defaults to Preferred | v1.0 | Settings > Library > Regions and Languages supports reordering both lists; better regional title and Preferred mark are separate import proposals; ties stay put; player titles and preexisting titles without provenance are protected during import; Suggest Names preserves recorded player titles, including adopted patch and hack titles, allows titles without provenance to opt into the regional title order on acceptance, and leaves skips and Preferred Builds unchanged |
| done | Match Game... for unknown ROMs, lineage without owning the base, link base later | v1.0 | explicit library and bundled No-Intro search in Import Review; records the base title, system and known family/release without a ROM; a later base import offers the destination and Base mark; manual matching leaves verification Unknown |
| done | Multi-signal development-build matching, never silently attach | v1.0 | stored bank fingerprints, unique header and whole-title/alias evidence, hardware and toolchain support rank candidates; high confidence preselects, medium keeps New Game selected, review explains the evidence and Import confirms the destination |
| partial | Quiet provider metadata refresh never overwriting user overrides | v2.0 | No-Intro refreshes matched Builds at launch when each system's bundled version changes; player fields, missing provenance and names stay protected; other providers remain |

Done: SHA-256 identity for every ROM; Original imported filename preserved permanently; the bundled
No-Intro data (both systems' DB exports, aftermarket releases included) with its generator, manual
refresh and 90-day CI reminder; Verified / Bad Dump / Modified / Unknown in Technical Info, never
altering a ROM.

### Import

| Status | Item | Target | Notes |
|---|---|---|---|
| done | Files default-open handling with another emulator installed | v1.0 | Owner/Viewer declarations for .gb/.gbc/.ips/.bps; cited Delta, Provenance, SameBoy and RetroArch ROM identifiers accepted (see product.md, Shared files); hosted app test covers rank, role, extensions and identifiers; the Files tap and Share > Press Any checks passed on device alongside another emulator; iOS chooses the default between claiming apps |
| partial | ZIP + 7z with archive safety (size limits, traversal, password detect) | v2.0 | shared zips open each ROM, patch and save inside, read in memory with the system zlib (stored and deflate, per-kind size limits, CRC checked, encrypted and Zip64 refused; other entries and links skipped); 7z remains |
| missing | Multi-asset analysis/grouping (ROMs, patches, saves, art, manuals, README/changelog, variable maps, skins) | v2.0 |  |
| partial | Duplicate ROM still inspects new saves/art/manuals/patches | v2.0 | duplicate path only repairs the blob |
| partial | Visual artwork comparison (existing/fetched/packaged) in review | v2.0 | manual Check for New Artwork shows current and fetched images; Import Review shows the automatic proposal in its second section; packaged comparison remains |
| missing | Import while playing -> "New Build Ready" Switch Now/Later; Developer "Restart into New Build" | v2.0 |  |
| missing | Multiple ROMs attached to one Game in one flow | v2.0 |  |

Done: Share Sheet / Open In for ROMs, patches and `.sav`/`.srm` saves, with the Quick Play or
Import choice on open, a Game/base Build choice for patches and a Game choice for saves; Owner rank with Viewer copy imports, imported format
declarations only, and compatibility identifiers from the public plists cited in product.md;
Analyze -> ImportPlan -> Review -> transactional Commit; Game artwork from Photos or Files in
Import Review, with an automatic proposal in the second section and a per-import opt-out; Files picker for .gb/.gbc; .sav and
.ips/.bps from Game detail; Exact duplicate: no second blob/Build, shows it's already there,
re-import repairs damaged file; New Game vs Add Build choice, reviewable Base/Preferred suggestions
(a file No-Intro doesn't know defaults to both unless its version is older than the Base's;
No-Intro releases keep an existing Base; ROM hacks default Preferred only); Toolchain
findings in Import Review and Quick Play promotion; Files over a size limit for their kind
(ROM, patch, save, artwork, variable map) refused before they are read or staged; only regular
files staged. Review suggests the Game holding a Build with the same header title, and a
mid-name "v5" or "0.3.0" word in a hyphenated or underscored filename becomes the version.

### Game/Build restructuring

| Status | Item | Target | Notes |
|---|---|---|---|
| partial | Import-Review-style inheritance step (artwork, docs, tags, compatible profiles; deselectable) on promote/merge | v1.0 (mvp says merge "with review") | review sheet copies artwork and chosen Save Profiles; docs and tags don't exist yet |
| missing | Lightweight Build timeline (versions, hashes, parents, notes, import/activation history) | v2.0 |  |
| partial | Build comparison (changed bytes/ranges, size, banks, header) | v2.0 | the comparison engine and its tests are in Importing; the Build Details screen remains |

Done: Make Separate Game: Move/Copy, default Move, Build UUID/blob preserved, Build-scoped data
follows; Merge into Game: Move/Copy, lineage/recipes remapped; Same image already in target: Copy
skips, Move refused naming the Builds; Profiles/artwork/preferences follow when the source Game is
emptied or merged away; Promoted Game records the Game it split from (Split From), kept by title
once that Game is gone; Mark or unmark imported Builds as Base Builds after import, with a new Base
automatically replacing the previous one; rename a Build from its long-press menu.

### Patching

| Status | Item | Target | Notes |
|---|---|---|---|
| missing | Editable stacks UI: reorder/enable/disable/add/remove -> new Build | v2.0 |  |
| missing | Patch base by region: when a patch expects another regional release already in the Game, such as USA when Europe was chosen, review offers that Build | v2.0 | a fan translation of a Japanese release joins the family's Game through its base |
| partial | Pluggable patch-format architecture | v2.0 | switch on extension, no registry |
| missing | Patch metadata with confidence/provenance (catalog > README > filename) | v2.0 |  |
| missing | BPS generation from base vs modified Build | v2.0 |  |
| missing | Quick Play a patch against a base without creating a Build | future |  |
| done | Expected input hash on every step of a patch stack; review shows expected and selected hashes when they differ | v1.0 | Enabled steps record their input SHA-256; rebuilds stop at a mismatched step and show both hashes. Technical Info lists all steps. BPS Apply Anyway warnings compare sizes and CRC32s. |

Done: IPS (RLE, truncate) and BPS (CRC checks) engines; Preserve base ROM, original patch, recipe,
result hash; Base validation; explicit Apply Anyway persisted for rebuilds; Patch result is a new
immutable Build with lineage; Generated ROM is cache: evict, rebuild, verify hash; Ordered
multi-patch recipe (multi-select applies a stack); Unsupported formats identified and reported.

### Save system: battery saves and profiles

| Status | Item | Target | Notes |
|---|---|---|---|
| partial | Compatibility-aware Build switching (flush, analyze, risky -> migrate/duplicate/use anyway/blank) | MVP and v1.0 | launch check offers copy/new save/use anyway; migrate waits for v2.0 GB Studio migration |
| missing | GB Studio save migration (version-gated, needs maps) | v2.0 |  |
| missing | RTC: real time + per-profile manual offset; Developer RTC controls | v2.0 | SameBoy's internal RTC runs, no offset; the offset goes in the profile's stored `rtcContextJSON` |
| missing | Save Profile locking | later |  |
| done | Cross-region save check: launching a Build whose region or language differs from the Build that last wrote the profile warns, since many games' saves don't carry across languages | v1.0 | same risky-launch prompt names both releases; requires a writer and both regions, compares languages when both are recorded; Shares Saves clears the warning |
| done | Declared save compatibility between Builds (known to share, known not to), used by the launch check | v1.0 | symmetric pairs; Always Use Saves Between These Builds records a share and launches; Build Details adds, replaces and swipe-removes either choice; Shares Saves skips the prompt, Doesn't forces it; Move keeps pairs, Copy gets none; Recently Deleted hides and restores them, purge removes them |

Done: One .sav per Save Profile, atomic flush synced to storage; In-game saves written during play
once changed, at most every five seconds of play and off the frame-pacing queue; Compatible Builds
share a profile on purpose; New
blank profile; duplicate profile (bytes copied, ancestry shown); Import .sav into a new profile,
or into an existing one after confirming, keeping its old save as "<name> before import";
Variable maps (GB Studio globals, RGBDS .sym, GBDK .noi) kept on the exact Build; Each profile
records the Build that last wrote it, and launching another Build warns when the save may not fit
(declared non-share, different regions or languages, GB Studio, different detected tools or
different header save hardware, unless declared to share); Save Profile badge, one
emoji shown beside its name; Delete a profile, with a confirmation naming it, taking its save and
states.

### Save system: states and lifecycle

| Status | Item | Target | Notes |
|---|---|---|---|
| done | Quick Save (one tap) | v1.0 | One replaceable Quick State per Build + Save Profile; Quick Load uses the existing load checks; rename, delete and restore in Save States |
| done | Configurable fixed slots | v1.0 | App-only Off/3/5/10; replacement preserves name and pin; restore/reassign collisions become manual |
| done | Unlimited named states | v1.0 | Optional Name New States prompt; rename and delete in Save States |
| done | Configurable automatic cleanup; pinned/favorited exempt | v1.0 | Manual All/10/25/50 to Recently Deleted; Auto 3/5/10 with Plus, or the latest one without, pruned permanently at each Auto State write; pins exempt and restored manual states pinned under a limit |
| missing | State records cheat config; offer Restore Cheat Configuration | v2.0 |  |
| missing | Per-Save-Profile autoresume override | v2.0 |  |
| done | Separate crash-recovery checkpoint + Recover Session / Start Normally | v1.0 | One hidden state per Build and Save Profile, refreshed each minute of play; clean close or Auto State removes it. An open-session marker offers recovery without automatic launch; Start Normally keeps the checkpoint until that Build launches |
| done | Restart from the game menu; Start Over from the library | v1.0 | Restart asks first, keeps the battery save through a core reset and, for a library game, an Auto State of the moment left; Start Over boots from the save whatever Resume Games says, keeping the resume point |
| done | App relaunch returns to the previous game/session | v1.0 | A library game saved in the background reopens with Resume Games (Always, Ask or Never); a closed game stays closed, and Quick Play is excluded |
| missing | In-game Build/Profile switching (save, check, relaunch) | v2.0 |  |

Done: Basic manual save + load state (menu hides crash checkpoints); States
never cross Build/Profile/core/serialization context; Auto State on background, close and session
switch; configurable retention (default 5); Resume Games Always/Ask/Never (default Always),
inheritable System/Game/Build, Ask prompt, foreground policy; Auto State not restored once the profile's save is newer; Failed
restore boots normally, keeps state, tells user; Backgrounding pauses emulation/audio; One active
emulator session; Each state keeps a PNG thumbnail of its frame, shown in Load State; A failed
battery write still saves the Auto State, and a failed close can be retried or closed without
saving; Loading a state older than the profile's save warns and keeps the save as "<name> before
loading state"; A separated Build's states follow it to the profile copies it plays.

### Quick Play

| Status | Item | Target | Notes |
|---|---|---|---|
| missing | Configurable retention Immediately / 24 h / 7 d | v2.0 |  |
| partial | Session artifacts | v2.0 | battery + autosave kept; manual states ("Save states aren't kept in Quick Play"), a screenshot gallery, notes, debug captures and their transfer on promotion missing |
| missing | Background hash/identify/toolchain detection for Quick Play | v2.0 | not run |

Done: Temporary sandbox, no library mutation until promotion; Time-to-first-frame path: read once,
validate, copy, hash; boot past logo (cgb_boot_fast); no optional assets; "First frame in N ms"; Use
an existing save by copying it in; source never written; Promotion via Import Review: keep / replace
after safety copy / new profile / discard save; Recent Quick Plays list with Keep/Import/Discard and
resume from autosave, skipped once the battery save is newer; Add to Library keeps the autosave as
the Build's Auto State; 24 h default retention, expired sessions purged.

### Cheats and memory tools


| Status | Item | Target | Notes |
|---|---|---|---|
| missing | Pluggable verified-ROM cheat database, selective add, never auto-enable | v2.0 |  |
| missing | Cheat groups/categories + search | v2.0 |  |
| missing | Cheat search: exact/unknown/changed/unchanged/inc/dec/delta/greater/less, signed/unsigned 8/16-bit, hex | v2.0 |  |
| missing | Result actions: edit, freeze, watch, create cheat, copy address | v2.0 |  |
| missing | Named search sessions within current emulation session | v2.0 |  |
| missing | Memory Watch list + optional Developer HUD + short history/min/max/graph | v2.0 |  |
| missing | Developer Mode performance overlay: frame time, dropped frames and audio underruns, recorded on the slowest supported iPhone as the device performance check | v2.0 |  |
| missing | Immediate Developer Mode memory writes with Undo Last Write, frozen indication | v2.0 |  |
| missing | Frame advance + frame counter (bindable) | v2.0 |  |
| missing | Developer Mode audio channel mute and solo: Pulse 1, Pulse 2, Wave and Noise toggles on the game menu's Sound page, for checking a hUGETracker or GB Studio track | v2.0 | SameBoy has `GB_set_channel_muted` and `GB_is_channel_muted`, so the audio side is a few calls; session-only, reset when the game closes so a game never comes back silent; could be offered outside Developer Mode for a player a harsh channel bothers |
| missing | Full debugger/disassembler/VRAM viewer | later |  |

Done: Cheat management add/remove/enable/disable/persist in Game Genie and GameShark formats, v1.0:
`CheatCapability` on the SameBoy adapter through SameBoy's own parser; cheats per Build in
`build_cheats` with a Cheats On switch per Build; Cheats in the game menu and the Build's menu;
applied at launch and mid-game; carried by Library Backup and Game packages. SameBoy's own cheat
file format isn't imported.

### Screenshots, notes, debug context

Done: Share Screenshot in the game menu's Capture submenu exports a clean native-size PNG from
library games and Quick Play through the system share sheet, leaves gameplay paused and removes
the temporary file after sharing. Free, with no gallery or capture metadata.

| Status | Item | Target | Notes |
|---|---|---|---|
| missing | In-app screenshot gallery tied to exact Build; export/share to Photos | v2.0 |  |
| missing | Export presets Clean / Build Info / Bug Report with rendered info strip and metadata fields | v2.0 |  |
| missing | Optional atomic Capture Context (watches, named vars, memory ranges, registers, frame/time, Build/hash/patches, RTC, cheats, profile, core/settings) | v2.0 |  |
| missing | Full-RAM snapshot (opt-in, Developer Mode) | v2.0 |  |
| missing | Bug-report export (Markdown/JSON) with privacy checklist/preview | v2.0 | lands in the Files folder, with any memory or save captures the player includes |
| missing | Game notes, timestamped gameplay notes with attachments | v2.0 | plain-text Build notes are built |

### Rewind and speed

| Status | Item | Target | Notes |
|---|---|---|---|
| missing | Rewind, presets 5 s/15 s/30 s/1 m/2 m/5 m, memory-budgeted, effective duration shown, muted by default (optional audio), survives brief background | v2.0 | no RewindCapability |
| partial | Fast-forward | MVP basic / v2.0 full | menu toggle at the Fast Forward Speed setting (1.5x/2x/3x/4x/8x/Unlimited, default 2x, inheritable, changes live from the game menu's Settings); Fast Forward Audio setting Muted (default) or Accelerated up to 4x; hold vs toggle waits for Quick Actions |
| missing | Slow motion 0.25x/0.5x/0.75x | v2.0 |  |

Done: Pause / Resume from menu with paused overlay; any fresh non-directional controller button
or on-screen A, B, START or SELECT press resumes the exposed overlay and is consumed until
released. Directional input leaves it paused.

### Rendering, shaders, display

| Status | Item | Target | Notes |
|---|---|---|---|
| done | Free built-in palettes for original Game Boy games | v1.0 | Twelve button-combo palettes and six game palettes (Mole Mania, Link's Awakening, Super Mario Land, Super Mario Land 2, Donkey Kong Land and Game Boy Camera), alongside DMG/Pocket/Light; grouped palette list with color names, combo subtitles and BG/OBJ0/OBJ1 previews, one Black & White choice; display-only DMG rendering; Skip Boot Logo on/off; scoped Screen Colors lists, including in-game Settings |
| missing | Custom Game Boy palettes and GBC game-palette selection | v2.0 | Specify separate background/OBJ0/OBJ1 colors, enter a GBC boot-ROM palette combination number (such as 17), or select a recognized game (such as Mole Mania) to use its built-in colors; include color previews |
| done | Adaptive presentation on high-refresh displays | v1.0 | CADisplayLink on its own thread runs the frames owed at 59.73 Hz and presents the newest, up to 120 Hz on ProMotion; Low Power Mode or a serious or critical thermal state caps presentation at 60 Hz, applied live from the system's change notifications; the Low Power Mode device check passed |
| partial | Curated display/shader set (LCD 1×, LCD 3×, Pixel Transparency, DMG/GBC LCD, sharp bilinear, CRT/scanlines); BuiltIn + CommunityDownload catalog with license/hash checks | v2.0 | LCD 1× pixel grid and LCD 3× RGB subpixel effects implemented as Press Any's own code, modelled on the libretro LCD shaders and credited to them; remaining effects and catalog missing; each shader that ships is credited by author in Acknowledgements and `THIRD_PARTY_NOTICES.md` |
| partial | Shader components/params inherit independently; named user presets; live switching via Quick Actions | v2.0 | LCD effect and frame blending inherit App → System → Game → Build independently of scaling, and change live from the game menu's Settings; named presets and Quick Actions switching missing |
| missing | Custom crop / other aspect options | v2.0 |  |
| missing | Thermal-aware degradation of optional work | v2.0 |  |
| missing | Arbitrary .slang/.slangp import; shader preset file import/export | later |  |

Done: Framebuffer -> Metal texture presentation; native core timing paces frames; Screen Scaling
Integer (default, whole device pixels, nearest) / Fill (10:9, edge-blended), inheritable; Frame
Blending Off (default) / Blend / LCD Ghosting, inheritable; Screen Colors lists per system, also
accessible from in-game Settings: Game Boy Green (DMG, default) / Olive (Pocket) / Teal (Light),
twelve free button-combo boot palettes (including Black & White), and six game palettes
(Mole Mania, Link's Awakening, Super Mario Land, Super Mario Land 2, Donkey Kong Land and Game
Boy Camera); color names and background/sprite thumbnails,
Game Boy Color Balanced (default) / Accurate / Boost Contrast / Reduce Contrast / Low Contrast /
Original. Both inherit App -> System -> Game -> Build, with the lists from System down, update
the open picture from Settings, and survive reset and state loads.

### Layouts, skins, touch

| Status | Item | Target | Notes |
|---|---|---|---|
| done | Consistent touch D-pad diagonal sectors | v1.0 | Game Boy portrait and landscape and Playtiles share a 0.67 weaker/stronger axis ratio, about 22.5° per diagonal and 67.5° per cardinal; dead zones and hit areas stay unchanged. Angle regression tests cover both styles and orientations; the thumb-sliding check passed on device |
| done | Playtiles physical fit requirement | v1.1 | Requires a 68 mm-wide screen, checked by native iPhone screen class (short edge at least 1242 pixels), independent of rotation and Display Zoom. App and scoped pickers disable it on narrower phones; saved choices use Game Boy without being rewritten. Package and app compatibility regressions pass; additional physical-device checks remain |
| missing | Minimal / Fullscreen / one-handed presets | v2.0 |  |
| missing | GameBaby preset; per-accessory/device calibration screen | v2.0 |  |
| missing | Lightweight editor: screen/control position+size, opacity, hitboxes, portrait/landscape, control styles, save preset | v2.0 |  |
| missing | Edit Layout from gameplay on a frozen frame; Save for This Game vs Update Shared Preset | v2.0 |  |
| missing | Native layout import/export via Files/Share | v2.0 |  |
| missing | Delta + Manic skin import adapters, source package kept, unsupported-element report, no silent mis-map | v2.0 |  |
| missing | Optional customizable gestures (off by default) | v2.0 |  |
| missing | Turbo A / Turbo B actions (not in default layout) | v2.0 |  |
| missing | Suggest (never force) a preset for identifiable accessories | v2.0 |  |
| missing | Controller-covered layouts (Playtiles and any later one): the app's screens fit the visible top of the screen and are navigable with the controller's buttons | v2.0 | today only gameplay knows the controller covers the bottom; the library and sheets use the whole screen |
| missing | Full skin artwork authoring; community layout gallery | v2.0 / later |  |

Done: Built-in "Game Boy" layout measured from DMG-01, default, inheritable; Built-in "Playtiles"
from the Delta skin frames, portrait START/SELECT swapped, alignment guide, and two sideways tiles
with separate guides and duplicate button inputs in landscape; Controller themes Classic
/ Dark / Match System (app-wide), status bar follows; Tap wordmark opens the game menu, with or
without a controller (44 pt), optional Tap Game for Menu (off), one-time hint, VoiceOver Game Menu
button; Touch Haptics Off / Light / Medium (Light), off while a controller hides the controls; Sliding D-pad with
diagonals, sliding A/B, multitouch A+B; Subtle pressed-state visuals.

### Controllers and rumble

| Status | Item | Target | Notes |
|---|---|---|---|
| partial | Multiple controllers, choose Player 1, reserve Player 2 | v2.0 | first connected used; selectPlayerOne() has no UI |
| done | Controller Menu opens and closes the game menu | v1.0 | Menu opens the game menu with no combo; pressing it again closes and resumes, including with touch controls hidden. X or PlayStation Triangle stays START; Y or Square stays SELECT; Home is never taken |
| missing | Rumble routing override Phone / Controller / Both / Off | v2.0 |  |
| missing | Separate phone and controller intensity | v2.0 |  |

Done: Apple GameController input (extendedGamepad), D-pad and left thumbstick with a radial dead
zone and eight equal sectors; A and B by the controller's letters (Circle = A and Cross = B on PlayStation),
Menu opens the game menu and closes it with Resume; any non-directional button resumes the exposed pause overlay;
X = START, Options or Y = SELECT (Triangle and Square on PlayStation), shoulders free; iOS controller customizations, including per-app ones, are the only button mapping; Connected controllers use Game
Boy and follow Orientation even with Playtiles chosen; Disconnect releases input, restores the
chosen layout, pauses and shows a notice without restarting; A controller hides the touch
controls, a touch brings them back until its next button press, and Settings can keep them;
Cartridge rumble routed controller-first, phone fallback. Physical-device customization checks
passed and remain as regression coverage in mvp-verification.md.

### Quick Actions

| Status | Item | Target | Notes |
|---|---|---|---|
| missing | One shared action registry for menu, controller hotkeys and skin buttons | v2.0 |  |
| missing | Reorderable/customizable Quick Actions with favorites | v2.0 |  |
| missing | Remaining actions: rewind, slow-mo, screenshot, note, manual, cheats, shader, Build/Profile switch, Build info, watches, frame advance, layout edit | v2.0 |  |

Done: In-game menu from the wordmark with or without a controller: Pause/Resume, Fast Forward,
Save State, Load State and Close; Quick Play offers Add to Library and explains disabled Save State.
Close and Add to Library wait for the menu's dismissal animation to finish before leaving gameplay.

### Manuals / documents


| Status | Item | Target | Notes |
|---|---|---|---|
| missing | PDF, CBZ, PNG/JPEG/WebP sets, TXT, Markdown as managed copies | v2.0 |  |
| missing | Game/Build/both association with semantic types, default manual | v2.0 |  |
| missing | In-game overlay reader: pauses, restores prior run/pause state, remembers last-read position | v2.0 |  |
| missing | Text search in TXT/MD/text PDFs if simple; no OCR | v2.0 |  |
| missing | iPad side-by-side; bookmarks/annotations/OCR | v2.0 |  |

### Artwork

| Status | Item | Target | Notes |
|---|---|---|---|
| done | Automatic fetch on import + setting to disable | v1.1 | Libretro lookup after import and Quick Play promotion; default on; preserves existing artwork and in-flight player choices; duplicates skip lookup |
| partial | Provider chain: local/imported, Community Catalog, OpenVGDB (experimental), Libretro thumbnails, SteamGridDB (user key), title-screen fallback | v2.0 | pluggable provider port and Libretro box art built; chosen Photos/Files artwork wins; remaining providers missing; OpenVGDB still blocked by its data license |
| partial | Priority manual -> hack-specific -> inherited base (recorded as inherited) -> generated | v2.0 | existing artwork is preserved; verified and confirmed base inheritance is recorded; hack-specific and generated priority missing |
| missing | Automatic artwork generated from the Game's title screen | v2.0 | Detect the title screen while running the game after import; manual selection from the current frame is built |
| missing | Build-level artwork override | v2.0 |  |
| partial | Regional artwork: lookups use the Build's region, and a Game's primary artwork follows the preferred region | v2.0 | lookups use the preferred recognized No-Intro release and same-release revision fallback; automatic primary changes by region require typed artwork |
| missing | Multiple typed assets (box front/back, cart, title, screenshots, logo, fan) | v2.0 |  |
| missing | Non-destructive crop/reposition | v2.0 |  |
| done | Manual "Check for New Artwork"; cache only selected primary | v1.1 | current/fetched preview with explicit Use Artwork and Cancel; works with automatic lookups off; no persistent HTTP cache |
| done | Grouped Library settings | v1.1 | one Library page with Preferences, Organization, Files, and Backup and Restore; Artwork contains its import setting and the Find Missing Artwork review |
| done | Find Missing Artwork across the library | v1.1 | Settings > Library > Artwork; includes Games hidden by search/filters; progress, image previews and per-Game acceptance before saving; Cancel discards temporary proposals; works with import-time lookups off; preserves existing artwork; proposes previously removed artwork for explicit acceptance; newer choices and removals during search or review win |
| done | Artwork provenance (provider, URL, fetch time, rights) | v1.1 | kept in ManagedAsset.provenanceJSON with inherited base name; backup/restore and artwork copies preserve it |

Done: Use Current Frame as Artwork in the game menu's Capture submenu for library games,
confirming before replacing existing artwork; whole-image library tiles with sharp pixels;
Manual artwork from Photos/Files, remove, stored as user data, downscaled to 1024 pixels;
title placeholder fallback; Artwork follows Builds when a Game is emptied by promote/merge.

### External display / AirPlay


| Status | Item | Target | Notes |
|---|---|---|---|
| missing | Independent external render target (not mirroring); wired displays | v2.0 |  |
| missing | Phone as controller companion keeping Quick Actions/manual/states/Build switching | v2.0 |  |
| missing | Display-specific scaling/aspect/shader/safe area; modes game-only/minimal HUD/mirror | v2.0 |  |

### iCloud


| Status | Item | Target | Notes |
|---|---|---|---|
| missing | Sync all library state except ROM blobs | v2.0 | stable UUIDs exist, nothing else |
| partial | Tombstones; offline devices cannot resurrect | v2.0 | local tombstones are kept for good; sync must check them |
| missing | Field-level merge where safe | v2.0 |  |
| missing | Divergent .sav preserved, explicit resolution, split into new profile | v2.0 |  |

### Community Catalog


| Status | Item | Target | Notes |
|---|---|---|---|
| missing | Signed catalog file read offline: Game and Build metadata, expected hashes, lineage, patch download locations, no ROMs; nothing else depends on it | v2.0 |  |
| missing | Opt-in anonymous read; lightweight identity to contribute; optional attribution | after v2.0 | hosted service |
| missing | Moderated submissions, trust layers, structured evidence, rejection reasons | after v2.0 | hosted service |
| missing | Field-level corrections; "Suggest This Correction" after local edit, never auto-submit | after v2.0 | hosted service |
| missing | Metadata, artwork, legal patch references/uploads; no ROM hosting | after v2.0 | hosted service; the v1.0 file carries references |
| missing | Update discovery: quiet badge, optional verified pre-download, per-Game override, details | after v2.0 |  |
| missing | Update import as new Build via normal review, old kept for rollback | after v2.0 |  |
| missing | Backend (PostgreSQL/Supabase-shaped), CC0 factual metadata policy | after v2.0 |  |

### Metadata databases

| Status | Item | Target | Notes |
|---|---|---|---|
| missing | Bundled offline identity baseline + validated downloadable updates | v2.0 |  |
| missing | Pluggable metadata provider chain (canonical -> online -> catalog -> user override) | v2.0 |  |
| missing | Separate opt-in homebrew/ROM-hack catalog with provenance | v2.0 |  |

### Backups and migration


| Status | Item | Target | Notes |
|---|---|---|---|
| done | Export/import Library Backup | v1.0 | Settings export sheet, progress, zip restore picker and shared-file routing; domain records and manual positions; 2 GiB streamed archives, size check before export; package and GRDB tests |
| done | Export one Game as a package in the Library Backup format: its Builds' patches and recipes, Save Profiles, states, artwork, documents and notes, ROMs only when asked; importing it merges like a restore | v1.0 | Game Details export, patch-base dependencies and reviewed merge; current schema has no documents model |
| done | Documented versioned archive: manifest, ordinary files, checksums, schema version | v1.0 | docs/backup-format.md; format v1, migration ID, every payload checksummed; newer versions refused |
| done | ROMs excluded by default, explicit personal full-backup option | v1.0 | Include ROMs defaults off; personal-backup footer; missing ROM rows restore and duplicate import repairs files |
| not planned | Optional password encryption | none | Backups have no password. The manifest's encrypted flag stays so an archive marked encrypted is refused before changes |
| done | Merge restore by stable IDs/hashes with conflict review; Replace Entire Library | v1.0 | Per-item choices and independent save copies; Recently Deleted and purged records left alone; automatic safety backup with ROMs before destructive confirmation; atomic commit and rollback tests |
| done | Migration Report before commit + retained summary | v1.0 | Review before writes, report after commit, Settings > Library > Last Restore retained in the database |
| missing | Delta/Manic/Afterplay/Playtiles import adapters | future |  |

Done: Export Save writes a Save Profile's battery save as a .sav named for the Game and profile;
Export ROM writes a Build's ROM, rebuilt first when patched, under its canonical name; both land in
Files without replacing an earlier export.

### Deletion and undo


| Status | Item | Target | Notes |
|---|---|---|---|
| partial | Synchronized tombstones | v2.0 | purging writes a permanent local tombstone; syncing them waits on iCloud |
| missing | Lightweight Undo for recent structural operations | v2.0 |  |

Done: Dependency-aware deletion: the confirmation names patched Builds and emptied Games that go
too, and a Game can't go while another Game's patch is built from it; Recently Deleted for 30
days in Settings, with Restore and Delete Now, purged at launch; Delete Game, Build, Save Profile
and save state from the UI, a save state from its profile's Save States; swipe to delete on Build,
Save Profile and save state rows and to discard a Quick Play session, asking first as the menus do.

### Performance

| Status | Item | Target | Notes |
|---|---|---|---|
| done | Audio interruptions pause safely; route changes don't restart the game | v1.0 | the game pauses whenever its scene goes inactive (calls, Siri, Control Center); an audio interruption that leaves the scene active, and an output device going away, pause it too and leave it paused until Resume; the physical-device checks passed |
| missing | Thermal-aware degradation | v2.0 |  |
| missing | Default shader sustains full speed on minimum QA device | v2.0 | LCD 1x and LCD 3x are built and their device checks passed; the wider curated shader set is not built |

Done: Native timing authoritative; audio never sets game speed; Sound setting: Follow Silent Switch
(default) / Always On / Always Off; Low-latency adaptive audio (40 ms target growing to 160 ms
after shortfalls); frames run on the display refresh at native speed, up to 120 Hz, or 60 Hz in
Low Power Mode or under heat.

### Privacy and telemetry

| Status | Item | Target | Notes |
|---|---|---|---|
| missing | Opt-in crash reporting limited to non-content diagnostics | v2.0 | no crash reporting at all |
| missing | Opt-in anonymous usage counts (Games, Builds per Game, Save Profiles used by several Builds, Quick Play sessions added to the library), never titles, hashes, filenames or contents | v2.0 | endpoint or provider and privacy copy not chosen; PRIVACY.md and the App Store privacy answers change with it |
| missing | Explicit bug-report export with checklist/preview | v2.0 |  |
| partial | Accurate privacy/consent copy for provider queries and catalog; keys server-side/secure storage | v2.0 | Libretro release-name/network-address disclosure and disable setting built; other providers, catalog and keys pending |

Done: ROMs, saves, screenshots, memory, imported filenames and notes stay local. Artwork queries
send canonical release names, with disclosures in Settings and the privacy policy.

### Accessibility


| Status | Item | Target | Notes |
|---|---|---|---|
| missing | Expanded VoiceOver pass | v2.0 | Baseline library and game-menu labels are built and device-checked; narrated gameplay is not planned |
| missing | Dynamic Type for on-screen controls | v2.0 | Normal management UI supports Dynamic Type and passed device checks; controller drawing remains fixed size |
| missing | Reduce Motion support | v2.0 | none |
| partial | Large/configurable touch targets | v2.0 | hit areas extend 10-12 pt beyond drawn controls; not configurable |
| missing | One-handed layouts | v2.0 | none |
| missing | Controller navigation | v2.0 | none; button remapping is iOS's Game Controller settings |

Done: VoiceOver labels for library and game-menu management, Dynamic Type in the normal UI,
with completed device checks; Good contrast / color-independent states; haptics never sole feedback.

### Settings inheritance

Nothing open.
| missing | Narrow Save Profile overlay (cheats, RTC, autoresume, rewind) | v2.0 |  |

Done: Resolver App -> System -> Game -> Build, only explicit overrides stored, inherited source
shown, Reset to Inherited; Implemented keys; Settings screens for App, System (Game Boy, Game Boy
Color), Game and Build; App Settings as Display, Controls and Playing pages with Systems pages, Library
and About lists, and the scoped form grouped the same way with each setting's source under its
name.

### SDK / toolchain detection


Nothing open.

Done: Standalone detector seam + gbtoolsid port (engines, toolchains, music/SFX drivers,
version/range, evidence, detector version, corpus revision), differential CI vs upstream; GB Studio
detection, including 4.3+ by version, multi-layer (GB Studio over GBDK + audio driver); Categorical
confidence; Runs on import and patching, stored per Build, shown in Import Review, promotion and
Technical Info (which detects again); Quick Play detects on demand in its Technical Info and at
Add to Library, never before the first frame; Feeds the save compatibility check.

### Included Games


| Status | Item | Target | Notes |
|---|---|---|---|
| missing | Optional Included Games manifest (ID, hashes, licenses, permission record, releaseApproved gate) imported through the normal path | v2.0 |  |

### CI / generated pipelines


| Status | Item | Target | Notes |
|---|---|---|---|
| done | Data and audit pipelines: no-intro-update, toolchain-fingerprints-update, fixtures, license-audit, privacy-audit | v1.0 | No-Intro data stays a human refresh by policy, with a CI reminder at 90 days and generator tests; toolchain detection is checked against gbtoolsid on every push; `verify-repo-hygiene.sh` checks the test-ROM manifest; the iOS build verifies the privacy manifest; `verify-third-party-notices.py` fails when a pinned dependency or submodule commit is missing from THIRD_PARTY_NOTICES.md. shader-catalog-update and included-games-verify arrive with shaders and included games in v2.0; openvgdb-update stays disabled |
| partial | MVP gate | MVP | package tests cover required tests 1-13 and 15, and an app test covers 14 (controller disconnect); every physical-iPhone (L4c) check is unchecked |

Done: ci.yml (L1/L2/L3, gbtoolsid differential, test-coverage, hygiene) and ios-build.yml (simulator
build/tests).

### v2.0 targets


| Status | Item | Target | Notes |
|---|---|---|---|
| missing | Link cable, local dual-core first; nearby/SharePlay initiation; no Multipeer | v2.0 | no LinkCableCapability |
| missing | GB Studio save migration with old/new variable maps | v2.0 |  |
| missing | Game Boy Printer with preview/save/share | v2.0 | no PrinterCapability |
| missing | RAR import (tentative) | v2.0 |  |
| missing | Visual skin/layout authoring beyond the lightweight editor | v2.0 |  |
| missing | Video/GIF capture; screenshots and clips framed like a Game Boy, shared from the game menu | v2.0 | saved recordings also land in the Files folder |
| missing | Browse and download games: itch.io's Game Boy tag in an in-app browser and Homebrew Hub (hh.gbdev.io) by its API, from the library's + menu; downloads go straight to Import Review, with Quick Play | v2.0 | needs zip import; extend privacy disclosures for these providers and confirm App Store guideline 4.7 wording |
| missing | Share an itch.io game page or GitHub page to download and import a ROM | v2.0 | web-URL share extension; resolve supported ROM downloads, choose when several exist, then Import Review or Quick Play; safe ZIP extraction; preserve itch.io's normal purchase/login flow |
| missing | `.gbproject`-style project import/export | v2.0 |  |
| missing | Better ROM comparison + BPS generation | v2.0 |  |
| missing | iPad side-by-side manual/game | v2.0 |  |

Done: Game Boy Camera (v1.1): rear camera by default for camera cartridges in library play and
Quick Play, with a scoped Game Boy Camera setting (Rear, Front, Off) and a game-menu switch for
the session; permission when a camera game opens, neutral-gray fallback, orientation and
front mirroring, capture stopped on pause/inactivity/close, and photos kept by the normal save
path. Photo! DX's version-1 RGB handshake provides automatic color with a frozen source across
the three exposures. Synthetic cartridge, adapter, session, camera-policy and sampling tests
cover the path; real Photo! DX RGB capture, color gallery pixels and battery reloads pass on
the CGB and AGB bridge models (evidence in `docs/mvp-verification.md`).
Apple SDK, simulator integration and physical-camera checks remain in `docs/mvp-verification.md`.

### Later


| Status | Item | Target | Notes |
|---|---|---|---|
| missing | Developer tools: a watched Files or iCloud Drive folder whose new ROMs import as new Builds; GitHub releases or CI builds as Builds; a tester bug report bundle (save, state, screenshot, Build hash, toolchain) | later |  |
| missing | iOS integration: Continue Playing widget, Siri and Shortcuts ("Resume <game>"), Spotlight | later |  |
| missing | Network/internet link; RetroAchievements; full debugger/disassembler/VRAM; deterministic replay/movies; arbitrary .slang/.slangp; Apple TV/macOS/iPad-first polish; creator-controlled homebrew publishing; document annotations/OCR/bookmarks; community layout gallery; battery-saver mode; per-Build alternate core choice; bulk canonical rename | later |  |

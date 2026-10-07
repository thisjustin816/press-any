# Backlog

What's built and what's left of `docs/product.md`, which says what each item means. Update an
item's row when its status changes, and move it to its area's "Done" line when it's finished.
Targets are releases: v1, v1.1 or later.

## Suggested order

Nothing below is in progress.

The MVP is complete and working. Its device checklist remains a regression record.

Library backend first: everything that decides how the library is stored, identified and kept
safe lands before more play features, so a library built while testing never needs regrouping or
migrating later.

1. Identity: the ROM-hack naming and metadata-source work that remains. Bundled No-Intro data,
   hash matching, family grouping, regional proposals, reviewed family merges and Match Game
   with absent-base lineage are built. "No-Intro data" in `docs/product.md` describes the behavior.
2. The rest of the data model, in as few schema migrations as possible: metadata provenance with
   Metadata Details, Build notes, per-Build playtime, favorites, declared save compatibility,
   per-step patch input hashes, and the cross-region save check. Game aliases and rename are built.
3. Multi-signal development-build matching, the one import item left in v1.
4. Library features on that data: FTS5 search, sorting, play statistics, and the storage screen
   with cleanup, in-flight protection and verification on read.
5. Exports, last of the library work because their format follows the settled schema: Library
   Backup export and import (versioned archive, ROMs left out unless asked, merge restore by
   stable IDs) and a whole Game as a package in the same format. Save and ROM exports and the
   Files folder they land in come first, as they don't depend on the schema.
6. The rest of the v1 core: Quick Save and save state slots, crash recovery, reopening the last
   game, and a fixed controller combo for the game menu.

v1 is a good core experience; everything else waits for v1.1: ZIP, 7z and multi-asset import,
artwork and documents with the manual reader, rewind, slow motion, frame advance and Quick
Actions, the DMG/GBC/SGB model override, shaders and the layout editor with skin import,
screenshots and notes, external displays, tags and collections, iCloud sync once the schema has
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
| partial | TestFlight then App Store release path (signing, rights, disclosures gate) | v1 | TestFlight upload on every main build; a GitHub pre-release adds its build to the public group and submits it for Beta App Review, with notes since the previous release (docs/testflight.md); App Store submission, listing, review and rights gate not started |
| missing | Paid/IAP seam `FeatureEntitlementProvider` (StoreKit kept out of Domain) | v1.1 | none |
| partial | Minimal first-launch onboarding (Import, Quick Play, saves/storage, opt-ins) | v1 | a one-time welcome screen covers the library, Builds, saves, Quick Play, the game menu and exports, and Settings reopens it; opt-ins and contextual introductions remain, besides the one-time "Tap Press Any for the menu" hint |
| missing | Developer Mode toggle (Advanced -> Developer Mode) gating dev tools | v1.1 | none |
| partial | Landscape gameplay | v1 | Gameplay-only rotation, a safe-area-aware GBA layout and the inheritable Orientation setting (Automatic, Portrait, Landscape) are implemented; Playtiles without a connected controller and sheets stay portrait. Physical-device rotation lock, cutout and controller checks remain in mvp-verification.md |
| missing | Root docs CONTRIBUTING/SECURITY/PRIVACY/CoC/trademark, DCO signoff | v1.1 | only LICENSE, THIRD_PARTY_NOTICES.md, AGENTS.md, README.md |
| missing | App Store screenshots and previews from homebrew and the original test ROMs only, no third-party game art or logos | v1 | the Screenshots workflow already seeds from `TestROMs/` |

Done: A Press Any folder in Files holding Exports, with the library kept in Application Support and
an empty share Inbox removed at launch; iOS 17.4 minimum; iPhone-first, iPad not deliberately broken; Light + dark appearance;
Offline-first core; Naming: display name only from Info.plist, brand-free IDs; Wordmark (heavy
italic, magenta "A") in library toolbar and controller body; App icon (A button; light/dark/tinted);
Acknowledgements screen listing SameBoy + GRDB with full licenses.

### Architecture seams


| Status | Item | Target | Notes |
|---|---|---|---|
| partial | Registries for platforms, cores, image analyzers, toolchain detectors, patch formats | v1.1 | CoreRegistry + ToolchainDetectorRegistry exist; no platform or analyzer registry; patch formats dispatched by file extension in PatchStackApplier |
| missing | PlatformDescriptor / HardwareDescriptor / DistributionDescriptor / CompatibilityRecord (core target + hardware target) | v1.1 |  |
| missing | Input and memory descriptors | v1.1 |  |

Done: Neutral platform IDs `gb`/`gbc`; Generic `GameImage`/`PersistentSave` contracts.

### Cores

| Status | Item | Target | Notes |
|---|---|---|---|
| missing | Nonintrusive "core update available" notice | v1.1 | none |
| missing | Explicit, reversible core-migration checkpoint (new state lineage, rollback when old core available) | v1.1 | none |
| partial | Automatic model selection | v1.1 | CGB flag 0x80/0xC0 -> CGB, else DMG (SameBoyAdapter.loadImage); SGB never chosen |
| missing | Model override DMG/GBC/SGB at App->System->Game->Build | v1.1 | no setting key |
| missing | SGB mode: palettes, borders, game enhancements (custom border editing deferred) | v1.1 | no SGB model/boot ROM in bridge |
| missing | User-chosen alternate core per Build | later |  |
| missing | mGBA/GBA adapter | 1.2 or 2.0 | after GB/GBC is feature complete |

Done: SameBoy 1.0.3 GB/GBC behind `EmulatorCore`, no SameBoy types leak; Latest compatible core on
first launch, then pinned per Build; Open SameBoy boot ROMs incl. cgb_boot_fast; Skip Boot Logo:
Quick Play always, library via inheritable setting (default shows logo); Optional capability
protocols: rumble and boot skipping implemented, rewind, cheats, memory access, RTC, link cable,
camera and printer declared, and a missing one is a failed cast.

### Persistence / storage

| Status | Item | Target | Notes |
|---|---|---|---|
| missing | Storage screen by category, source vs disposable, safe cleanup | v1 | none |
| partial | Automatic cleanup of disposable data only | v1 | expired Quick Play sessions and staged copies left by interrupted imports removed at launch (AppContainer init); no generated-cache eviction under pressure |
| partial | GC coordination / in-flight protection / orphan sweep in the running app | v1 | Check Library Files runs the orphan sweep on demand; in-flight protection and GC coordination remain |

Done: GRDB/SQLite metadata, binaries on managed FS; SHA-256 identity, content-addressed collision-
safe relative paths; Source-asset dedup; Source vs userData vs cache vs temporary classes; Atomic
save/state writes; Transactional commit, no orphaned permanent asset on failure; Verify important
assets when read or used: launch rehashes the ROM and patches, battery saves and save states are
checked against their recorded SHA-256 before they reach the core, and Check Library Files rehashes
ROMs and patches on demand.

### Domain model

| Status | Item | Target | Notes |
|---|---|---|---|
| done | Game aliases/alternate titles (indexed) | v1 | normalized indexed alias table in one identity migration; family titles added at import; library search matches aliases, including "Pocket Monsters Crystal" for Pokémon Crystal; FTS5 remains separate |
| partial | Metadata source/confidence/provenance + user overrides, Metadata Details UI | v1 | filename source/confidence and editable import suggestions exist; full provider provenance and Metadata Details UI remain |
| done | Presentation-metadata editing (rename Game/Build after creation) | v1 | Rename Game in Game Details preserves the former title as an alias and protects the player title; Rename Build; Suggest Names reviews Game titles and Build names, retaining old Game titles as aliases |
| partial | Build toolchain record, variable-map sidecars, notes, per-Build playtime, artwork/doc overrides, activation history | v1 (toolchain and sidecars were MVP) | toolchain reports and variable maps done; the rest missing |
| missing | Documents model (Game/Build/both; Manual/README/Changelog/Guide/Map/Other) | v1.1 |  |
| missing | Typed multi-artwork model with primary selection | v1.1 | Game.artworkAssetID is a single image |
| missing | Tags and collections | v1.1 |  |

Done: Game: UUID, primary title, system family, preferred Build/Profile, timestamps; Build: UUID,
gameID, system, concise name, immutable hash, sourceKind, parent lineage, Base marker, preferred
profile, core pin; SaveProfile: name, current save, ancestry, playtime/session count/last
played/created; SaveState exact context (Build + Profile + core + serialization version), playtime,
label, kind; Build region/language/revision/version suggested from recognized filename tags,
nonzero header revision fallback, editable or clearable at import (including Quick Play promotion),
numeric version sort key and Technical Info display; PatchRecipe: exact base, ordered items, enabled flag, expected hash, Apply-Anyway flag;
ManagedAsset: hash, kind, length, relative path, original filename, provenance, integrity.

### Library

| Status | Item | Target | Notes |
|---|---|---|---|
| missing | Optional Developer view (Build/version/profile details) | v1.1 |  |
| missing | Manual collections/folders | v1.1 |  |
| missing | Smart collections (GB, GBC, Homebrew, ROM Hacks, Favorites, Recently Played, Builds with updates) | v1.1 |  |
| missing | Tags on Games/Builds via long-press/overflow | v1.1 |  |
| partial | Sorting | v1 | title only; recent/added/playtime/release year/system/developer/publisher/hack author/Build version/last Build change/manual order missing |
| missing | Favorites | v1 |  |
| partial | Play statistics | v1 | profile playtime, session count, last played recorded but never displayed; per-Build playtime, Game rollups, play count, last played on Game missing |

Done: Box-art grid and compact list; Game detail with Builds and Save Profiles; Preferred Build
one-tap Play; explicit choice never silently changed; Build switch from Game detail; long-press to
play another Build/Save; Build preferred Save Profile falling back to Game preferred.

### Search

| Status | Item | Target | Notes |
|---|---|---|---|
| missing | SQLite FTS5 live index (aliases, filenames, hack title/author/version, system, region, Build names, tags, doc titles) with title-first ranking | v1 | no FTS table |

Done: Search by primary title and Game aliases.

### ROM identity, naming, metadata

| Status | Item | Target | Notes |
|---|---|---|---|
| partial | Automatic No-Intro / ROM-hack naming and structured fields | v1 | conservative filename suggestions, hack/base titles, authors, translation/status, confidence and concise Build names are implemented across ROM import, Quick Play promotion and patch-created Builds; the parser recognizes numbered development flags and Sample, Kiosk and Debug, and drops Aftermarket and Unl; a repeated name gains the date the Build was added; Suggest Names reviews existing Build names and regional Game titles; broader real-world corpus tuning remains |
| partial | Header read/validate/display, no editing | v1 | GBROMHeaderParser validates header + global checksum; shown only in Import Review, not in Build details |
| partial | Normalized No-Intro / ROM-hack filename suggestion | v1 | generated and shown during import while original filenames remain preserved; explicit physical rename remains separate |
| missing | Explicit "Rename File to Canonical Name" (bulk later) | v1.1 | physical renaming is an explicit action |
| missing | Signed/validated downloadable database updates | v1.1 | needs a host and a signing key; the bundled file already carries its date |
| partial | Hash match on import: canonical name, region, language, revision and status come from the matched dump, ahead of the filename, with the source shown | v1 | matched by SHA-1; a known dump takes its canonical name, region, language and revision through the filename parser; status flags such as Aftermarket and Unl are not parsed yet |
| done | Parent/clone grouping: a release joins its family's Game automatically when unambiguous, even with a different regional title, shown in Import Review before commit; weaker matches are suggestions; regrouping stays possible | v1 | one family Game is suggested; several require a choice; regional title and Preferred proposals are confirmed in Import Review |
| done | Suggest merging Games already in the library that are one No-Intro family, reviewed like Suggest Names | v1 | library view-menu review selects Games, survivor and title; confirmation uses the existing merge path, preserving lineage, profiles, states and artwork; overlapping images refused before moving a group |
| done | Preferred region and language order (App setting, USA, Europe, Japan by default) choosing a Game's display title among its releases and which regional Build defaults to Preferred | v1 | Settings > Library > Regions and Languages supports reordering both lists; better regional title and Preferred mark are separate import proposals; ties stay put; player titles and preexisting titles without provenance are protected during import; Suggest Names opts into the regional title order on acceptance, protects edits, leaves skips and Preferred Builds unchanged |
| done | Match Game... for unknown ROMs, lineage without owning the base, link base later | v1 | explicit library and bundled No-Intro search in Import Review; records the base title, system and known family/release without a ROM; a later base import offers the destination and Base mark; manual matching leaves verification Unknown |
| partial | Multi-signal development-build matching, never silently attach | v1 | exact hash/family and whole-title, alias, header or hack-base suggestions exist; broader development signals and confidence ranking remain |
| missing | Quiet provider metadata refresh never overwriting user overrides | v1.1 |  |

Done: SHA-256 identity for every ROM; Original imported filename preserved permanently; the bundled
No-Intro data (both systems' DB exports, aftermarket releases included) with its generator, manual
refresh and 90-day CI reminder; Verified / Bad Dump / Modified / Unknown in Technical Info, never
altering a ROM.

### Import

| Status | Item | Target | Notes |
|---|---|---|---|
| partial | Files default-open handling with another emulator installed | v1 | Owner/Viewer declarations for .gb/.gbc/.ips/.bps; cited Delta, Provenance, SameBoy and RetroArch ROM identifiers accepted (see product.md, Shared files); hosted app test covers rank, role, extensions and identifiers; physical-iPhone tap and Share > Press Any checks pending in mvp-verification.md; iOS chooses the default between claiming apps |
| missing | ZIP + 7z (libarchive) with archive safety (depth/ratio limits, traversal, password detect) | v1.1 |  |
| missing | Multi-asset analysis/grouping (ROMs, patches, saves, art, manuals, README/changelog, variable maps, skins) | v1.1 |  |
| partial | Duplicate ROM still inspects new saves/art/manuals/patches | v1.1 | duplicate path only repairs the blob |
| missing | Visual artwork comparison (existing/fetched/packaged) in review | v1.1 |  |
| missing | Import while playing -> "New Build Ready" Switch Now/Later; Developer "Restart into New Build" | v1.1 |  |
| missing | Multiple ROMs attached to one Game in one flow | v1.1 |  |

Done: Share Sheet / Open In for ROMs and patches, with the Quick Play or Import choice on open
and a Game/base Build choice for patches; Owner rank with Viewer copy imports, imported format
declarations only, and compatibility identifiers from the public plists cited in product.md;
Analyze -> ImportPlan -> Review -> transactional Commit; Game artwork from Photos or Files in
Import Review; Files picker for .gb/.gbc; .sav and
.ips/.bps from Game detail; Exact duplicate: no second blob/Build, shows it's already there,
re-import repairs damaged file; New Game vs Add Build choice, reviewable Base/Preferred suggestions
(development releases default to both; ROM hacks default Preferred only); Toolchain
findings in Import Review and Quick Play promotion; Files over a size limit for their kind
(ROM, patch, save, artwork, variable map) refused before they are read or staged; only regular
files staged. Review suggests the Game holding a Build with the same header title, and a
mid-name "v5" or "0.3.0" word in a hyphenated or underscored filename becomes the version.

### Game/Build restructuring

| Status | Item | Target | Notes |
|---|---|---|---|
| partial | Import-Review-style inheritance step (artwork, docs, tags, compatible profiles; deselectable) on promote/merge | v1 (mvp says merge "with review") | review sheet copies artwork and chosen Save Profiles; docs and tags don't exist yet |
| missing | Lightweight Build timeline (versions, hashes, parents, notes, import/activation history) | v1.1 |  |
| partial | Build comparison (changed bytes/ranges, size, banks, header) | v1.1 | the comparison engine and its tests are in Importing; the Build Details screen remains |

Done: Make Separate Game: Move/Copy, default Move, Build UUID/blob preserved, Build-scoped data
follows; Merge into Game: Move/Copy, lineage/recipes remapped; Same image already in target: Copy
skips, Move refused naming the Builds; Profiles/artwork/preferences follow when the source Game is
emptied or merged away; Promoted Game records the Game it split from (Split From), kept by title
once that Game is gone; Mark or unmark imported Builds as Base Builds after import, with a new Base
automatically replacing the previous one; rename a Build from its long-press menu.

### Patching

| Status | Item | Target | Notes |
|---|---|---|---|
| missing | Editable stacks UI: reorder/enable/disable/add/remove -> new Build | v1.1 |  |
| missing | Patch base by region: when a patch expects another regional release already in the Game, such as USA when Europe was chosen, review offers that Build | v1.1 | a fan translation of a Japanese release joins the family's Game through its base |
| partial | Pluggable patch-format architecture | v1.1 | switch on extension, no registry |
| missing | Patch metadata with confidence/provenance (catalog > README > filename) | v1.1 |  |
| missing | BPS generation from base vs modified Build | v1.1 |  |
| missing | Quick Play a patch against a base without creating a Build | future |  |
| missing | Expected input hash on every step of a patch stack; review shows expected and selected hashes when they differ | v1 | PatchRecipe checks only the base and the result; IPS carries no checksum of its own |

Done: IPS (RLE, truncate) and BPS (CRC checks) engines; Preserve base ROM, original patch, recipe,
result hash; Base validation; explicit Apply Anyway persisted for rebuilds; Patch result is a new
immutable Build with lineage; Generated ROM is cache: evict, rebuild, verify hash; Ordered
multi-patch recipe (multi-select applies a stack); Unsupported formats identified and reported.

### Save system: battery saves and profiles

| Status | Item | Target | Notes |
|---|---|---|---|
| partial | Compatibility-aware Build switching (flush, analyze, risky -> migrate/duplicate/use anyway/blank) | MVP and v1 | launch check offers copy/new save/use anyway; migrate waits for v1.1 GB Studio migration |
| missing | GB Studio save migration (version-gated, needs maps) | v1.1 |  |
| missing | RTC: real time + per-profile manual offset; Developer RTC controls | v1.1 | SameBoy's internal RTC runs, no offset; the offset goes in the profile's stored `rtcContextJSON` |
| missing | Save Profile locking | later |  |
| missing | Cross-region save check: launching a Build whose region or language differs from the Build that last wrote the profile warns, since many games' saves don't carry across languages | v1 | joins the existing launch check; declared save compatibility can clear it |
| missing | Declared save compatibility between Builds (known to share, known not to), used by the launch check | v1 | the launch check only infers today (GB Studio, tools, header save hardware) |

Done: One .sav per Save Profile, atomic flush synced to storage; In-game saves written during play
once changed, at most every five seconds of play and off the frame-pacing queue; Compatible Builds
share a profile on purpose; New
blank profile; duplicate profile (bytes copied, ancestry shown); Import .sav into a new profile,
or into an existing one after confirming, keeping its old save as "<name> before import";
Variable maps (GB Studio globals, RGBDS .sym, GBDK .noi) kept on the exact Build; Each profile
records the Build that last wrote it, and launching another Build warns when the save may not fit
(GB Studio, different detected tools, different header save hardware); Save Profile badge, one
emoji shown beside its name; Delete a profile, with a confirmation naming it, taking its save and
states.

### Save system: states and lifecycle

| Status | Item | Target | Notes |
|---|---|---|---|
| missing | Quick Save (one tap) | v1 | SaveStateKind.quick unused |
| missing | Configurable fixed slots | v1 |  |
| partial | Unlimited named states | v1 | a Save Profile's Save States renames and deletes them; Save State doesn't ask for a name |
| missing | Configurable automatic cleanup; pinned/favorited exempt | v1 |  |
| missing | State records cheat config; offer Restore Cheat Configuration | v1.1 |  |
| missing | Per-Save-Profile autoresume override | v1.1 |  |
| done | Separate crash-recovery checkpoint + Recover Session / Start Normally | v1 | One hidden state per Build and Save Profile, refreshed each minute of play; clean close or Auto State removes it. An open-session marker offers recovery without automatic launch; Start Normally keeps the checkpoint until that Build launches |
| done | App relaunch returns to the previous game/session | v1 | A library game saved in the background reopens with Resume Games (Always, Ask or Never); a closed game stays closed, and Quick Play is excluded |
| missing | In-game Build/Profile switching (save, check, relaunch) | v1.1 |  |

Done: Basic manual save + load state (menu hides crash checkpoints); States
never cross Build/Profile/core/serialization context; Auto State on background, close and session
switch; rolling 5; Resume Games Always/Ask/Never (default Always), inheritable System/Game/Build,
Ask prompt, foreground policy; Auto State not restored once the profile's save is newer; Failed
restore boots normally, keeps state, tells user; Backgrounding pauses emulation/audio; One active
emulator session; Each state keeps a PNG thumbnail of its frame, shown in Load State; A failed
battery write still saves the Auto State, and a failed close can be retried or closed without
saving; Loading a state older than the profile's save warns and keeps the save as "<name> before
loading state"; A separated Build's states follow it to the profile copies it plays.

### Quick Play

| Status | Item | Target | Notes |
|---|---|---|---|
| missing | Configurable retention Immediately / 24 h / 7 d | v1.1 |  |
| partial | Session artifacts | v1.1 | battery + autosave kept; manual states ("Save states aren't kept in Quick Play"), screenshots, notes, debug captures and their transfer on promotion missing |
| missing | Background hash/identify/toolchain detection for Quick Play | v1.1 | not run |

Done: Temporary sandbox, no library mutation until promotion; Time-to-first-frame path: read once,
validate, copy, hash; boot past logo (cgb_boot_fast); no optional assets; "First frame in N ms"; Use
an existing save by copying it in; source never written; Promotion via Import Review: keep / replace
after safety copy / new profile / discard save; Recent Quick Plays list with Keep/Import/Discard and
resume from autosave, skipped once the battery save is newer; Add to Library keeps the autosave as
the Build's Auto State; 24 h default retention, expired sessions purged.

### Cheats and memory tools


| Status | Item | Target | Notes |
|---|---|---|---|
| missing | Cheat management add/remove/enable/disable/persist; Game Genie/GameShark/SameBoy formats | v1.1 | no CheatCapability |
| missing | Pluggable verified-ROM cheat database, selective add, never auto-enable | v1.1 |  |
| missing | Cheat groups/categories + search | v1.1 |  |
| missing | Cheat search: exact/unknown/changed/unchanged/inc/dec/delta/greater/less, signed/unsigned 8/16-bit, hex | v1.1 |  |
| missing | Result actions: edit, freeze, watch, create cheat, copy address | v1.1 |  |
| missing | Named search sessions within current emulation session | v1.1 |  |
| missing | Memory Watch list + optional Developer HUD + short history/min/max/graph | v1.1 |  |
| missing | Immediate Developer Mode memory writes with Undo Last Write, frozen indication | v1.1 |  |
| missing | Frame advance + frame counter (bindable) | v1.1 |  |
| missing | Full debugger/disassembler/VRAM viewer | later |  |

### Screenshots, notes, debug context


| Status | Item | Target | Notes |
|---|---|---|---|
| missing | In-app screenshot gallery tied to exact Build; export/share to Photos | v1.1 |  |
| missing | Export presets Clean / Build Info / Bug Report with rendered info strip and metadata fields | v1.1 |  |
| missing | Optional atomic Capture Context (watches, named vars, memory ranges, registers, frame/time, Build/hash/patches, RTC, cheats, profile, core/settings) | v1.1 |  |
| missing | Full-RAM snapshot (opt-in, Developer Mode) | v1.1 |  |
| missing | Bug-report export (Markdown/JSON) with privacy checklist/preview | v1.1 | lands in the Files folder, with any memory or save captures the player includes |
| missing | Game notes, Build notes, timestamped gameplay notes with attachments | v1.1 |  |

### Rewind and speed

| Status | Item | Target | Notes |
|---|---|---|---|
| missing | Rewind, presets 5 s/15 s/30 s/1 m/2 m/5 m, memory-budgeted, effective duration shown, muted by default (optional audio), survives brief background | v1.1 | no RewindCapability |
| partial | Fast-forward | MVP basic / v1.1 full | menu toggle at the Fast Forward Speed setting (1.5x/2x/3x/4x/8x/Unlimited, default 2x, inheritable, changes live from the game menu's Settings); Fast Forward Audio setting Muted (default) or Accelerated up to 4x; hold vs toggle waits for Quick Actions |
| missing | Slow motion 0.25x/0.5x/0.75x | v1.1 |  |

Done: Pause / Resume from menu with paused overlay.

### Rendering, shaders, display

| Status | Item | Target | Notes |
|---|---|---|---|
| partial | Adaptive presentation on high-refresh displays | v1 | CADisplayLink on its own thread runs the frames owed at 59.73 Hz and presents the newest, up to 120 Hz on ProMotion; thermal or Low Power Mode rate changes not handled |
| partial | Curated display/shader set (LCD 1×, LCD 3×, Pixel Transparency, DMG/GBC LCD, sharp bilinear, CRT/scanlines); BuiltIn + CommunityDownload catalog with license/hash checks | v1.1 | original built-in LCD 1× pixel grid and LCD 3× RGB subpixel effects implemented; remaining effects and catalog missing |
| partial | Shader components/params inherit independently; named user presets; live switching via Quick Actions | v1.1 | LCD effect and frame blending inherit App → System → Game → Build independently of scaling, and change live from the game menu's Settings; named presets and Quick Actions switching missing |
| missing | Custom crop / other aspect options | v1.1 |  |
| missing | Thermal-aware degradation of optional work | v1.1 |  |
| missing | Arbitrary .slang/.slangp import; shader preset file import/export | later |  |

Done: Framebuffer -> Metal texture presentation; native core timing paces frames; Screen Scaling
Integer (default, whole device pixels, nearest) / Fill (10:9, edge-blended), inheritable; Frame
Blending Off (default) / Blend / LCD Ghosting, inheritable; Screen Colors per system: Game Boy
Green (default) / Olive / Teal / Black & White, Game Boy Color Balanced (default) / Accurate /
Boost Contrast / Reduce Contrast / Low Contrast / Original. Both inherit System → Game → Build,
update the open picture from Settings, and survive reset and state loads.

### Layouts, skins, touch

| Status | Item | Target | Notes |
|---|---|---|---|
| partial | Consistent touch D-pad diagonal sectors | v1 | Game Boy portrait and landscape and Playtiles share a 0.67 weaker/stronger axis ratio, about 22.5° per diagonal and 67.5° per cardinal; dead zones and hit areas stay unchanged. Angle regression tests cover both styles and orientations; physical-iPhone thumb-sliding check remains in mvp-verification.md |
| missing | Minimal / Fullscreen / one-handed presets | v1.1 |  |
| missing | GameBaby preset; per-accessory/device calibration screen | v1.1 |  |
| missing | Lightweight editor: screen/control position+size, opacity, hitboxes, portrait/landscape, control styles, save preset | v1.1 |  |
| missing | Edit Layout from gameplay on a frozen frame; Save for This Game vs Update Shared Preset | v1.1 |  |
| missing | Native layout import/export via Files/Share | v1.1 |  |
| missing | Delta + Manic skin import adapters, source package kept, unsupported-element report, no silent mis-map | v1.1 |  |
| missing | Optional customizable gestures (off by default) | v1.1 |  |
| missing | Turbo A / Turbo B actions (not in default layout) | v1.1 |  |
| missing | Suggest (never force) a preset for identifiable accessories | v1.1 |  |
| missing | Controller-covered layouts (Playtiles and any later one): the app's screens fit the visible top of the screen and are navigable with the controller's buttons | v1.1 | today only gameplay knows the controller covers the bottom; the library and sheets use the whole screen |
| missing | Full skin artwork authoring; community layout gallery | v1.1 / later |  |

Done: Built-in "Game Boy" layout measured from DMG-01, default, inheritable; Built-in "Playtiles"
layout from the Delta skin frames, START/SELECT swapped, alignment guide; Controller themes Classic
/ Dark / Match System (app-wide), status bar follows; Tap wordmark opens the game menu, with or
without a controller (44 pt), optional Tap Game for Menu (off), one-time hint, VoiceOver Game Menu
button; Touch Haptics Off / Light / Medium (Light), off while a controller hides the controls; Sliding D-pad with
diagonals, sliding A/B, multitouch A+B; Subtle pressed-state visuals.

### Controllers and rumble

| Status | Item | Target | Notes |
|---|---|---|---|
| partial | Multiple controllers, choose Player 1, reserve Player 2 | v1.1 | first connected used; selectPlayerOne() has no UI |
| done | Controller Menu opens and closes the game menu | v1 | Menu opens the game menu with no combo; pressing it again closes and resumes, including with touch controls hidden. X or PlayStation Triangle stays START; Y or Square stays SELECT; Home is never taken |
| missing | Rumble routing override Phone / Controller / Both / Off | v1.1 |  |
| missing | Separate phone and controller intensity | v1.1 |  |

Done: Apple GameController input (extendedGamepad), D-pad and left thumbstick with a radial dead
zone and eight equal sectors; A and B by the controller's letters (Circle = A and Cross = B on PlayStation),
Menu opens the game menu and closes it with Resume; X = START, Options or Y = SELECT (Triangle and Square on PlayStation), shoulders free; iOS controller customizations, including per-app ones, are the only button mapping; Connected controllers use Game
Boy and follow Orientation even with Playtiles chosen; Disconnect releases input, restores the
chosen layout, pauses and shows a notice without restarting; A controller hides the touch
controls, a touch brings them back until its next button press, and Settings can keep them;
Cartridge rumble routed controller-first, phone fallback. Physical-device customization checks
remain in mvp-verification.md.

### Quick Actions

| Status | Item | Target | Notes |
|---|---|---|---|
| missing | One shared action registry for menu, controller hotkeys and skin buttons | v1.1 |  |
| missing | Reorderable/customizable Quick Actions with favorites | v1.1 |  |
| missing | Remaining actions: rewind, slow-mo, screenshot, note, manual, cheats, shader, Build/Profile switch, Build info, watches, frame advance, layout edit | v1.1 |  |

Done: In-game menu from the wordmark with or without a controller: Pause/Resume, Fast Forward,
Save State, Load State and Close; Quick Play offers Add to Library and explains disabled Save State.

### Manuals / documents


| Status | Item | Target | Notes |
|---|---|---|---|
| missing | PDF, CBZ, PNG/JPEG/WebP sets, TXT, Markdown as managed copies | v1.1 |  |
| missing | Game/Build/both association with semantic types, default manual | v1.1 |  |
| missing | In-game overlay reader: pauses, restores prior run/pause state, remembers last-read position | v1.1 |  |
| missing | Text search in TXT/MD/text PDFs if simple; no OCR | v1.1 |  |
| missing | iPad side-by-side; bookmarks/annotations/OCR | v1.1 |  |

### Artwork

| Status | Item | Target | Notes |
|---|---|---|---|
| missing | Automatic fetch on import + setting to disable | v1.1 |  |
| missing | Provider chain: local/imported, Community Catalog, OpenVGDB (experimental), Libretro thumbnails, SteamGridDB (user key), title-screen fallback | v1.1 |  |
| missing | Priority manual -> hack-specific -> inherited base (recorded as inherited) -> generated | v1.1 |  |
| missing | Artwork generated from the Game's title screen | v1.1 | open: capturing after import by running the game unseen (detecting the title screen past the boot logo, for example once the picture settles) or from the current frame chosen in the game menu, or both; framing the 10:9 picture in a square tile (whole-pixel scale on a border color sampled from the frame, or on the placeholder cartridge's label) |
| missing | Build-level artwork override | v1.1 |  |
| missing | Regional artwork: lookups use the Build's region, and a Game's primary artwork follows the preferred region | v1.1 | box art differs by region |
| missing | Multiple typed assets (box front/back, cart, title, screenshots, logo, fan) | v1.1 |  |
| missing | Non-destructive crop/reposition | v1.1 |  |
| missing | Manual "Check for New Artwork"; cache only selected primary | v1.1 |  |
| missing | Artwork provenance (provider, URL, fetch time, rights) | v1.1 |  |

Done: Manual artwork from Photos/Files, remove, stored as user data, downscaled to 1024 pixels;
title placeholder fallback; Artwork follows Builds when a Game is emptied by promote/merge.

### External display / AirPlay


| Status | Item | Target | Notes |
|---|---|---|---|
| missing | Independent external render target (not mirroring); wired displays | v1.1 |  |
| missing | Phone as controller companion keeping Quick Actions/manual/states/Build switching | v1.1 |  |
| missing | Display-specific scaling/aspect/shader/safe area; modes game-only/minimal HUD/mirror | v1.1 |  |

### iCloud


| Status | Item | Target | Notes |
|---|---|---|---|
| missing | Sync all library state except ROM blobs | v1.1 | stable UUIDs exist, nothing else |
| partial | Tombstones; offline devices cannot resurrect | v1.1 | local tombstones are kept for good; sync must check them |
| missing | Field-level merge where safe | v1.1 |  |
| missing | Divergent .sav preserved, explicit resolution, split into new profile | v1.1 |  |

### Community Catalog


| Status | Item | Target | Notes |
|---|---|---|---|
| missing | Signed catalog file read offline: Game and Build metadata, expected hashes, lineage, patch download locations, no ROMs; nothing else depends on it | v1.1 |  |
| missing | Opt-in anonymous read; lightweight identity to contribute; optional attribution | after v1.1 | hosted service |
| missing | Moderated submissions, trust layers, structured evidence, rejection reasons | after v1.1 | hosted service |
| missing | Field-level corrections; "Suggest This Correction" after local edit, never auto-submit | after v1.1 | hosted service |
| missing | Metadata, artwork, legal patch references/uploads; no ROM hosting | after v1.1 | hosted service; the v1 file carries references |
| missing | Update discovery: quiet badge, optional verified pre-download, per-Game override, details | after v1.1 |  |
| missing | Update import as new Build via normal review, old kept for rollback | after v1.1 |  |
| missing | Backend (PostgreSQL/Supabase-shaped), CC0 factual metadata policy | after v1.1 |  |

### Metadata databases

| Status | Item | Target | Notes |
|---|---|---|---|
| missing | Bundled offline identity baseline + validated downloadable updates | v1.1 |  |
| missing | Pluggable metadata provider chain (canonical -> online -> catalog -> user override) | v1.1 |  |
| missing | Separate opt-in homebrew/ROM-hack catalog with provenance | v1.1 |  |

### Backups and migration


| Status | Item | Target | Notes |
|---|---|---|---|
| missing | Export/import Library Backup | v1 |  |
| missing | Export one Game as a package in the Library Backup format: its Builds' patches and recipes, Save Profiles, states, artwork, documents and notes, ROMs only when asked; importing it merges like a restore | v1 |  |
| missing | Documented versioned archive: manifest, ordinary files, checksums, schema version | v1 |  |
| missing | ROMs excluded by default, explicit personal full-backup option | v1 |  |
| missing | Optional password encryption | v1 |  |
| missing | Merge restore by stable IDs/hashes with conflict review; Replace Entire Library | v1 |  |
| missing | Migration Report before commit + retained summary | v1 |  |
| missing | Delta/Manic/Afterplay/Playtiles import adapters | future |  |

Done: Export Save writes a Save Profile's battery save as a .sav named for the Game and profile;
Export ROM writes a Build's ROM, rebuilt first when patched, under its canonical name; both land in
Files without replacing an earlier export.

### Deletion and undo


| Status | Item | Target | Notes |
|---|---|---|---|
| partial | Synchronized tombstones | v1.1 | purging writes a permanent local tombstone; syncing them waits on iCloud |
| missing | Lightweight Undo for recent structural operations | v1.1 |  |

Done: Dependency-aware deletion: the confirmation names patched Builds and emptied Games that go
too, and a Game can't go while another Game's patch is built from it; Recently Deleted for 30
days in Settings, with Restore and Delete Now, purged at launch; Delete Game, Build, Save Profile
and save state from the UI, a save state from its profile's Save States.

### Performance

| Status | Item | Target | Notes |
|---|---|---|---|
| partial | Audio interruptions pause safely; route changes don't restart the game | v1 | the game pauses whenever its scene goes inactive (calls, Siri, Control Center); an audio-only interruption that leaves the scene active still runs silently |
| missing | Thermal-aware degradation | v1.1 |  |
| missing | Default shader sustains full speed on minimum QA device | v1.1 | no shader yet; device gate not recorded |

Done: Native timing authoritative; audio never sets game speed; Sound setting: Follow Silent Switch
(default) / Always On / Always Off; Low-latency adaptive audio (40 ms target growing to 160 ms
after shortfalls); frames run on the display refresh at native speed, up to 120 Hz.

### Privacy and telemetry

| Status | Item | Target | Notes |
|---|---|---|---|
| missing | Opt-in crash reporting limited to non-content diagnostics | v1.1 | no crash reporting at all |
| missing | Opt-in anonymous usage counts (Games, Builds per Game, Save Profiles used by several Builds, Quick Play sessions added to the library), never titles, hashes, filenames or contents | v1.1 | endpoint or provider and privacy copy not chosen; PRIVACY.md and the App Store privacy answers change with it |
| missing | Explicit bug-report export with checklist/preview | v1.1 |  |
| missing | Accurate privacy/consent copy for provider queries and catalog; keys server-side/secure storage | v1.1 |  |

Done: Nothing uploaded automatically (ROMs, saves, screenshots, memory, filenames, notes).

### Accessibility


| Status | Item | Target | Notes |
|---|---|---|---|
| partial | VoiceOver labels for management UI and emulator controls | v1 | the logo is the "Game Menu" button, with Close Game inside the menu; the default save's star reads "Default Save"; controls not playable by VoiceOver (accepted) |
| partial | Dynamic Type in normal UI | v1 | SwiftUI defaults; controller drawing fixed size |
| missing | Reduce Motion support | v1 | none |
| partial | Large/configurable touch targets | v1 | hit areas extend 10-12 pt beyond drawn controls; not configurable |
| missing | One-handed layouts | v1.1 | none |
| missing | Controller navigation | v1 | none; button remapping is iOS's Game Controller settings |

Done: Good contrast / color-independent states; haptics never sole feedback.

### Settings inheritance

Nothing open.
| missing | Narrow Save Profile overlay (cheats, RTC, autoresume, rewind) | v1.1 |  |

Done: Resolver App -> System -> Game -> Build, only explicit overrides stored, inherited source
shown, Reset to Inherited; Implemented keys; Settings screens for App, System (Game Boy, Game Boy
Color), Game and Build; App Settings as Controls, Display and Playing pages with Systems, Library
and About lists, and the scoped sheet grouped the same way with each setting's source under its
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
| missing | Optional Included Games manifest (ID, hashes, licenses, permission record, releaseApproved gate) imported through the normal path | v1.1 |  |

### CI / generated pipelines


| Status | Item | Target | Notes |
|---|---|---|---|
| missing | no-intro-update, toolchain-fingerprints-update, shader-catalog-update, included-games-verify, fixtures, license-audit, privacy-audit, openvgdb-update (disabled) | v1 |  |
| partial | MVP gate | MVP | package tests cover required tests 1-13 and 15, and an app test covers 14 (controller disconnect); every physical-iPhone (L4c) check is unchecked |

Done: ci.yml (L1/L2/L3, gbtoolsid differential, test-coverage, hygiene) and ios-build.yml (simulator
build/tests).

### v1.1 targets


| Status | Item | Target | Notes |
|---|---|---|---|
| missing | Link cable, local dual-core first; nearby/SharePlay initiation; no Multipeer | v1.1 | no LinkCableCapability |
| missing | GB Studio save migration with old/new variable maps | v1.1 |  |
| missing | Game Boy Camera | v1.1 | no CameraCapability |
| missing | Game Boy Printer with preview/save/share | v1.1 | no PrinterCapability |
| missing | RAR import (tentative) | v1.1 |  |
| missing | Visual skin/layout authoring beyond the lightweight editor | v1.1 |  |
| missing | Video/GIF capture; screenshots and clips framed like a Game Boy, shared from the game menu | v1.1 | saved recordings also land in the Files folder |
| missing | Browse and download games: itch.io's Game Boy tag in an in-app browser and Homebrew Hub (hh.gbdev.io) by its API, from the library's + menu; downloads go straight to Import Review, with Quick Play | v1.1 | needs zip import; the app's first network use, so revisit the privacy manifest and label; confirm App Store guideline 4.7 wording |
| missing | Share an itch.io game page or GitHub page to download and import a ROM | v1.1 | web-URL share extension; resolve supported ROM downloads, choose when several exist, then Import Review or Quick Play; safe ZIP extraction; preserve itch.io's normal purchase/login flow |
| missing | `.gbproject`-style project import/export | v1.1 |  |
| missing | Better ROM comparison + BPS generation | v1.1 |  |
| missing | iPad side-by-side manual/game | v1.1 |  |

### Later


| Status | Item | Target | Notes |
|---|---|---|---|
| missing | Developer tools: a watched Files or iCloud Drive folder whose new ROMs import as new Builds; GitHub releases or CI builds as Builds; a tester bug report bundle (save, state, screenshot, Build hash, toolchain) | later |  |
| missing | iOS integration: Continue Playing widget, Siri and Shortcuts ("Resume <game>"), Spotlight | later |  |
| missing | Network/internet link; RetroAchievements; full debugger/disassembler/VRAM; deterministic replay/movies; arbitrary .slang/.slangp; Apple TV/macOS/iPad-first polish; creator-controlled homebrew publishing; document annotations/OCR/bookmarks; community layout gallery; battery-saver mode; per-Build alternate core choice; bulk canonical rename | later |  |

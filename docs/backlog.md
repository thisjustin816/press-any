# Backlog

Every feature and requirement in `docs/specs/` and `docs/decisions.md`, checked against the code
on 2026-10-03 and updated 2026-10-05: 105 done, 27 partial and 168 missing. The specs stay the
source of truth for what each item means; this file tracks what's left and a suggested order.
Update an item's row when its status changes, and move it to its area's "Done" line when it's
finished.

Spec references: `mvp`, `prod`, `dec` and `later` are the four files in `docs/specs/`
(`gb-emulator-mvp.md`, `-product.md`, `-decisions.md` and `-later-decisions.md`), with section
numbers after them, so `dec 12` is section 12 of the decisions file. `Q81` is locked decision 81
in that file, and `D` is `docs/decisions.md`. Targets are the spec's release: MVP, v1, v1.1 or
later.

## Suggested order

Nothing below is in progress.

1. Finish the MVP. The real-device check in `docs/mvp-verification.md` still has to pass on a
   phone.
2. Display and play feel, small changes that make games look and play right on day one: frame
   blending, GBC color correction, DMG palettes, Fast Forward presets with hold or toggle, slow
   motion, rewind, and the DMG/GBC/SGB model override.
3. The rest of the v1 core gate: Quick Actions, save state slots and Quick Save, controller
   profiles and remapping, landscape and the layout editor, cheats and memory tools, external
   display, and the curated shader library, which `AGENTS.md` holds until the MVP check passes.
4. Library and services: Share Sheet and archive import, search and collections, automatic
   artwork, manuals, screenshots and notes, deletion and undo, backups, iCloud and the Community
   Catalog.

## Known bugs

None known.

## Spec conflicts to resolve

None open. The twelve listed on 2026-10-04 were settled on 2026-10-05 (`D` "Spec conflicts
settled for the MVP").

## Inventory by area

Open items in each area are in the table, finished ones on the line under it.

### Platform / app shell

| Status | Item | Target | Spec | Notes |
|---|---|---|---|---|
| partial | TestFlight then App Store release path (signing, rights, disclosures gate) | v1 | prod "Platform", acceptance-matrix "Release" | manual TestFlight upload workflow and setup (docs/release.md); App Store listing, review and rights gate not started |
| missing | Paid/IAP seam `FeatureEntitlementProvider` (StoreKit kept out of Domain) | v1 | later 12 | none |
| missing | Minimal first-launch onboarding (Import, Quick Play, saves/storage, opt-ins) | v1 | Q183 | only the one-time "Tap Press Any for the menu" hint |
| missing | Developer Mode toggle (Advanced -> Developer Mode) gating dev tools | v1 | Q184, dec 12 | none |
| missing | Landscape gameplay | v1 | prod "Layouts, skins, touch"; dec 22 | TouchControlLayout is portrait-only |
| missing | Root docs CONTRIBUTING/SECURITY/PRIVACY/CoC/trademark, DCO signoff | v1 | later 12 | only LICENSE, THIRD_PARTY_NOTICES.md, AGENTS.md, README.md |

Done: iOS 17 minimum; iPhone-first, iPad not deliberately broken; Light + dark appearance;
Offline-first core; Naming: display name only from Info.plist, brand-free IDs; Wordmark (heavy
italic, magenta "A") in library toolbar and controller body; App icon (A button; light/dark/tinted);
Acknowledgements screen listing SameBoy + GRDB with full licenses.

### Architecture seams

Spec: later 2.

| Status | Item | Target | Spec | Notes |
|---|---|---|---|---|
| partial | Registries for platforms, cores, image analyzers, toolchain detectors, patch formats | v1 | later 2, D "Adaptive audio, and registries wait for v1" | CoreRegistry + ToolchainDetectorRegistry exist; no platform or analyzer registry; patch formats dispatched by file extension in PatchStackApplier |
| missing | PlatformDescriptor / HardwareDescriptor / DistributionDescriptor / CompatibilityRecord (core target + hardware target) | v1 | later 2 |  |
| missing | Input and memory descriptors | v1 | later 2 |  |

Done: Neutral platform IDs `gb`/`gbc`; Generic `GameImage`/`PersistentSave` contracts.

### Cores

| Status | Item | Target | Spec | Notes |
|---|---|---|---|---|
| missing | Nonintrusive "core update available" notice | v1 | prod "Core policy" | none |
| missing | Explicit, reversible core-migration checkpoint (new state lineage, rollback when old core available) | v1 | Q85; later 4 | none |
| partial | Automatic model selection | v1 | Q87 | CGB flag 0x80/0xC0 -> CGB, else DMG (SameBoyAdapter.loadImage); SGB never chosen |
| missing | Model override DMG/GBC/SGB at App->System->Game->Build | v1 | Q87; later 7 ("no claim CGB-only works in DMG") | no setting key |
| missing | SGB mode: palettes, borders, game enhancements (custom border editing deferred) | v1 | Q86 | no SGB model/boot ROM in bridge |
| missing | User-chosen alternate core per Build | later | dec 2 |  |
| missing | mGBA/GBA adapter | later | prod "post-v1" |  |

Done: SameBoy 1.0.3 GB/GBC behind `EmulatorCore`, no SameBoy types leak; Latest compatible core on
first launch, then pinned per Build; Open SameBoy boot ROMs incl. cgb_boot_fast; Skip Boot Logo:
Quick Play always, library via inheritable setting (default shows logo); Optional capability
protocols: rumble and boot skipping implemented, rewind, cheats, memory access, RTC, link cable,
camera and printer declared, and a missing one is a failed cast.

### Persistence / storage

| Status | Item | Target | Spec | Notes |
|---|---|---|---|---|
| partial | Verify important assets when read/used (Q180) | v1 | prod "Persistence and storage" | launch re-hashes image/patches (ResolveImageForLaunch); Settings > Check Library Files runs ManagedAssetIntegrityChecker (missing and damaged files, removes leftovers and stale temporary files); saves/states not verified on read |
| missing | Storage screen by category, source vs disposable, safe cleanup | v1 | Q138 | none |
| partial | Automatic cleanup of disposable data only | v1 | Q139 | expired Quick Play sessions and staged copies left by interrupted imports removed at launch (AppContainer init); no generated-cache eviction under pressure |
| missing | GC coordination / in-flight protection / orphan sweep in the running app | v1 | later 6 | logic only in the unused checker |

Done: GRDB/SQLite metadata, binaries on managed FS; SHA-256 identity, content-addressed
collision-safe relative paths; Source-asset dedup; Source vs userData vs cache vs temporary classes;
Atomic save/state writes; Transactional commit, no orphaned permanent asset on failure.

### Domain model

| Status | Item | Target | Spec | Notes |
|---|---|---|---|---|
| missing | Game aliases/alternate titles (indexed) | v1 | Q162 | no field |
| missing | Metadata source/confidence/provenance + user overrides, Metadata Details UI | v1 | Q163/Q164; mvp "Game" (provenance records) | none |
| missing | Presentation-metadata editing (rename Game/Build after creation) | v1 | Q163 | no edit UI |
| partial | Build region/language/revision/version + structured version sort key | MVP/v1 | mvp "Build"; Q152 | columns exist, never populated (import ignores filename/header), no edit UI |
| partial | Build toolchain record, variable-map sidecars, notes, per-Build playtime, artwork/doc overrides, activation history | v1 (toolchain/sidecars MVP per later 5) | prod "Build"; dec 3 | toolchain reports and variable maps done; the rest missing |
| missing | Documents model (Game/Build/both; Manual/README/Changelog/Guide/Map/Other) | v1 | prod "Documents"; Q169 |  |
| missing | Typed multi-artwork model with primary selection | v1 | prod "Artwork"; dec 20 | Game.artworkAssetID is a single image |
| missing | Tags and collections | v1 | prod "Canonical domain model" |  |

Done: Game: UUID, primary title, system family, preferred Build/Profile, timestamps; Build: UUID,
gameID, system, concise name, immutable hash, sourceKind, parent lineage, Base marker, preferred
profile, core pin; SaveProfile: name, current save, ancestry, playtime/session count/last
played/created; SaveState exact context (Build + Profile + core + serialization version), playtime,
label, kind; PatchRecipe: exact base, ordered items, enabled flag, expected hash, Apply-Anyway flag;
ManagedAsset: hash, kind, length, relative path, original filename, provenance, integrity.

### Library

| Status | Item | Target | Spec | Notes |
|---|---|---|---|---|
| missing | Optional Developer view (Build/version/profile details) | v1 | prod "Library organization" |  |
| missing | Manual collections/folders | v1 | dec 15 |  |
| missing | Smart collections (GB, GBC, Homebrew, ROM Hacks, Favorites, Recently Played, Builds with updates) | v1 | dec 15 |  |
| missing | Tags on Games/Builds via long-press/overflow | v1 | dec 15 |  |
| partial | Sorting | v1 | dec 15 | title only; recent/added/playtime/release year/system/developer/publisher/hack author/Build version/last Build change/manual order missing |
| missing | Favorites | v1 | prod "Library organization" |  |
| partial | Play statistics | v1 | prod/dec 15 | profile playtime, session count, last played recorded but never displayed; per-Build playtime, Game rollups, play count, last played on Game missing |

Done: Box-art grid and compact list; Game detail with Builds and Save Profiles; Preferred Build
one-tap Play; explicit choice never silently changed; Build switch from Game detail; long-press to
play another Build/Save; Build preferred Save Profile falling back to Game preferred.

### Search

| Status | Item | Target | Spec | Notes |
|---|---|---|---|---|
| missing | SQLite FTS5 live index (aliases, filenames, hack title/author/version, system, region, Build names, tags, doc titles) with title-first ranking | v1 | prod "Search" | no FTS table |

Done: Search by primary title.

### ROM identity, naming, metadata

| Status | Item | Target | Spec | Notes |
|---|---|---|---|---|
| partial | No-Intro / ROM-hack bracket parsing into structured fields | v1 | prod "ROM identity"; dec 17 | FilenameMetadataParser yields title + raw ()/[] groups only; no region/lang/rev/hack title/author/version/status flags |
| partial | Header read/validate/display, no editing | v1 | dec 18 | GBROMHeaderParser validates header + global checksum; shown only in Import Review, not in Build details |
| missing | Canonical normalized filename + explicit "Rename File to Canonical Name" (bulk later) | v1 | dec 17 |  |
| missing | Verification status Verified/Modified/Unknown; never auto-repair | v1 | dec 18 |  |
| missing | Bundled No-Intro baseline + signed/validated updates; parent/clone family grouping shown in review | v1 | prod "ROM identity"; Q157; later 11 no-intro-update.yml |  |
| partial | Match Game... for unknown ROMs, lineage without owning the base, link base later | v1 | dec 17 | user can pick an existing Game as destination; no lineage-without-base metadata |
| partial | Multi-signal development-build matching, never silently attach | v1 | Q151; mvp "Import MVP" step 5 | only exact hash or explicit target; no heuristics |
| missing | Quiet provider metadata refresh never overwriting user overrides | v1 | Q165 |  |

Done: SHA-256 identity for every ROM; Original imported filename preserved permanently.

### Import

| Status | Item | Target | Spec | Notes |
|---|---|---|---|---|
| missing | Share Sheet / Open In (and Quick Play vs Import choice on open) | v1 | prod "Sources"; dec 14 | no document types/onOpenURL |
| missing | ZIP + 7z (libarchive) with Q92 safety (depth/ratio limits, traversal, password detect) | v1 | Q92; later 6 |  |
| missing | Multi-asset analysis/grouping (ROMs, patches, saves, art, manuals, README/changelog, variable maps, skins) | v1 | prod "Multi-asset review" |  |
| partial | Duplicate ROM still inspects new saves/art/manuals/patches | v1 | prod "Duplicate handling" | duplicate path only repairs the blob |
| missing | Visual artwork comparison (existing/fetched/packaged) in review | v1 | dec 32 |  |
| missing | Import while playing -> "New Build Ready" Switch Now/Later; Developer "Restart into New Build" | v1 | Q149/Q150 |  |
| missing | Multiple ROMs attached to one Game in one flow | v1 | dec 16 |  |

Done: Analyze -> ImportPlan -> Review -> transactional Commit; Files picker for .gb/.gbc; .sav and
.ips/.bps from Game detail; Exact duplicate: no second blob/Build, shows it's already there,
re-import repairs damaged file; New Game vs Add Build choice, Base Build toggle; Toolchain
findings in Import Review and Quick Play promotion; Files over a size limit for their kind
(ROM, patch, save, artwork, variable map) refused before they are read or staged; only regular
files staged.

### Game/Build restructuring

| Status | Item | Target | Spec | Notes |
|---|---|---|---|---|
| partial | Import-Review-style inheritance step (artwork, docs, tags, compatible profiles; deselectable) on promote/merge | v1 (mvp says merge "with review") | Q83/Q84 | review sheet copies artwork and chosen Save Profiles; docs and tags don't exist yet |
| missing | Preferred Base Build among several | v1 | Q155 (optional) |  |
| missing | Lightweight Build timeline (versions, hashes, parents, notes, import/activation history) | v1 | prod "Game/Build restructuring" |  |
| missing | Build comparison (changed bytes/ranges, size, banks, header) | v1 | dec 5 |  |

Done: Make Separate Game: Move/Copy, default Move, Build UUID/blob preserved, Build-scoped data
follows; Merge into Game: Move/Copy, lineage/recipes remapped; Same image already in target: Copy
skips, Move refused naming the Builds; Profiles/artwork/preferences follow when the source Game is
emptied or merged away; Promoted Game records the Game it split from (Split From), kept by title
once that Game is gone; Mark or unmark imported Builds as Base Builds after import.

### Patching

| Status | Item | Target | Spec | Notes |
|---|---|---|---|---|
| missing | Editable stacks UI: reorder/enable/disable/add/remove -> new Build | v1 | Q133 |  |
| partial | Pluggable patch-format architecture | v1 | prod "Patching" | switch on extension, no registry |
| missing | Patch metadata with confidence/provenance (catalog > README > filename) | v1 | Q135 |  |
| missing | BPS generation from base vs modified Build | v1.1 | prod "v1.1 targets" |  |
| missing | Quick Play a patch against a base without creating a Build | future | dec 14 |  |

Done: IPS (RLE, truncate) and BPS (CRC checks) engines; Preserve base ROM, original patch, recipe,
result hash; Base validation; explicit Apply Anyway persisted for rebuilds; Patch result is a new
immutable Build with lineage; Generated ROM is cache: evict, rebuild, verify hash; Ordered
multi-patch recipe (multi-select applies a stack); Unsupported formats identified and reported.

### Save system: battery saves and profiles

| Status | Item | Target | Spec | Notes |
|---|---|---|---|---|
| partial | Compatibility-aware Build switching (flush, analyze, risky -> migrate/duplicate/use anyway/blank) | MVP and v1 | mvp "Build switching/save safety"; prod "Compatibility-aware Build switching"; later 5, 15 | launch check offers copy/new save/use anyway; migrate waits for v1.1 GB Studio migration |
| missing | GB Studio save migration (version-gated, needs maps) | v1.1 | prod "v1.1 targets" |  |
| missing | RTC: real time + per-profile manual offset; Developer RTC controls | v1 | dec 11 | SameBoy's internal RTC runs, no offset; the offset goes in the profile's stored `rtcContextJSON` |
| missing | Save Profile locking | later | dec 9/33 |  |

Done: One .sav per Save Profile, atomic flush synced to storage; In-game saves written during play
once changed, at most every five seconds of play; Compatible Builds share a profile on purpose; New
blank profile; duplicate profile (bytes copied, ancestry shown); Import .sav into a new profile,
or into an existing one after confirming, keeping its old save as "<name> before import";
Variable maps (GB Studio globals, RGBDS .sym, GBDK .noi) kept on the exact Build; Each profile
records the Build that last wrote it, and launching another Build warns when the save may not fit
(GB Studio, different detected tools, different header save hardware); Save Profile badge, one
emoji shown beside its name; Delete a profile, with a confirmation naming it, taking its save and
states.

### Save system: states and lifecycle

| Status | Item | Target | Spec | Notes |
|---|---|---|---|---|
| missing | Quick Save (one tap) | v1 | dec 8 | SaveStateKind.quick unused |
| missing | Configurable fixed slots | v1 | dec 8 |  |
| partial | Unlimited named states | v1 | dec 8 | `label` field; no naming, renaming or deleting UI |
| missing | Configurable automatic cleanup; pinned/favorited exempt | v1 | dec 8 |  |
| missing | State records cheat config; offer Restore Cheat Configuration | v1 | Q126 |  |
| missing | Per-Save-Profile autoresume override | v1 | dec 8/9, Q146 (see conflicts) |  |
| missing | Separate crash-recovery checkpoint + Recover Session / Start Normally | v1 | Q181 | SaveStateKind.crashRecovery unused |
| missing | App relaunch returns to the previous game/session | v1 | Q146 |  |
| missing | In-game Build/Profile switching (save, check, relaunch) | v1 | Q148 |  |

Done: Basic manual save + load state (menu lists all states); States
never cross Build/Profile/core/serialization context; Auto State on background, close and session
switch; rolling 5; Resume Games Always/Ask/Never (default Always), inheritable System/Game/Build,
Ask prompt, foreground policy; Auto State not restored once the profile's save is newer; Failed
restore boots normally, keeps state, tells user; Backgrounding pauses emulation/audio; One active
emulator session; Each state keeps a PNG thumbnail of its frame, shown in Load State; A failed
battery write still saves the Auto State, and a failed close can be retried or closed without
saving; Loading a state older than the profile's save warns and keeps the save as "<name> before
loading state"; A separated Build's states follow it to the profile copies it plays.

### Quick Play

| Status | Item | Target | Spec | Notes |
|---|---|---|---|---|
| missing | Configurable retention Immediately / 24 h / 7 d | v1 | prod "Quick Play" |  |
| partial | Session artifacts | v1 | dec 14 | battery + autosave kept; manual states ("Save states aren't kept in Quick Play"), screenshots, notes, debug captures and their transfer on promotion missing |
| missing | Background hash/identify/toolchain detection for Quick Play | v1 | dec 14 vs D (optional, after first frame) | not run |

Done: Temporary sandbox, no library mutation until promotion; Time-to-first-frame path: read once,
validate, copy, hash; boot past logo (cgb_boot_fast); no optional assets; "First frame in N ms"; Use
an existing save by copying it in; source never written; Promotion via Import Review: keep / replace
after safety copy / new profile / discard save; Recent Quick Plays list with Keep/Import/Discard and
resume from autosave, skipped once the battery save is newer; Add to Library keeps the autosave as
the Build's Auto State; 24 h default retention, expired sessions purged.

### Cheats and memory tools

Spec: all v1 unless noted.

| Status | Item | Target | Spec | Notes |
|---|---|---|---|---|
| missing | Cheat management add/remove/enable/disable/persist; Game Genie/GameShark/SameBoy formats | v1 | prod "Cheats..."; dec 12 | no CheatCapability |
| missing | Pluggable verified-ROM cheat database, selective add, never auto-enable | v1 | Q128 |  |
| missing | Cheat groups/categories + search | v1 | Q127 |  |
| missing | Cheat search: exact/unknown/changed/unchanged/inc/dec/delta/greater/less, signed/unsigned 8/16-bit, hex | v1 | prod "Cheats..." |  |
| missing | Result actions: edit, freeze, watch, create cheat, copy address | v1 | dec 12 |  |
| missing | Named search sessions within current emulation session | v1 | Q131 |  |
| missing | Memory Watch list + optional Developer HUD + short history/min/max/graph | v1 | Q129/Q130 |  |
| missing | Immediate Developer Mode memory writes with Undo Last Write, frozen indication | v1 | Q132 |  |
| missing | Frame advance + frame counter (bindable) | v1 | dec 11 |  |
| missing | Full debugger/disassembler/VRAM viewer | later |  |  |

### Screenshots, notes, debug context

Spec: all v1.

| Status | Item | Target | Spec | Notes |
|---|---|---|---|---|
| missing | In-app screenshot gallery tied to exact Build; export/share to Photos | v1 | dec 13 |  |
| missing | Export presets Clean / Build Info / Bug Report with rendered info strip and metadata fields | v1 | dec 13 |  |
| missing | Optional atomic Capture Context (watches, named vars, memory ranges, registers, frame/time, Build/hash/patches, RTC, cheats, profile, core/settings) | v1 | dec 13 |  |
| missing | Full-RAM snapshot (opt-in, Developer Mode) | v1 | dec 13 |  |
| missing | Bug-report export (Markdown/JSON) with privacy checklist/preview | v1 | Q176 |  |
| missing | Game notes, Build notes, timestamped gameplay notes with attachments | v1 | dec 13 |  |

### Rewind and speed

| Status | Item | Target | Spec | Notes |
|---|---|---|---|---|
| missing | Rewind, presets 5 s/15 s/30 s/1 m/2 m/5 m, memory-budgeted, effective duration shown, muted by default (optional audio), survives brief background | v1 | Q80/Q103; later 7 | no RewindCapability |
| partial | Fast-forward | MVP basic / v1 full | Q81 | menu toggle at fixed 2x (GameplayViewController.toggleFastForward, EmulationSpeed supports multiplier/unlimited); presets 1.5x/2x/3x/4x/8x/Unlimited, hold vs toggle, audio Accelerated/Mute setting missing |
| missing | Slow motion 0.25x/0.5x/0.75x | v1 | dec 11 |  |

Done: Pause / Resume from menu with paused overlay.

### Rendering, shaders, display

| Status | Item | Target | Spec | Notes |
|---|---|---|---|---|
| partial | Adaptive presentation on high-refresh displays | v1 | Q95 | MTKView redraws per submitted frame; no display-link pacing or ProMotion handling |
| missing | GB/GBC color correction | v1 | dec 23 |  |
| missing | DMG palettes / system-authentic default look; raw pixels available | v1 | Q108 | SameBoy default output only |
| missing | Frame blending, LCD ghosting | v1 | dec 23 |  |
| missing | Curated RetroArch-compatible shader set (lcd1x, lcd3x, Pixel Transparency, DMG/GBC LCD, sharp bilinear, CRT/scanlines); BuiltIn + CommunityDownload catalog with license/hash checks | v1 | prod "Rendering and shaders"; later 9 |  |
| missing | Shader components/params inherit independently; named user presets; live switching via Quick Actions | v1 | Q105/Q106/Q107 |  |
| missing | Custom crop / other aspect options | v1 | dec 23 |  |
| missing | Thermal-aware degradation of optional work | v1 | Q97 |  |
| missing | Arbitrary .slang/.slangp import; shader preset file import/export | later | Q106 |  |

Done: Framebuffer -> Metal texture presentation; native core timing paces frames; Screen Scaling
Integer (default, whole device pixels, nearest) / Fill (10:9, edge-blended), inheritable.

### Layouts, skins, touch

| Status | Item | Target | Spec | Notes |
|---|---|---|---|---|
| missing | Minimal / Fullscreen / one-handed presets | v1 | prod "Layouts, skins, touch" |  |
| missing | GameBaby preset; per-accessory/device calibration screen | v1 | Q113/Q114 |  |
| missing | Lightweight editor: screen/control position+size, opacity, hitboxes, portrait/landscape, control styles, save preset | v1 | dec 22; Q119 |  |
| missing | Edit Layout from gameplay on a frozen frame; Save for This Game vs Update Shared Preset | v1 | Q118/Q120 |  |
| missing | Native layout import/export via Files/Share | v1 | Q115 |  |
| missing | Delta + Manic skin import adapters, source package kept, unsupported-element report, no silent mis-map | v1 | Q116/Q117 |  |
| missing | Optional customizable gestures (off by default) | v1 | Q124 |  |
| missing | Turbo A / Turbo B actions (not in default layout) | v1 | Q125 |  |
| missing | Suggest (never force) a preset for identifiable accessories | v1 | Q113 |  |
| missing | Full skin artwork authoring; community layout gallery | v1.1 / later | v1.1/later | Q115 |

Done: Built-in "Game Boy" layout measured from DMG-01, default, inheritable; Built-in "Playtiles"
layout from the Delta skin frames, START/SELECT swapped, alignment guide; Controller themes Classic
/ Dark / Match System (app-wide), status bar follows; Tap wordmark opens the game menu, with or
without a controller (44 pt), optional Tap Game for Menu (off), one-time hint, VoiceOver Game Menu
button; Touch Haptics Off / Light / Medium (Light), off while a controller hides the controls; Sliding D-pad with
diagonals, sliding A/B, multitouch A+B; Subtle pressed-state visuals.

### Controllers and rumble

| Status | Item | Target | Spec | Notes |
|---|---|---|---|---|
| partial | Multiple controllers, choose Player 1, reserve Player 2 | v1 | Q111 | first connected used; selectPlayerOne() has no UI |
| missing | Named reusable controller profiles, remapping, App/System/Game/Build inheritance | v1 | Q112 | fixed mapping (Select = Options or L1) |
| missing | Controller hotkey combos and menu navigation | v1 | dec 24 | "Open Menu" is a mappable input with no default button, and Home is never taken (D "A controller opens the game menu") |
| missing | Rumble routing override Phone / Controller / Both / Off | v1 | Q88 |  |
| missing | Separate phone and controller intensity | v1 | Q104 |  |

Done: Apple GameController input (extendedGamepad); Unexpected disconnect pauses, reveals touch
controls, shows notice; A controller hides the touch controls, a touch brings them back until its
next button press, and Settings can keep them; Cartridge rumble routed controller-first, phone fallback.

### Quick Actions

| Status | Item | Target | Spec | Notes |
|---|---|---|---|---|
| partial | In-game menu (wordmark tap, with or without a controller): Pause/Resume, Fast Forward, Save State, Load State, Close | MVP | D "One game menu" | menuElements, GameMenuButton |
| missing | One shared action registry for menu, controller hotkeys and skin buttons | v1 | prod "Quick Actions" |  |
| missing | Reorderable/customizable Quick Actions with favorites | v1 | prod "Quick Actions" |  |
| missing | Remaining actions: rewind, slow-mo, screenshot, note, manual, cheats, shader, Build/Profile switch, Build info, watches, frame advance, layout edit | v1 | prod "Quick Actions" |  |

### Manuals / documents

Spec: all v1 unless noted.

| Status | Item | Target | Spec | Notes |
|---|---|---|---|---|
| missing | PDF, CBZ, PNG/JPEG/WebP sets, TXT, Markdown as managed copies | v1 | Q99 |  |
| missing | Game/Build/both association with semantic types, default manual | v1 | Q169 |  |
| missing | In-game overlay reader: pauses, restores prior run/pause state, remembers last-read position | v1 | Q170/Q171 |  |
| missing | Text search in TXT/MD/text PDFs if simple; no OCR | v1 | Q100 |  |
| missing | iPad side-by-side; bookmarks/annotations/OCR | v1 | v1.1/later |  |

### Artwork

| Status | Item | Target | Spec | Notes |
|---|---|---|---|---|
| missing | Automatic fetch on import + setting to disable | v1 | prod "Artwork" |  |
| missing | Provider chain: local/imported, Community Catalog, OpenVGDB (experimental), Libretro thumbnails, SteamGridDB (user key), title-screen fallback | v1 | Q79; later 8 |  |
| missing | Priority manual -> hack-specific -> inherited base (recorded as inherited) -> generated | v1 | dec 20 |  |
| missing | Build-level artwork override | v1 | Q168 |  |
| missing | Multiple typed assets (box front/back, cart, title, screenshots, logo, fan) | v1 | dec 20 |  |
| missing | Non-destructive crop/reposition | v1 | Q167 |  |
| missing | Manual "Check for New Artwork"; cache only selected primary | v1 | Q166/Q98 |  |
| missing | Artwork provenance (provider, URL, fetch time, rights) | v1 | later 8 |  |

Done: Manual artwork from Photos/Files, remove, stored as user data, downscaled to 1024 pixels;
title placeholder fallback; Artwork follows Builds when a Game is emptied by promote/merge.

### External display / AirPlay

Spec: v1 hard requirement.

| Status | Item | Target | Spec | Notes |
|---|---|---|---|---|
| missing | Independent external render target (not mirroring); wired displays | v1 | Q175; dec 26 |  |
| missing | Phone as controller companion keeping Quick Actions/manual/states/Build switching | v1 | Q174 |  |
| missing | Display-specific scaling/aspect/shader/safe area; modes game-only/minimal HUD/mirror | v1 | Q175; dec 26 |  |

### iCloud

Spec: target v1, may move to v1.1.

| Status | Item | Target | Spec | Notes |
|---|---|---|---|---|
| missing | Sync all library state except ROM blobs | v1 | Q89 | stable UUIDs exist, nothing else |
| missing | Tombstones; offline devices cannot resurrect | v1 | Q90; later 14 |  |
| missing | Field-level merge where safe | v1 | Q101 |  |
| missing | Divergent .sav preserved, explicit resolution, split into new profile | v1 | Q102 |  |

### Community Catalog

Spec: target v1, may move to v1.1.

| Status | Item | Target | Spec | Notes |
|---|---|---|---|---|
| missing | Opt-in anonymous read; lightweight identity to contribute; optional attribution | v1 | prod "Community Catalog" |  |
| missing | Moderated submissions, trust layers, structured evidence, rejection reasons | v1 | dec 19; later 13 |  |
| missing | Field-level corrections; "Suggest This Correction" after local edit, never auto-submit | v1 | dec 19 |  |
| missing | Metadata, artwork, legal patch references/uploads; no ROM hosting | v1 | Q178/Q179 |  |
| missing | Update discovery: quiet badge, optional verified pre-download, per-Game override, details | v1 | dec 19 |  |
| missing | Update import as new Build via normal review, old kept for rollback | v1 | dec 19 |  |
| missing | Backend (PostgreSQL/Supabase-shaped), CC0 factual metadata policy | v1 | later 13 |  |

### Metadata databases

| Status | Item | Target | Spec | Notes |
|---|---|---|---|---|
| missing | Bundled offline identity baseline + validated downloadable updates | v1 | prod "Automatic artwork/metadata databases" |  |
| missing | Pluggable metadata provider chain (canonical -> online -> catalog -> user override) | v1 | Q79 |  |
| missing | Separate opt-in homebrew/ROM-hack catalog with provenance | v1 | prod "Automatic artwork/metadata databases" |  |

### Backups and migration

Spec: all v1 unless noted.

| Status | Item | Target | Spec | Notes |
|---|---|---|---|---|
| missing | Export/import Library Backup | v1 | Q140 |  |
| missing | Documented versioned archive: manifest, ordinary files, checksums, schema version | v1 | Q141 |  |
| missing | ROMs excluded by default, explicit personal full-backup option | v1 | Q140 |  |
| missing | Optional password encryption | v1 | Q142 |  |
| missing | Merge restore by stable IDs/hashes with conflict review; Replace Entire Library | v1 | Q143 |  |
| missing | Migration Report before commit + retained summary | v1 | Q144 |  |
| missing | Delta/Manic/Afterplay/Playtiles import adapters | future | Q140 |  |

### Deletion and undo

Spec: v1.

| Status | Item | Target | Spec | Notes |
|---|---|---|---|---|
| missing | Delete Game/Build/Profile/State from the UI | v1 | dec 30 | repo deleteGame/deleteSaveProfile/deleteSaveState only |
| missing | Dependency-aware deletion showing affected Builds/assets; no broken base/patch links | v1 | dec 30 |  |
| missing | Recently Deleted, 30 days, restorable | v1 | Q90 |  |
| missing | Synchronized tombstones | v1 | Q90 |  |
| missing | Lightweight Undo for recent structural operations | v1 | Q145 |  |

### Performance

| Status | Item | Target | Spec | Notes |
|---|---|---|---|---|
| partial | Audio interruptions pause safely; route changes don't restart the game | v1 | Q173 | the game pauses whenever its scene goes inactive (calls, Siri, Control Center); an audio-only interruption that leaves the scene active still runs silently |
| missing | Thermal-aware degradation | v1 | Q97 |  |
| missing | Default shader sustains full speed on minimum QA device | v1 | Q94 | no shader yet; device gate not recorded |

Done: Native timing authoritative; audio never sets game speed; Sound setting: Follow Silent Switch
(default) / Always On / Always Off; Low-latency adaptive audio (40 ms target growing to 160 ms
after shortfalls, frames paced against fixed deadlines).

### Privacy and telemetry

| Status | Item | Target | Spec | Notes |
|---|---|---|---|---|
| missing | Opt-in crash reporting limited to non-content diagnostics | v1 | Q177 | no crash reporting at all |
| missing | Explicit bug-report export with checklist/preview | v1 | Q176 (see Screenshots) |  |
| missing | Accurate privacy/consent copy for provider queries and catalog; keys server-side/secure storage | v1 | later 13 |  |

Done: Nothing uploaded automatically (ROMs, saves, screenshots, memory, filenames, notes).

### Accessibility

Spec: v1 baseline, Q93.

| Status | Item | Target | Spec | Notes |
|---|---|---|---|---|
| partial | VoiceOver labels for management UI and emulator controls | v1 |  | the logo is the "Game Menu" button, with Close Game inside the menu; the default save's star reads "Default Save"; controls not playable by VoiceOver (accepted) |
| partial | Dynamic Type in normal UI | v1 |  | SwiftUI defaults; controller drawing fixed size |
| missing | Reduce Motion support | v1 |  | none |
| partial | Large/configurable touch targets | v1 |  | hit areas extend 10-12 pt beyond drawn controls; not configurable |
| missing | One-handed layouts | v1 |  | none |
| missing | Fully remappable controls; controller navigation | v1 |  | none |

Done: Good contrast / color-independent states; haptics never sole feedback.

### Settings inheritance

Nothing open.
| missing | Narrow Save Profile overlay (cheats, RTC, autoresume, rewind) | v1 | dec 9; later 7 |  |

Done: Resolver App -> System -> Game -> Build, only explicit overrides stored, inherited source
shown, Reset to Inherited; Implemented keys; Settings screens for App, System (Game Boy, Game Boy
Color), Game and Build.

### SDK / toolchain detection

Spec: later 5: MVP.

Nothing open.

Done: Standalone detector seam + gbtoolsid port (engines, toolchains, music/SFX drivers,
version/range, evidence, detector version, corpus revision), differential CI vs upstream; GB Studio
detection, including 4.3+ by version, multi-layer (GB Studio over GBDK + audio driver); Categorical
confidence; Runs on import and patching, stored per Build, shown in Import Review, promotion and
Technical Info (which detects again); Quick Play detects on demand in its Technical Info and at
Add to Library, never before the first frame; Feeds the save compatibility check.

### Included Games

Spec: later 10.

| Status | Item | Target | Spec | Notes |
|---|---|---|---|---|
| missing | Optional Included Games manifest (ID, hashes, licenses, permission record, releaseApproved gate) imported through the normal path | v1 |  |  |

### CI / generated pipelines

Spec: later 11.

| Status | Item | Target | Spec | Notes |
|---|---|---|---|---|
| missing | no-intro-update, toolchain-fingerprints-update, shader-catalog-update, included-games-verify, fixtures, license-audit, privacy-audit, openvgdb-update (disabled) | v1 | docs/ci.md "Not built yet" |  |
| partial | MVP gate | MVP | mvp "Required tests" / mvp-verification.md | package tests cover required tests 1-13 and 15, and an app test covers 14 (controller disconnect); every physical-iPhone (L4c) check is unchecked |

Done: ci.yml (L1/L2/L3, gbtoolsid differential, test-coverage, hygiene) and ios-build.yml (simulator
build/tests).

### v1.1 targets

Spec: all missing.

| Status | Item | Target | Spec | Notes |
|---|---|---|---|---|
| missing | Link cable, local dual-core first; nearby/SharePlay initiation; no Multipeer | v1.1 |  | no LinkCableCapability |
| missing | GB Studio save migration with old/new variable maps | v1.1 |  |  |
| missing | Game Boy Camera | v1.1 |  | no CameraCapability |
| missing | Game Boy Printer with preview/save/share | v1.1 |  | no PrinterCapability |
| missing | RAR import (tentative) | v1.1 |  |  |
| missing | Visual skin/layout authoring beyond the lightweight editor | v1.1 |  |  |
| missing | Video/GIF capture; screenshots and clips framed like a Game Boy, shared from the game menu | v1.1 | D 2026-10-05 |  |
| missing | Browse and download games: itch.io's Game Boy tag in an in-app browser and Homebrew Hub (hh.gbdev.io) by its API, from the library's + menu; downloads go straight to Import Review, with Quick Play | v1.1 | D 2026-10-05 | needs zip import; the app's first network use, so revisit the privacy manifest and label; confirm App Store guideline 4.7 wording |
| missing | `.gbproject`-style project import/export | v1.1 |  |  |
| missing | Better ROM comparison + BPS generation | v1.1 |  |  |
| missing | iPad side-by-side manual/game | v1.1 |  |  |

### Later

Spec: all missing.

| Status | Item | Target | Spec | Notes |
|---|---|---|---|---|
| missing | Developer tools: a watched Files or iCloud Drive folder whose new ROMs import as new Builds; GitHub releases or CI builds as Builds; a tester bug report bundle (save, state, screenshot, Build hash, toolchain) | later | D 2026-10-05 |  |
| missing | iOS integration: Continue Playing widget, Siri and Shortcuts ("Resume <game>"), Spotlight | later | D 2026-10-05 |  |
| missing | mGBA/GBA; network/internet link; RetroAchievements; full debugger/disassembler/VRAM; deterministic replay/movies; arbitrary .slang/.slangp; Apple TV/macOS/iPad-first polish; creator-controlled homebrew publishing; document annotations/OCR/bookmarks; community layout gallery; battery-saver mode; per-Build alternate core choice; bulk canonical rename | later |  |  |

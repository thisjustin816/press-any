# GB Emulator: Full Product Specification and Roadmap

## Product thesis
An iPhone-first GB/GBC emulator that is excellent for ordinary play but uniquely strong for ROM-hack/homebrew testing. The library models a Game as a persistent identity with multiple immutable Builds, reusable Save Profiles, patch provenance, and developer/debug context. SameBoy ships first; the frontend is multi-core by design so mGBA can add GBA later.

## Governing UX principle
**Simple by default, deep when wanted.** Normal users get one-tap Play, good automatic metadata/artwork, sane controls, authentic display presets, autosave/autoresume, and straightforward saves. Power-user and development tools appear through Customize, overflow/long-press actions, Advanced, or Developer Mode. Do not expose a setting merely because an implementation has a parameter.

## Platform
- iPhone-first, iOS 17+.
- iPad compatibility should not be intentionally broken, but iPad-specific polish/multitasking is later.
- Light + dark appearance in v1.
- TestFlight before App Store.
- Offline-first core experience.

## Emulation cores
### v1
SameBoy for GB/GBC/SGB.

### post-v1
mGBA adapter for GBA.

### Core policy
- Multi-core `EmulatorCore` abstraction from day one.
- Optional capabilities: rewind, cheats, memory access/search, RTC, link cable, camera, printer, etc.
- Latest compatible core is selected on a Build's first launch, then pinned to that Build.
- New core availability produces a nonintrusive notice.
- Updating creates a reversible core-migration checkpoint; old states remain tied to old core serialization context.
- Automatic DMG/GBC/SGB model selection with App -> System -> Game -> Build overrides.

## Persistence and storage
- GRDB/SQLite for metadata and relationships.
- Managed filesystem for binary assets.
- SHA-256 identity/integrity.
- Content-aware deduplication.
- Source assets vs rebuildable cache explicitly modeled.
- Atomic save writes.
- Verify important assets when used, especially after sync/restore/migration.
- Storage screen by category with safe cache cleanup.
- Under pressure, only disposable generated-ROM cache and expired Quick Play data may be automatically removed.

## Canonical domain model
### Game
Stable user-facing identity. Owns metadata, aliases, collections/tags, default artwork/docs, preferred Build, preferred Save Profile, settings overrides, aggregate play stats.

### Build
Exact executable ROM identity. Immutable ROM hash. May be imported complete ROM or generated from Base Build + patch recipe. Stores region/language/revision/version, lineage, toolchain detection, preferred Save Profile, core pin, settings overrides, optional artwork/docs overrides, notes and per-Build playtime.

### Base Builds
A Game may have multiple bases (regions/revisions). Patch recipes always reference exact base hash.

### Save Profile
Named playthrough battery save. Manually creatable: blank, duplicate, import `.sav`, Quick Play promotion, future migration. Flat list with subtle ancestry. One current battery save per profile. Narrow overrides for cheats/RTC/autoresume/rewind where appropriate. Per-profile playtime/last played/session count.

### Save State
Build + Save Profile + core serialization context. Screenshot, timestamp, playtime, optional label and cheat-set metadata. Never cross Build boundaries.

### Patch / PatchRecipe
IPS/BPS v1. Source patch retained permanently. Ordered stack modeled. Recipe mutation creates new Build. Generated output is cache and must hash to expected result.

### Documents
Managed copies associated with Game, Build, or both; semantic type Manual/README/Changelog/Guide/Map/Other.

### Artwork
Multiple typed assets: front/back box, cartridge/label, title screen, screenshot, logo, custom/fan, extensible types. One primary library image. Game-level default with optional Build override. Original image preserved; presentation crop/reposition is non-destructive.

## Library organization
- Grid, compact list, and optional Developer view.
- Manual collections/folders plus smart collections (system, homebrew, ROM hacks, favorites, recent, etc.).
- Arbitrary tags on Games and Builds, tucked behind long-press/overflow/detail editing.
- Sorting: title/recently played/added/playtime/release year/system/developer/publisher plus advanced hack author/build version/date/last Build change/manual order.
- Favorites, last played, total playtime, play count, Build-level and Save Profile-level aggregate statistics. No permanent per-session log in v1.
- Preferred Build controls one-tap Play; explicit user preference is never silently changed by recent use.
- Build preferred Save Profile falls back to Game preferred Save Profile.

## Search
- SQLite FTS5 live search.
- Index Game title, aliases, canonical/original filenames, hack title, author, version, system, region, Build names, tags/collections, document titles and other useful metadata.
- Exact/primary-title matches rank above incidental metadata.

## ROM identity, naming, and metadata
- Bundle baseline No-Intro-derived identity data where licensing permits; support validated downloadable updates.
- Use No-Intro parent/clone/family relationships as high-confidence grouping evidence, not as an inflexible definition of Game.
- Unambiguous family relationships may be pre-grouped in Import Review; user can change before commit.
- Revisions/regions/languages normally become Builds of same Game; user may separate.
- Parse No-Intro naming and ROM-hack bracket conventions best-effort in v1, with clean title/Build and normalized filename suggestions in import, Quick Play promotion and patching.
- Extract hack title/author/version into structured metadata instead of cluttering display title.
- Preserve original imported filename permanently.
- Normalize internally; physical Rename to Canonical Name is explicit.
- Unknown ROM/hack may be manually matched to known Game/base lineage even if base ROM is absent.
- Metadata has source/confidence/provenance. User overrides win locally; technical hashes are immutable.
- Canonical/provider metadata may refresh quietly without overwriting user overrides.

## Import architecture
`ImportAnalyzer -> ImportPlan -> ImportReview -> transactional Commit`

### Sources
- Files/document picker.
- Share Sheet/Open In. Direct `.gb`/`.gbc` files offer Quick Play or Import Review; `.ips`/`.bps` files require choosing a Game and base Build. Receive a bounded copy before review, keeping the sender's file untouched. During gameplay the file opens over the paused game; Quick Play closes that game first.
- ZIP + 7z v1; RAR tentative v1.1.
- Archives are temporary containers and are not retained.
- Safe archive handling: path traversal protection, nested-depth and decompression limits, malformed/password-protected handling, no executable behavior.

### Multi-asset review
Analyze all assets before mutation. Group likely ROMs/builds, patches, saves, artwork, manuals/docs and metadata. Artwork review visually compares auto-fetched/default, imported, and existing choices. Unsupported/unwanted archive content is not retained unless explicitly imported as documentation/attachment.

### Duplicate handling
Exact duplicate ROM content is deduplicated, but newly supplied artwork/saves/manuals/metadata/patches are still reviewed and may be imported.

### Development imports
Imports may analyze while gameplay continues. If a likely new Build of current Game arrives, show nonintrusive New Build Ready with Switch Now/Later. Developer Mode offers Restart into New Build; never swap ROM bytes live.

## Game/Build restructuring
- Make Separate Game: Move or Copy, default Move.
- Carry likely relevant Game-level assets via review; Build-scoped data follows automatically.
- Preserve base-game lineage after promotion.
- Merge into Game: move/copy Builds with asset/save review.
- Lightweight Build timeline: versions, hashes, parent relationships, notes, import/activation history.
- v1 Build comparison: metadata + changed byte/range counts, ROM size/bank differences, header changes. Symbol-aware diff/patch generation later.
- Import suggests Build roles for review: development releases default Base + Preferred; ROM hacks and patch-created Builds default Preferred but not Base; ordinary additional images remain conservative.

## Patching
- v1 formats: IPS + BPS.
- Pluggable patch-format architecture.
- Preserve base ROM, patch source, recipe, provenance and output hash.
- Validate base when possible; allow explicit Apply Anyway.
- Editable stacks: reorder/enable/disable/add/remove; edits produce a new Build.
- Generated ROM is rebuildable cache.
- Future: BPS generation from base vs modified Build; other formats only as demand warrants.

## Save system
### Battery saves
- One `.sav` per Save Profile.
- Profiles may be shared by compatible Builds.
- No general rolling `.sav` history; use profile duplication/forking for isolation.
- Explicit replace/delete is confirmed.
- Quick Play and migration operate on copies, not source profiles.

### Compatibility-aware Build switching
- Snapshot/flush current save.
- Analyze toolchain/build compatibility.
- Normal compatible switches stay one-tap.
- Risky switches offer migrate (when supported), duplicate into new profile, use same anyway, or blank save.
- GB Studio detection from the MVP; accept variable-map sidecars as Build metadata. Automatic GB Studio save migration targeted v1.1 and must not claim reliability without the required old/new maps.

### Save states
- Dedicated Auto State plus rolling history default 5.
- Quick Save + configurable fixed slots + unlimited named states.
- State thumbnail + timestamp + Build + playtime + optional label.
- Configurable automatic cleanup; pinned/favorited states exempt.
- State cheat configuration recorded as metadata; loading offers restore rather than silently changing cheats.
- State loading across different Builds is not a normal operation.

### Lifecycle
- Battery save flush + Auto State on background/normal exit/session switch.
- Global autoresume default Always; override Always/Ask/Never per relevant context.
- Backgrounding pauses emulator/audio.
- Separate crash-recovery checkpoint; after abnormal termination offer Recover Session / Start Normally.

## Quick Play
- Temporary sandbox; no permanent library mutation until promotion.
- Default retention 24h; configurable immediate/24h/7d style policy.
- Exact existing Build may offer Use Existing Save, implemented by copying into sandbox.
- Promotion can keep library save, replace after safety copy, or create new Save Profile.
- Temporary session can collect save/state/screenshots/notes/debug context.

## Cheats and memory tools: v1
- Full cheat management.
- Game Genie/GameShark/SameBoy-supported formats as applicable.
- Pluggable verified-ROM cheat database; browse/selectively add, never auto-enable.
- Optional groups/categories + search.
- Cheat search: exact, unknown, changed, unchanged, increased/decreased, delta, greater/less; signed/unsigned 8/16-bit and hex baseline.
- Result actions: edit, freeze, watch, create cheat, copy address.
- Named search sessions survive within current emulation session only.
- Memory Watch list with optional Developer HUD and short in-memory history/min/max/graph.
- Immediate Developer Mode writes with Undo Last Write where possible.
- Frame advance and frame counter.
- Full debugger/disassembler/VRAM tools later.

## Screenshots, notes, and debug context
- In-app screenshot gallery; every capture associated with exact Build.
- Optional capture context atomically records selected watches, named variables when symbols/maps exist, selected memory ranges, registers where core supports, frame/time, Build/hash/patch stack, RTC, cheats, Save Profile, core/settings.
- Full RAM snapshot is opt-in Developer Mode only.
- Export original clean image, metadata where supported, or rendered Build Info/Bug Report overlay.
- Bug-report export has a privacy checklist; full memory/save/notes require explicit inclusion.
- Game notes, Build notes, timestamped gameplay notes; gameplay note may attach screenshot/debug context.

## Rewind and speed
- Rewind presets: 5s, 15s, 30s, 1m, 2m, 5m.
- Memory-budgeted; effective duration may reduce under device pressure.
- Survives brief background/resume, not persisted as a long-term timeline.
- Rewind audio muted by default; optional if quality is acceptable.
- FF: 1.5x, 2x, 3x, 4x, 8x, Unlimited; hold/toggle; audio Accelerated or Mute.
- Slow motion: 0.25x, 0.5x, 0.75x.

## Rendering and shaders
- SameBoy framebuffer -> Metal texture -> color/display stages -> shader chain -> local/external target.
- Native core timing; adaptive display presentation including high-refresh iPhones.
- Correctness/full-speed emulation wins over optional effects.
- Thermal pressure degrades optional shaders/rewind/background work first.
- v1: curated RetroArch-compatible Metal shader library, not arbitrary `.slang/.slangp` import.
- Before freezing bundle, perform community survey of GB/GBC favorites. Explicit candidates include lcd1x, lcd3x, Pixel Transparency combinations, DMG/GBC LCD treatments, color correction, sharp bilinear, CRT/scanline options.
- Shader pipeline components/parameters inherit independently.
- Users can save named presets.
- Live switching through Quick Actions.
- System-authentic default; raw pixels readily available.

## Layouts, skins, touch
- Built-in Game Boy and Playtiles layouts from the MVP; Minimal, Fullscreen and one-handed presets come with the layout editor. "Classic" names a controller theme.
- Lightweight v1 editor: screen/control position/size, opacity, touch hitboxes, portrait/landscape independently, small built-in visual control styles.
- Edit Layout from gameplay pauses on current frame for alignment.
- Game-specific layout override vs update shared preset choice.
- Delta and Manic import adapters -> internal native skin model; preserve source package; preview/report unsupported elements.
- Native layout import/export through Files/Share Sheet.
- Hardware presets for passive accessories such as Playtiles/GameBaby; passive accessories are manual selection, with device-specific calibration offsets. Identifiable connected accessories may be suggested, never force-switched.
- Sliding D-pad, natural diagonals; sliding A/B; multitouch A+B. Playtiles widens straight-direction zones: a diagonal's weaker axis must exceed 65% of its stronger axis and the center dead zone. Deliberate diagonals remain available.
- Subtle pressed-state visual feedback.
- Light touch haptics by default; automatically suppressed while physical controller is active unless overridden.
- Optional gameplay gestures off by default.
- Optional Turbo A/B actions, not in default layout.

## Controllers and rumble
- Apple GameController support for iOS-supported Xbox/PlayStation/Switch-compatible/MFi/generic devices.
- Named reusable controller profiles by type.
- Global defaults with system/game overrides; Build override where settings hierarchy applies.
- Multiple controllers detected; v1 selects Player 1, architecture reserves Player 2.
- Physical controller active -> hide touch controls by default, touch-to-reveal.
- Disconnect -> pause + reveal touch controls + notice.
- Shared action system powers Quick Actions, controller hotkeys and skin controls.
- Cartridge rumble routing default: controller preferred, phone fallback; Phone/Controller/Both/Off override.
- Separate phone/controller intensity controls.

## Quick Actions
Fully reorderable/customizable with favorites. Actions may include save/load state, rewind, FF, slow motion, screenshot, note, manual, cheats, shader, Build/Profile switch, Build info, watches, frame advance, layout editing, etc. Do not create separate command implementations for menus/controllers/skins.

## Manuals/documents
- PDF, CBZ, PNG/JPEG/WebP image sets, TXT, Markdown.
- Managed app copies.
- Game/Build/both association and semantic types.
- Manual available from gameplay; opening pauses, closing restores prior running/paused state.
- Remember last-read position.
- Search TXT/Markdown/text PDFs only if straightforward; no OCR v1.
- iPad side-by-side later.

## Artwork
- Automatic fetch on import; setting to disable automatic downloads.
- Priority: manual override -> hack-specific -> base-game inherited -> generated fallback.
- Pluggable providers.
- Cache only selected primary artwork unless user explicitly saves additional assets.
- No automatic refresh after selection; manual Check for New Artwork.
- Visual comparison during import/selection.

## External display / AirPlay
- v1 hard requirement.
- External display is independent gameplay render target; phone becomes controller-focused companion.
- Quick Actions/manual/states/Build switching remain available on phone.
- Display-specific scaling/aspect/shader/safe-area treatment.
- Chromecast intentionally out of current scope.

## iCloud
Target v1 but subject to milestone checkpoint after local data model is stable.
- Sync full library state except ROM blobs.
- Sync metadata, saves, states, cheats, settings, tags/collections, artwork/manual overrides, patches, skins/layouts, notes, screenshots/debug captures, stats and relevant local catalog metadata.
- Tombstone deletions; Recently Deleted = 30 days; stale offline devices cannot resurrect deleted data.
- Field-level merge where safe.
- Divergent `.sav` conflicts preserve both and require explicit resolution; option to split one into new Save Profile.
- iCloud is synchronization, not hidden save-version history.

## Community Catalog
Target v1 but may move to v1.1 at milestone review.
- Opt-in read/contribute.
- Reading no account; contribution requires lightweight identity; public attribution optional.
- Separate trust layers: canonical verified sources, curated catalog, community submissions, local user overrides.
- Contributions moderated; structured source evidence where available; rejection reason returned; field-level correction submissions.
- Local metadata edit may offer Suggest This Correction; never auto-submit.
- Metadata, artwork and legally appropriate patch references/uploads. Never commercial ROM hosting/acquisition.
- Homebrew binary publishing later through explicit creator-controlled rights-aware workflow.
- Update discovery: quiet badge by default; optional pre-download verified updates; per-Game overrides.
- Update details: version/date/author release notes/source/known compatibility where data exists.
- Update action: trusted download when legally available -> verify -> normal Import Review -> add as new Build, keep old for rollback.

## Automatic artwork/metadata databases
- Bundled offline baseline plus validated downloadable identity metadata updates.
- Pluggable artwork/metadata provider chain.
- Exact providers and licensing/terms require implementation-time research.
- Build an opt-in homebrew/ROM-hack catalog with provenance and moderation; do not conflate it with canonical No-Intro data.

## Backups and migration
- Export + import Library Backup.
- Versioned documented archive, manifest + ordinary files, checksums/schema version.
- User assets included; ROMs excluded by default with explicit personal full-backup option.
- Optional password encryption.
- Restore merges stable IDs/hashes with conflict review; explicit Replace Entire Library mode.
- Migration Report before commit and retained summary afterward.
- Future migration adapters for Delta, Manic, Afterplay, Playtiles-related exports and other ecosystems; map only what can be represented safely and report incompatible save states/skins/etc.

## Deletion and undo
- Dependency-aware deletion.
- Recently Deleted 30 days.
- Synchronized tombstones.
- Lightweight Undo for recent structural operations where practical.

## Performance
- Native timing and full-speed correctness first.
- Low-latency adaptive audio; audio never dictates game speed.
- Thermal-aware degradation of optional features only.
- Memory-budgeted rewind.
- Default shader must sustain full-speed GB/GBC on minimum supported hardware chosen for QA.

## Privacy and telemetry
- Crash reporting opt-in.
- Automatic reports may include app/device/core/non-content feature diagnostics.
- Never automatically upload ROM/save/state bytes, screenshots, memory, filenames, notes or library contents.
- Debug/bug reports are explicit exports with checklist/preview.

## Accessibility baseline
Practical emulator-focused support: Dynamic Type in normal UI, good contrast/color-independent states, Reduce Motion, configurable/large touch targets, one-handed layouts, remappable controls, controller navigation where practical, sensible VoiceOver for management UI/emulator controls, and haptics never as sole feedback. Specialized gameplay narration/vision interpretation is not a v1 requirement.

## v1.1 targets
- Link cable: local dual-core first; future nearby/network transport. Proximity/SharePlay may initiate compatible sessions. Do not build new transport on deprecated Multipeer Connectivity.
- GB Studio save migration when required old/new variable maps are present and version compatibility is validated.
- Game Boy Camera using camera/photos/test image where appropriate.
- Game Boy Printer with preview/save/share.
- RAR import tentative.
- Visual skin/layout authoring beyond lightweight editor.
- Video/GIF capture.
- `.gbproject`-style project import/export (metadata/patches/artwork/layouts/docs/optional saves; base ROM excluded by default).
- Better ROM comparison and BPS generation.
- iPad-specific side-by-side manual/game UI.

## Later
- mGBA/GBA.
- Network/internet link cable.
- RetroAchievements.
- Full debugger/disassembler/VRAM tools.
- Deterministic replay/movie system.
- Arbitrary RetroArch `.slang/.slangp` importing if justified.
- Apple TV/macOS/iPad-first polish.
- Creator-controlled homebrew binary publishing.
- Advanced document annotations/OCR if demand justifies it.

## Explicitly out of current scope
- Chromecast.
- Commercial ROM acquisition/downloading.
- Silent ROM repair.
- True live ROM-byte hot swapping.
- Full wiki/social comments/ratings in Community Catalog.

## Release gates
### Architecture Proof / MVP
Must pass the workflow and tests in `gb-emulator-mvp.md` before broad v1 feature work.

### v1 Core gate
Original hard requirements and product-defining systems must be stable: GB/GBC SameBoy, Build/library model, save system, states/autosave, rewind/FF, rumble, patching, cheats/memory tools, custom layouts/presets + Delta/Manic compatibility, curated shaders, Bluetooth controllers, automatic artwork, AirPlay/external display, safe, bounded imports, Quick Play.

### v1 Auxiliary checkpoint
iCloud and Community Catalog target v1. If the local emulator is stable and either backend is the sole blocker, conduct an explicit ship/no-ship review and permit moving that subsystem to v1.1 without weakening the local data model needed to add it safely.

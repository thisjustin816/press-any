# iOS Game Boy Emulator: Canonical Decision Log

This file is the canonical record of the original product decisions. `gb-emulator-later-decisions.md` and `docs/decisions.md` record decisions made since, and win where they conflict.

## 0. Corrections / conflict resolution

- Minimum OS is **iOS 17+**.
- v1 is **iPhone-first**. iPad-specific polish/multitasking comes later. Do not block basic compatibility unnecessarily, but do not make iPad UX a v1 launch requirement.
- **Chromecast is out of current scope.** Keep output architecture extensible, but no Cast implementation requirement now.
- GB/GBC core is **SameBoy**. GBA is architected for now but ships later using **mGBA**.
- Save states are **always Build-specific**. They are not shared across Builds, even when battery saves are.
- Battery-save safety should rely primarily on **Save Profile isolation/forking**, not an accumulating hidden rolling `.sav` backup system.

# 1. Product direction

The app is an iPhone-first GB/GBC emulator with unusually strong ROM-development, ROM-hack, version-management, save-isolation, patching, metadata, and debugging workflows.

The defining model is not "one ROM file = one library item." A persistent **Game** owns one or more **Builds**, and Builds can share or fork **Save Profiles** as appropriate.

Initial system support:
- GB
- GBC

Future:
- GBA via mGBA

Core strategy:
- SameBoy for GB/GBC
- mGBA later for GBA
- Multi-core-capable architecture from day one

Distribution:
- TestFlight first
- App Store afterward

Appearance:
- Light and dark mode in v1

Crash reporting:
- Optional / opt-in in v1

# 2. Platform / architecture

## Minimum OS
- **iOS 17+**

## UI architecture
- SwiftUI is suitable for library, settings, metadata, import flows, etc.
- Gameplay should use a dedicated gameplay controller / rendering surface rather than pushing the emulation framebuffer through ordinary SwiftUI layout.
- Metal renderer.

## Persistence
- **GRDB + SQLite** for metadata / relationships / migrations.
- ROMs, saves, save states, artwork, patches, manuals, etc. remain files in managed storage rather than giant DB blobs.

## Core abstraction
Design a core-agnostic adapter/protocol from day one.

Expected common responsibilities include:
- ROM loading
- start / pause / reset / stop
- input
- audio/video output
- battery save import/export
- save-state serialize/deserialize
- rewind
- fast-forward / speed controls
- rumble callbacks
- memory access where supported
- cheat APIs where supported

Optional capabilities should be modeled separately rather than forcing every core to expose identical features, e.g.:
- CheatSearchCapability
- MemoryAccessCapability
- CameraCapability
- PrinterCapability
- LinkCableCapability
- RTCControlCapability

## Core version behavior
- On a Build's **first launch**, use the latest compatible installed core by default.
- After first launch, **pin the core/version to that Build** for determinism/compatibility.
- If a newer core version becomes available, show a non-intrusive "core update available" notice.
- Core migration/change is an explicit user action.
- Later, where multiple compatible cores exist, user may explicitly choose a different core for a Build.

# 3. Primary data model

Canonical terminology:

**Game -> Builds -> Save Profiles**

## Game
Persistent library identity. It does not disappear or duplicate simply because the ROM, artwork, save, or patch changes.

Possible properties / relations:
- stable UUID
- display title
- canonical/base title
- alternate titles
- system
- region/language metadata
- developer/publisher where known
- ROM-hack/homebrew metadata where relevant
- artwork collection
- manuals
- tags
- notes
- collections
- preferred/default settings
- Builds
- Save Profiles
- aggregate play statistics

## Build
A playable ROM revision/version/variant under a Game.

A Build may come from:
- complete imported ROM
- base ROM + one patch
- base ROM + patch stack
- generated/derived variant
- Quick Play promoted into library

Patched and fully imported ROM variants are **Unified Builds** in the UI. Provenance remains available in Build details.

Build metadata should be able to store:
- stable UUID
- display name
- version
- author/team where applicable
- notes
- source/provenance
- ROM SHA-256
- parent Build
- patch recipe / patch stack
- import date
- activation history
- detected toolchain/engine
- toolchain version/confidence where known
- variable/symbol sidecars where available
- pinned core/version
- build-specific settings overrides
- play statistics

## Save Profile
Manually creatable playthrough save identity, independent of Build ownership.

Examples:
- Main
- Nuzlocke
- Speedrun
- Testing
- New Game

Creation methods:
- blank save
- duplicate existing profile
- import `.sav`
- create from Quick Play
- future migration from another Build/toolchain

Each profile can have:
- current battery save
- RTC state where applicable
- icon/badge
- default/preferred Build association as needed
- limited profile-specific settings
- ancestry metadata when copied/forked/migrated
- aggregate stats: total playtime, last played, session count, created date

Save Profiles are shown in a flat list. If duplicated/forked, show subtle ancestry such as "copied from Main" rather than a full tree UI.

# 4. Content-addressed ROM / asset storage

Use content hashing (SHA-256) and managed storage so exact duplicates can be deduplicated and relationships remain stable.

Do not use the ROM file itself as Game identity.

Benefits required by the design:
- exact Build identification
- deduplication
- save-state compatibility checks
- verification status
- patch provenance
- rollback/history
- future sync safety

# 5. Builds, patches, and original ROM preservation

Hard requirements:
- Update/replace ROM content without creating a duplicate Game.
- Keep original/base ROM cached unless explicitly deleted.
- Switch between Builds/patch variants.
- Patched Builds and full-ROM Builds appear uniformly as Builds.
- Patch provenance is retained.

Patch stacks are part of the architecture from the beginning, even if the first UI is simple.

Patch formats discussed as likely v1 candidates:
- IPS
- IPS32
- BPS
- UPS

Settled by Q78: IPS and BPS for v1. IPS32, UPS, xdelta/VCDIFF and other formats come later through the pluggable patch handling.

A Build timeline is required:
- version/name
- parent relationships
- hashes
- notes
- import/create dates
- activation history

Build comparison in v1:
- metadata comparison
- binary changed-byte count/ranges
- ROM size changes
- bank-level differences where meaningful
- header differences

Later:
- symbol-aware diffing
- more advanced visual diff tools
- patch generation (especially BPS)

# 6. Build switching and save compatibility

Normal behavior:
- A newly created/imported Build inherits the currently active Save Profile by default.
- Multiple compatible Builds may deliberately share one Save Profile.

Important safety rule:
- **Save states are never shared across Builds.**

Build activation should perform compatibility analysis and only interrupt the user if there is meaningful risk.

When save-layout incompatibility is suspected:
- prefer creating/forking a Save Profile instead of silently reusing the existing battery save
- allow the user to deliberately reuse it anyway
- use migration only when there is sufficient information

Do not maintain a general rolling hidden battery-save history. The safer primary model is Save Profile isolation/forking.

For an explicit destructive save replacement, keep a short-lived safety copy until success is confirmed.

# 7. GB Studio / homebrew toolchain handling

Toolchain/engine detection is a standard Build property.

Desired detection categories include tools such as:
- GB Studio
- GBDK
- ZGB
- others detectable through known open-source fingerprint approaches

Store:
- detected engine/toolchain
- possible version/range
- confidence
- availability of symbol/global-variable maps
- save compatibility status

GB Studio consideration:
- Do not assume `.sav` compatibility between Builds.
- If global-variable maps from old/new Builds are available, future save migration can match named variables safely.
- Do not claim reliable migration from binaries alone when required source-level mapping data is missing.

v1:
- detect toolchain where possible
- attach/import variable-map sidecars as Build metadata
- warn about likely save incompatibility
- fork/duplicate profiles safely
- schema ready for migration

v1.1:
- actual GB Studio save migration, version-gated and validated

# 8. Save states and lifecycle autosave

Manual save states:
- always Build-specific
- should also retain Save Profile context to avoid accidental cross-playthrough use
- screenshot thumbnail
- timestamp
- Build
- playtime
- optional user label

State types:
- Quick Save
- configurable fixed slots
- unlimited named states
- separate protected lifecycle Auto State

Retention:
- configurable automatic cleanup for manual states
- pinned/favorited states are exempt
- cleanup should respect Build boundaries

Autosave lifecycle behavior:
- flush battery save on background/exit
- create/update dedicated Auto State
- keep a rolling Auto State history (default target: last 5)
- autoresume is configurable at App, System, Game and Build scope, like other settings
- global default: Always Resume
- choices: Always / Ask / Never
- if state restore is incompatible/fails, safely fall back to normal boot

Rewind buffer persistence:
- survive brief app background/resume
- do not persist as a permanent cross-session timeline

# 9. Save Profile behavior

Save Profiles are manually creatable even for the same Build.

Launch behavior:
- remember the last/default Save Profile and launch with one tap
- long-press Play or overflow menu allows choosing another

Limited Save Profile-level overrides are allowed for playthrough-specific behavior such as:
- cheats
- RTC offset
- rewind where appropriate

Do not make Save Profile a full fifth visual/controller/theme settings layer.

Save Profile locking/protection:
- **deferred / not a v1 requirement**
- destructive Replace/Delete operations must still clearly identify the target and require confirmation

# 10. Settings inheritance

Canonical hierarchy:

**App defaults -> System defaults -> Game overrides -> Build overrides**

More specific wins.

A child level stores only actual overrides.

UI requirements:
- show where an inherited value comes from
- provide "Reset to Inherited"

Applicable to settings where sensible, including:
- shaders/display
- layout
- rewind
- fast-forward behavior
- audio options, except Sound (whether the game follows the silent switch), which is app-wide
- controller mappings/profiles
- autoresume
- RTC
- rumble

Save Profile adds only narrow contextual overrides as described above.

# 11. Rewind, speed, and timing

Rewind:
- hard requirement
- rewind granularity/behavior is user-configurable with presets
- duration presets: see Q103
- mute audio by default while rewinding
- optional rewind audio if implementation quality is acceptable

Fast-forward:
- hard requirement
- user-configurable speed presets
- audio behavior: user can choose accelerated audio or mute

Slow motion:
- include v1 presets such as 0.25x / 0.5x / 0.75x (exact final preset list can be tuned)

Frame advance:
- v1 developer feature
- bindable to quick actions/controllers

RTC:
- real system time plus manual offset per Save Profile
- advanced RTC testing controls may be exposed in Developer Mode

# 12. Cheats / memory / developer tools

Full cheat implementation is v1, not deferred.

Cheat management:
- add/remove/enable/disable
- persistence
- appropriate native cheat formats per system/core

Memory cheat searcher / updater:
- exact value
- unknown initial value
- changed / unchanged
- increased / decreased
- increased/decreased by value
- greater/less than
- useful integer/hex data types

Result actions:
- edit value
- freeze
- watch
- create cheat
- copy address

Watch List:
- v1

Developer Mode:
- optional toggle; normal player UI remains clean
- deeper tools hidden behind it

Developer Mode features include:
- memory search/editor
- watch list
- ROM hashes
- patch provenance
- frame advance/counter
- Build information
- RTC overrides
- advanced save information
- future debugger tools

Full debugger/disassembler/VRAM viewer can come later.

# 13. Screenshots, notes, and debug context

Screenshots:
- stored in an in-app gallery
- associated with exact Build
- optional export/share to Photos/other destinations

Export can optionally add:
- metadata where supported
- rendered text/info strip directly on image

Useful selectable fields:
- Build name/version
- ROM hash/short hash
- core/core version
- timestamp
- frame number
- system/game
- active patches
- developer notes

Presets may include:
- Clean
- Build Info
- Bug Report

Optional atomic Capture Context at screenshot time:
- current memory-watch values/addresses
- named variables when symbols/GB Studio globals are available
- selected memory ranges
- CPU/register state if exposed
- frame number / emulation time
- Build/hash/patch stack
- RTC state
- enabled cheats
- Save Profile identifier
- core/version and relevant emulator settings

Do not dump all RAM by default. Full-memory snapshot is an opt-in Developer Mode option.

Bug-report export can bundle screenshot plus human-readable Markdown/JSON context.

Notes:
- Game notes
- Build notes
- timestamped gameplay notes
- gameplay notes can attach screenshot/debug context

# 14. Quick Play / temporary smoke-test sessions

Quick Play is a **v1 requirement**.

Opening a ROM should allow:
- Quick Play
- Import to Library

Quick Play:
- does not create a permanent Game/Build
- launches from a temporary sandbox/workspace
- still hashes and identifies; toolchain detection runs on demand (Technical Info, Add to Library), never before the first frame
- can use battery saves, autosave state, screenshots, notes, debug captures
- can later be promoted into the library while preserving generated data
- if matching an existing Game, promotion can become "Add as New Build"

Retention:
- configurable temporary retention
- default: 24 hours
- examples: Immediately / 24 hours / 7 days
- Recent Quick Plays area
- manual Keep / Import / Discard

Existing-save behavior:
- default isolated
- if exact Build match exists, offer "Use Existing Save"
- **copy** the chosen library save into the Quick Play sandbox
- Quick Play never writes directly to the library Save Profile

When promoting Quick Play to library, offer:
- keep existing Save Profile unchanged
- update/replace with Quick Play save (with safety confirmation/copy)
- create a new Save Profile from Quick Play save

Future possibility:
- Quick Play a patch against a selected base ROM without permanently creating a Build unless promoted

# 15. Library organization / search

Library supports:
- user-created collections/folders
- smart collections

Examples of smart collections:
- GB
- GBC
- Homebrew
- ROM Hacks
- Favorites
- Recently Played
- Builds with updates

Views:
- box-art grid
- compact list
- optional developer-oriented view with Build/version/Save Profile details

Search:
- live results while typing
- dedicated SQLite FTS5 index
- search Game title
- alternate titles
- original/canonical filenames
- hack name
- author
- version
- system
- region
- Build names
- tags/collections
- document/manual titles where useful

Ranking should favor exact/title matches over incidental metadata matches.

Tags:
- arbitrary user tags on Games and Builds
- power-user feature, accessed through long-press/overflow/detail UI
- no prompts pushing tags into normal workflows
- tags participate in search and smart collections

Sorting:
- title
- recently played
- recently added
- playtime
- release year
- system
- developer/publisher
- hack author
- Build version/date
- last Build change
- custom manual ordering
- common sorts surfaced first; advanced under More

Play statistics:
- favorites
- last played
- total playtime
- play count
- per-Build playtime
- Game-level rollups
- Save Profile: total playtime, last played, session count, created date
- no detailed permanent session log in v1

# 16. Import pipeline

Import sources in v1:
- Files/document picker
- Share Sheet / Open In

Archive support:
- ZIP in v1
- 7z in v1
- RAR tentatively v1.1

Archives are **temporary import containers**, not retained library assets.

Importer architecture:

**ImportAnalyzer -> ImportPlan -> ImportReview -> Commit**

Rules:
- analysis happens before permanent mutation
- classify all detected content
- infer likely relationships
- fetch/resolve metadata/artwork before review where appropriate
- user sees one consolidated Import Review
- commit transactionally so failure does not leave half-imported library state

When multiple related assets are found, review should group them intelligently:
- ROM(s) / Build(s)
- patch(es)
- save(s)
- artwork
- manual/documentation
- README/changelog
- skins/layouts
- other supported assets

Artwork review:
- visually compare auto-downloaded artwork with imported/detected artwork
- existing artwork can also be shown when attaching to an existing Game
- user chooses rather than receiving an abstract yes/no prompt

Duplicate ROM handling:
- exact ROM blob is deduplicated
- still inspect the new import for useful new saves, artwork, manuals, patches, metadata, etc.
- if nothing useful is new, show where the ROM already exists instead of creating a duplicate

If multiple ROMs/builds are detected, allow attaching all to an existing Game or creating the appropriate Game grouping.

# 17. Naming / metadata normalization

Hard requirement:
- auto-conform / normalize standard ROM and ROM-hack naming
- metadata should become structured properties rather than cluttering UI titles

Parsing goals:
- No-Intro-style naming
- ROM-hack naming conventions such as square-bracket hack metadata (Maybe-Intro-style conventions)

Parse where possible:
- canonical/base title
- hack title
- author(s)
- version
- region
- language / translation language
- revision
- beta/prototype/status flags

Behavior:
- preserve original imported filename permanently in metadata
- generate a canonical normalized filename
- do not physically rename automatically
- offer explicit "Rename File to Canonical Name"
- support bulk rename later
- manual correction always wins

Unknown/unmatched ROM:
- offer Match Game... even if the base ROM is not present
- allow assigning lineage/base-game metadata without pretending the base ROM is owned/imported
- if correct base ROM is later imported, offer to link it

Matching priority concept:
1. exact hash/database match
2. recognized hack/homebrew catalog entry
3. filename/header parsing
4. fuzzy suggestions
5. manual Match Game...

# 18. ROM verification and databases

Every ROM gets SHA-256 identity.

Show verification status against known databases when possible:
- Verified
- Modified
- Unknown

Do not automatically repair/alter ROMs to make them match known dumps.

ROM header:
- read / validate / display in v1
- no header editing in v1

No-Intro / canonical metadata database:
- bundle an offline baseline snapshot
- allow periodically downloaded signed/validated updates
- imports/matching still work offline

# 19. Homebrew / ROM-hack Community Catalog

Build an opt-in Community Catalog alongside canonical databases.

Trust layers should remain separate:
- canonical verified sources
- curated catalog records
- community submissions / pending data
- local user overrides (highest local UI priority)

Privacy/content rule:
- opting into catalog use must not silently upload ROMs, saves, screenshots, debug memory, or local files
- binary/homebrew distribution, if added later, requires explicit creator-controlled rights-aware submission

v1:
- opt-in read access
- opt-in contribution
- submissions go through moderation/validation before becoming trusted/canonical

Accounts:
- reading does not require an account
- contributing requires lightweight identity/account
- public attribution can be optional

Correction flow:
- field-level correction UI from Game/Build screen
- after local metadata edit, optionally offer "Suggest this correction"
- do not auto-submit local edits
- include structured sources/evidence where available (release URL, author page, README, etc.)
- rejected corrections should return a short reason

Update discovery:
- detect newer homebrew/ROM-hack versions
- show nonintrusive update availability
- update detail includes version, release date, author-provided notes/changelog, source link, known compatibility information

Update action:
- from a trusted direct source, fetch/verify
- import as a **new Build**
- do not silently replace the old Build
- old Build remains for rollback

Background update checking:
- default: quiet checks + badge, no automatic download
- optional setting: pre-download verified updates
- per-Game update notification override supported
- no release-channel model required for now

# 20. Artwork

Automatic box art is a hard requirement.

On import, automatically fetch appropriate artwork unless disabled in settings.

Priority concept:
1. manual override
2. hack-specific artwork
3. inherited base-game artwork
4. generated placeholder

If base-game artwork is used for a hack, record that it is inherited rather than a destructive shared reference.

Artwork model supports multiple typed assets:
- front box
- back box
- cartridge/label
- title screen
- screenshots
- logo
- custom/fan art
- extensible future types

One asset is selected as primary library artwork.

# 21. Manuals / documentation

Manuals are first-class Game assets, not generic blobs.

A Game can have multiple manuals, e.g.:
- original manual
- hack manual
- alternate language manual

One can be designated default.

Supported v1 formats:
- PDF
- CBZ
- PNG/JPEG/WebP image sets
- TXT
- Markdown

Distinguish:
- Game-level manuals
- Build-level README/changelog/docs

Gameplay manual behavior:
- pause gameplay
- show manual/document in an overlay reader
- remember page/scroll position
- close to return immediately to game

Future iPad-focused release:
- side-by-side game/manual viewing

# 22. Skins / layouts

Hard requirements:
- custom layouts
- presets for hardware such as Playtiles and GameBaby
- Delta skin support
- Manic skin support

Internal model:
- own native layout/skin representation
- import adapters for Delta/Manic rather than using either schema as the app's core model

v1 visual editor scope:
- lightweight editor
- built-in presets
- hardware presets
- Delta/Manic imports
- drag/resize screen
- drag/resize controls
- control opacity
- touch-hitbox adjustment
- separate portrait/landscape layouts
- save custom preset

Later:
- full skin artwork/layer authoring
- more complex conditional layout editing

# 23. Shaders / video

v1 uses a **curated RetroArch-compatible shader library**, not arbitrary `.slang/.slangp` importing.

Renderer architecture should leave room for broader shader compatibility later.

Before finalizing the bundled set, do a dedicated community survey of current favorite GB/GBC shaders/presets.

Known desired examples to evaluate:
- lcd1x
- lcd3x
- pixel transparency variations/combinations
- system-appropriate GB/GBC color treatment

Shader design should consider separable/composable concepts such as:
- LCD/grid pattern
- pixel transparency
- color profile
- ghosting
- shader parameters

Video pipeline concept:
- core framebuffer -> Metal texture -> color correction -> shader chain -> scaling/cropping -> output

Display options should support concepts such as:
- integer scaling
- pixel-perfect scaling
- aspect fit/fill
- custom crop
- frame blending where useful
- GB/GBC color correction
- LCD ghosting

Exact curated shader set remains an explicit later research task.

# 24. Controllers / input / quick actions

Bluetooth controller support is a hard requirement.

Use Apple's controller APIs for supported Xbox/PlayStation/Switch-compatible/MFi/generic controllers.

Controller behavior:
- reusable **named controller profiles**
- inheritance model
- app-level default
- system override
- optional Game/Build override
- controller menu navigation
- hotkey combinations

Shared Action System:
- one action registry powers
  - in-game quick menu
  - controller hotkeys
  - skin buttons

Quick menu:
- fully reorderable/customizable
- sensible defaults
- favorite actions

Possible actions include:
- save/load state
- rewind
- fast-forward
- slow motion
- screenshot
- gameplay note
- manual
- cheats
- shader toggle/change
- Build info
- memory watches
- frame advance
- pause/menu

# 25. Rumble

Rumble is a hard requirement.

Design should route emulated rumble through a frontend abstraction capable of:
- iPhone haptics
- external controller haptics where supported
- both
- off
- intensity control where practical

Routing defaults are Q88; intensity is Q104.

# 26. External display / AirPlay

AirPlay / external-display support is a hard requirement.

Preferred behavior is not mere screen mirroring.

v1 external mode:
- game rendered on TV/external display
- iPhone remains controller / local UI
- separate external-screen layout

Potential modes:
- game only externally
- game + minimal HUD externally
- mirror full interface if desired

Should also work with compatible wired external displays where iOS exposes them.

Chromecast: deferred / not current scope.

# 27. Link cable

v1.1, not v1.

Architecture should include LinkCableCapability and transport abstraction from day one.

Likely progression:
- local two-session/device support
- nearby/network transport
- future internet transport

Future proximity UX:
- use Apple's proximity/SharePlay/AirDrop-style device-bump experience to initiate compatible link sessions where feasible
- proximity/session-establishment UI should be separate from actual serial-link transport

Do not build new architecture around deprecated Multipeer Connectivity.

# 28. Camera / Printer / other peripherals

Game Boy Camera:
- v1.1

Game Boy Printer:
- v1.1

Core capability hooks should exist in v1 architecture.

Super Game Boy support was discussed but not explicitly finalized; leave as an open decision.

# 29. iCloud / sync

Design for iCloud/sync from day one.

Target: **ship iCloud in v1 if practical**, but revisit scope after data structures/local persistence are stable. Do not let iCloud force a bad data model prematurely.

Stable UUIDs, sync-safe file organization, and conflict metadata are required from day one.

Important deletion rule:
- deletion must synchronize as state, not merely "record disappeared"
- use tombstones/deletion markers with identity + timestamp/version
- an offline device must not resurrect an object that was deleted elsewhere

Recently Deleted:
- dependency-aware deletion
- recoverable retention period
- restore is a synchronized operation
- after retention/sync safety, garbage-collect underlying files

Exact sync set likely includes:
- library metadata
- Save Profiles / saves
- save states
- cheats
- Build metadata
- patch files
- artwork overrides
- skins/layouts
- settings

ROM blobs are explicitly excluded from iCloud sync in v1 (Q89).

# 30. Deletion / dependencies

Use dependency-aware deletion + Recently Deleted.

Before deletion:
- show affected dependent Builds/assets
- do not silently break patch/base-ROM relationships

Recently Deleted retention is locked at 30 days (Q90).

# 31. Duplicate / update behavior

Replacing or updating a ROM/art/save on the same Game must not create a duplicate library item unless the user explicitly chooses to create a new Game.

When a new Build is imported:
- attach to existing Game where matched/selected
- preserve old Builds for rollback/history
- do not silently replace history

# 32. Importing saves / artwork / docs with an existing Game

Import Review must support attaching multiple detected assets to an existing Game/Build in one flow.

Artwork choice should be visual, comparing:
- existing artwork
- automatic fetched artwork
- imported/detected artwork

Do not merely ask "import this image?" without showing the alternatives.

# 33. Future / deferred features already discussed

Likely v1.1 or later:
- GBA via mGBA
- GB Studio save migration
- link cable
- Game Boy Camera
- Game Boy Printer
- richer iPad UX / side-by-side manual
- RAR archive support (tentative v1.1)
- full skin authoring
- video/GIF recording
- `.gbproject` import/export concept
- advanced ROM diffing
- BPS patch generation
- RetroAchievements
- full debugger
- deterministic replay/movie system
- Apple TV
- macOS
- broader arbitrary RetroArch `.slang/.slangp` import
- optional Save Profile locking if real-world use proves it useful

# 34. Open research

Later decisions settled most questions from the original planning list. These remain open:

1. The curated shader set, after a device comparison of the lcd1x/lcd3x and pixel-transparency
   candidates.
2. Artwork and metadata provider terms (the provider architecture is settled; see Q79).
3. Community Catalog implementation: auth, moderation, trust model, signing and privacy policy.
4. A security and privacy threat model for imported archives, community data, update downloads
   and external metadata.
5. A naming-parser test corpus for No-Intro and ROM-hack conventions, and precedence when parsed
   metadata conflicts with catalog data.

# 35. Recording new decisions

Do not reopen a locked decision without an explicit request to reconsider it. Record new decisions in `docs/decisions.md`, with the options considered and the reason for the choice.

# 36. Additional locked decisions (continued)

## Q78: v1 patch formats
IPS + BPS only for v1. Patch handling remains pluggable so IPS32, UPS, xdelta/VCDIFF, PPF, etc. can be added later without changing the Build/PatchRecipe model. Unsupported formats should be identified when possible and reported clearly.
## Q79: Artwork/metadata provider architecture
Pluggable provider chain. Canonical/No-Intro identity data first, then configurable online artwork/metadata providers, then the opt-in Homebrew/ROM Hack Community Catalog, with user manual overrides taking highest precedence.

## Q80: Rewind resource policy
Memory-budgeted rewind. Users choose simple duration presets, while the app enforces a configurable/system-derived memory ceiling. On lower-memory devices, retained history and/or snapshot cadence may be reduced to stay within budget. Raw memory-budget controls are not exposed in the normal UI.

## Q81: Fast-forward speed presets
1.5x, 2x, 3x, 4x, 8x, and Unlimited. Fast-forward audio behavior remains independently configurable (accelerated vs muted) through the existing settings hierarchy.

# 37. Build-to-Game promotion / separation requirement

New hard requirement: any Build can be separated from its current parent Game and promoted into its own top-level Game without re-importing the ROM.

Primary use case: ROM hacks that are technically derived from an existing title but are better represented as standalone games in the library (for example, a substantial Pokemon hack/homebrew-style project).

The promoted Game must retain structured lineage metadata linking it to its source/base Game and/or base ROM when known. Promotion must preserve the existing Build identity/blob/provenance rather than duplicating ROM bytes unnecessarily. Associated Build-scoped data (save states, screenshots/debug captures, Build notes, patch recipe, hashes, toolchain metadata, and Build-specific settings) must remain attached to the promoted Build. Game-scoped data such as artwork, manuals, collections/tags, and Save Profiles require an explicit promotion policy rather than silent reassignment.

The UI action should be available from Build details / overflow as something like **Make Separate Game...** or **Promote to Game...**. The reverse operation (merging/re-parenting a standalone Game back under another Game as a Build) should be considered alongside this feature so library organization remains reversible.

## Q82: Build-to-Game promotion behavior
Offer both Move and Copy, with **Move** as the default. Promoting a Build to its own top-level Game must preserve Build identity/provenance and avoid duplicating ROM blob data. The UI should allow the user to explicitly choose Copy when they intentionally want the same Build represented under both Games.
## Q83: Promoted-Game inherited assets
When promoting a Build to its own Game, use an Import-Review-style inheritance step. Default to copying/referencing likely relevant Game-level assets (selected artwork, relevant manuals/docs, tags/collections, and compatible Save Profiles) while leaving originals on the source Game. The user can deselect anything that should not carry over. Build-scoped data remains attached automatically.
## Q84: Reverse merge operation
Support **Merge into Game...** in v1. A standalone Game can be merged/reparented into another Game as one or more Builds, with explicit Move vs Copy choice, lineage/provenance preserved, and an Import-Review-style step for Game-level assets and Save Profiles. Avoid a fully general arbitrary graph/reparenting UI in v1.

## Q85: Core update migration behavior
Use a reversible core-migration checkpoint. A Build uses the latest compatible core on first launch, then remains pinned. When the user explicitly migrates that Build to a newer core version, battery-save data remains available, but existing save states stay associated with the old core version/state lineage. Start a fresh autosave/manual-state lineage for the new core version and retain the ability to roll the Build back to the prior core version if behavior regresses. Do not duplicate the ROM Build solely because the emulator core changed.

## Q86: Super Game Boy support
**Locked: B. Support SGB mode in v1 where SameBoy exposes it**, including SGB palettes, borders, and game-specific enhancements. Custom border management/editing is deferred.

## Q87: Automatic model selection
**Locked: B. Automatic by default with overrides through the existing settings hierarchy.** The app chooses the most appropriate GB/GBC/SGB model automatically from ROM capabilities and user defaults, but users can override model selection at App -> System -> Game -> Build scope when useful for compatibility or testing. Build-level override has highest priority.

## Q88: Rumble defaults
**Locked: B. Controller preferred, phone fallback.** If a connected controller exposes supported rumble/haptics, route emulated cartridge rumble there by default. Otherwise use iPhone haptics. Users can override the effective setting to Phone / Controller / Both / Off through the settings hierarchy. Exact intensity scaling remains an implementation/testing detail.

## Q89: iCloud v1 sync scope
**Locked: B. Sync full library state except ROM blobs.** Sync Games/Builds/lineage metadata, Save Profiles and battery saves, save states/autosaves, cheats, settings/overrides, tags/collections, artwork/manual overrides, patches, skins/custom layouts, notes, screenshots/debug captures, play statistics, and local Community Catalog-related metadata. ROM blobs remain local and are never automatically uploaded to iCloud. Deletion/tombstone semantics remain mandatory so deleted objects cannot be resurrected by an offline device.

## Additional input-haptics requirement
Offer configurable haptic feedback for on-screen virtual button presses, separate from emulated cartridge rumble. This applies to touch controls such as D-pad, A/B, Start/Select, quick actions, and custom layout buttons where appropriate. Cartridge rumble routing remains governed by Q88. Exact default intensity/patterns remain an implementation/UI detail to decide or tune during testing.

## Q90: Recently Deleted retention
**Locked: B. 30 days.** Dependency-aware deletion moves recoverable items into Recently Deleted for 30 days. iCloud synchronization must propagate deletion tombstones so offline devices cannot resurrect deleted records. After the retention period, eligible tombstoned records/files may be garbage-collected once sync-safety requirements are satisfied.

## Q91: On-screen control haptics default
**Locked: B with controller-aware suppression.** Light haptic feedback is enabled by default for on-screen virtual controls. Users can disable it or adjust strength where practical. When a physical controller is connected and actively being used, on-screen button haptics are disabled by default to avoid redundant feedback. This behavior should remain user-overridable. Cartridge rumble remains a separate system governed by Q88.

## Q92: Archive safety behavior
**Locked: B. Safe importer.** ZIP/7z import must enforce nested-archive depth limits, decompression size/ratio limits to mitigate archive bombs, path-traversal protection, no executable handling, clean failure for malformed archives, detection (not cracking) of password-protected archives, and ignoring unsupported files unless explicitly inspected. Archives remain temporary import containers and are not retained after selected assets are committed.

## Q93: Accessibility baseline
**Locked: pragmatic emulator-focused accessibility.** Prioritize accessibility features that are directly useful in an iPhone emulator and its management UI rather than attempting a comprehensive assistive-technology suite in v1. Required baseline: Dynamic Type in normal app UI, good contrast and color-independent status indicators, Reduce Motion support, configurable/large touch targets for virtual controls, one-handed-friendly layouts, fully remappable controls and controller navigation where practical, haptics never being the only feedback channel, and sensible VoiceOver labels/navigation for library/import/settings/manual/document UI and emulator controls. Do not make specialized gameplay narration, screen-content interpretation, dedicated Switch Control workflows, or other highly specialized assistive gameplay systems a v1 requirement. The architecture should not intentionally block future accessibility improvements.

## Q94: Performance policy
**Locked: B. Emulation correctness and full-speed frame pacing take priority over optional visual quality.** On the minimum supported device, normal GB/GBC gameplay with the default shader must sustain full emulation speed. If optional shaders/effects exceed the available performance budget, the app should reduce/disable those optional effects before allowing emulator timing or audio quality to degrade. Do not silently alter core timing to preserve visual effects.

## Q95: Frame pacing target
**Locked: B. Preserve native core timing with synchronized/adaptive presentation.** The renderer must preserve the emulator core's native frame timing rather than forcing a nominal 60 Hz emulation rate. Presentation should synchronize to the device display and handle high-refresh-rate screens by repeating/pacing frames appropriately without altering emulation speed. Frame pacing should prioritize smoothness, audio synchronization, and timing correctness.

## Q96: Audio latency policy
**Locked: B. Low-latency adaptive audio.** Start with a low audio-buffer target suitable for responsive gameplay, but allow the audio subsystem to increase buffering modestly when the device is under load to avoid underruns/crackle. Emulation timing remains authoritative; audio must not speed up or slow down the game to maintain sync. Exact buffer sizes and latency thresholds remain implementation/testing constants to tune on supported devices.

## Q97: Thermal and battery behavior
**Locked: B. Thermal-aware degradation of optional features only.** Under serious thermal pressure, preserve emulation correctness, input responsiveness, and audio first. Reduce or disable expensive optional shaders/effects, shorten rewind history or cadence within the existing memory-budget policy, and defer nonessential background work such as indexing or metadata refreshes before allowing gameplay timing to degrade. Never silently change emulation speed, corrupt state, or alter save semantics. Battery-saver mode is not a v1 requirement, but may be added later.

## Q98: Artwork caching and offline behavior
**Locked: A. Cache only the selected primary artwork.** Downloaded artwork used for the Game's selected primary image should be retained locally at appropriate quality and remain available offline. Alternate provider candidates shown during import or artwork selection are discarded once the user chooses, unless the user saves them as additional artwork under the multi-artwork model. This keeps storage usage predictable while preserving the chosen art offline.

## Q99: Manual/document storage
**Locked: B. Copy imported manuals/documents into managed app storage.** Once a PDF, CBZ, image set, TXT, Markdown, README, changelog, or other supported document is imported and associated with a Game/Build, the app maintains its own managed copy so later moves/deletions in Files or iCloud Drive do not break the library reference. Source paths may be retained as provenance metadata when useful, but library integrity must not depend on the external file remaining in place.

## Q100: Search inside manuals/documents
**Locked: A if implementation remains simple; otherwise defer to C.** Treat in-document search as a low-priority v1 feature. If the native document/text stack makes it straightforward, support search in TXT, Markdown, and PDFs that already contain selectable text. Do not add OCR for image-only PDFs, CBZ scans, or image manuals in v1. If text search introduces disproportionate implementation/testing complexity, ship v1 without in-document search rather than expanding scope.

## Q101: iCloud conflict resolution
**Locked: B. Automatic field-level merge where safe, preserve conflicting files, and escalate only genuine conflicts.** Independent metadata changes should merge when possible (for example, a tag added on one device and a note edited on another). Conflicting binary assets such as divergent `.sav` files or mutually exclusive edits must preserve both candidates and prompt the user to choose or reconcile. Deletion continues to use synchronized tombstones so stale offline devices cannot resurrect deleted content.

## Q102: iCloud Save Profile conflict behavior
**Locked: B. Preserve both divergent `.sav` candidates and require explicit resolution.** If two devices modify the same Save Profile independently, never silently choose one or overwrite either copy. Materialize both conflict candidates with device/date/playtime context where available and mark the Save Profile as needing resolution. The user may choose one as the canonical save, keep both by splitting one candidate into a new Save Profile, or duplicate before resolving. This is a specialization of Q101's general conflict policy for the highest-risk synced object.

## Q103: Rewind duration presets
**Locked: B. 5 sec, 15 sec, 30 sec, 1 min, 2 min, and 5 min.** Rewind remains memory-budgeted per Q80, so the requested duration is a target rather than permission to exceed the device-safe rewind memory ceiling. If the system cannot retain the full requested duration safely, it should reduce retained history/cadence while preserving gameplay correctness and communicate the effective retained duration in settings where useful.

# Decisions Q104-Q186 and final clarifications

## Q104: Rumble intensity
Locked: separate phone-haptics and controller-rumble intensity controls. Core rumble amplitude is scaled through the selected output; normal settings inheritance may override where appropriate.

## Q105: Shader inheritance
Locked: shader pipeline components and parameters inherit independently through App -> System -> Game -> Build rather than treating a whole preset as one indivisible value.

## Q106: User shader presets
Locked: users can customize shader components/parameters and save reusable named presets. File import/export of custom presets is post-v1.

## Q107: Live shader switching
Locked: shader presets can be switched live from Quick Actions without restarting emulation. Dedicated controller shader-cycling is not a v1 requirement.

## Q108: Default display philosophy
Locked: system-authentic default presentation for DMG/GBC/SGB, with raw pixels readily available. Exact bundled/default shaders require a community survey before final selection; lcd1x/lcd3x and Pixel Transparency variants are explicit candidates.

## Q109: Touch controls with controller
Locked: hide gameplay touch controls automatically when a physical controller is active, with touch-to-reveal and a user override.

## Q110: Controller disconnect
Locked: unexpected controller disconnect pauses gameplay, reveals touch controls, and shows a brief notice.

## Q111: Multiple controllers
Locked: v1 detects multiple controllers and lets the user choose Player 1; architecture reserves Player 2 for future link sessions.

## Q112: Controller profiles
Locked: reusable named controller profiles keyed to controller type where possible, with user customization and the established inheritance model.

## Q113: Hardware accessory detection
Locked: passive accessories such as Playtiles are manually selected. Electronically identifiable accessories/controllers may trigger a suggested preset, never a forced switch.

## Q114: Passive accessory calibration
Locked: device-specific presets plus a quick calibration screen for screen/touch-region offsets, persisted per accessory/device combination.

## Q115: Layout sharing
Locked: native custom layouts can be exported/imported through Files/Share Sheet. Community layout gallery is later.

## Q116: Foreign skin preservation
Locked: preserve original Delta/Manic skin packages as source artifacts while converting to the internal runtime model.

## Q117: Skin compatibility failures
Locked: partial import is allowed with explicit unsupported-element reporting and preview; controls must never be silently mis-mapped.

## Q118: In-game layout editing
Locked: Edit Layout is available from gameplay; emulation pauses and the current frame remains visible as an alignment reference.

## Q119: Native layout visual customization
Locked: geometry/hitboxes plus a small set of built-in control styles and opacity. Full per-control artwork authoring is later/imported-skin territory.

## Q120: Editing shared layouts from a Game
Locked: choose Save for This Game or Update Shared Preset; game-specific edits become overrides.

## Q121: D-pad touch behavior
Locked: sliding D-pad with natural diagonals and sensible dead-zone/sensitivity tuning.

## Q122: A/B sliding
Locked: allow sliding between A/B while multitouch still supports simultaneous A+B.

## Q123: Touch feedback
Locked: subtle visual pressed-state feedback plus haptics.

## Q124: Gameplay gestures
Locked: optional customizable screen gestures, off by default.

## Q125: Turbo buttons
Locked: optional Turbo A/Turbo B actions available to layouts, Quick Actions, and controller mappings; absent from default layout.

## Q126: Cheats and save-state context
Locked: save states/debug captures record active cheat configuration as metadata; loading does not silently toggle cheats but may offer Restore Cheat Configuration.

## Q127: Cheat organization
Locked: optional groups/categories plus search; small lists remain simple.

## Q128: Cheat database
Locked: pluggable cheat database keyed to verified ROM/Build identity; users selectively add cheats and nothing is auto-enabled.

## Q129: Memory watch HUD
Locked: optional Developer HUD for selected memory watches, off by default and configurable.

## Q130: Watch history
Locked: short in-memory history during the active session, with persistent history only through explicit debug capture.

## Q131: Cheat-search sessions
Locked: named memory-search sessions may be resumed within the current emulation session but are not persisted across launches.

## Q132: Memory-edit safety
Locked: immediate Developer Mode writes with original/current values, Undo Last Write where possible, and clear frozen-value indication.

## Q133: Patch-stack editing
Locked: patches may be reordered/enabled/disabled/added/removed, but every changed recipe produces a new Build/result; existing Build ROM identity is immutable.

## Q134: Patch base validation
Locked: validate expected base where possible, warn on mismatch, and allow explicit Apply Anyway.

## Q135: Patch metadata
Locked: best-effort structured metadata with confidence/provenance. Catalog/hash evidence outranks README/archive context, which outranks filename inference. Preserve original filename. Never treat filename guesses as canonical.

## Q136: Patch source retention
Locked: retain original patch file, base-ROM reference, recipe, and resulting hash.

## Q137: Generated ROM cache
Locked: generated patched ROMs are rebuildable cache; keep for launch speed, permit safe cache eviction, rebuild and verify hash on demand.

## Q138: Storage screen
Locked: show usage by category and distinguish source/irreplaceable assets from disposable/rebuildable cache; offer safe cleanup actions.

## Q139: Automatic cleanup
Locked: automatic cleanup may remove only disposable/rebuildable data such as generated-ROM cache and expired Quick Play sessions. Never silently delete source ROMs, patches, saves, manuals, user artwork, screenshots/debug captures, or similar user data.

## Q140: Library backup/import
Locked: bidirectional Library Backup export/import. Backup includes metadata and user-created/irreplaceable assets; ROMs excluded by default with an explicit personal-backup inclusion option. Future migration adapters should support exports from Delta, Manic, Afterplay, Playtiles-related formats where available, and other platforms.

## Q141: Backup format
Locked: documented, versioned archive with manifest, ordinary files where practical, checksums, and schema versioning.

## Q142: Backup encryption
Locked: unencrypted by default for portability, with optional password-based encryption. No password recovery promise.

## Q143: Backup restore
Locked: merge by stable IDs/hashes with conflict review and deduplication; explicit Replace Entire Library mode remains available.

## Q144: Migration reports
Locked: show compatibility report before commit and retain a summary afterward, covering exact imports, conversions, skipped data, and user decisions.

## Q145: Undo
Locked: lightweight Undo for recent structural/library operations where practical; deletion remains handled by Recently Deleted.

## Q146: App relaunch
Locked: return to previous game/session and honor the Auto Resume policy that applies to its Game and Build.

## Q147: Concurrent sessions
Locked: one active emulator session at a time in v1. Multi-core simultaneous sessions arrive with link cable support.

## Q148: In-game switching
Locked: Quick Actions can switch Build and Save Profile, safely closing/autosaving, checking compatibility, and relaunching.

## Q149: Import during gameplay
Locked: analyze imports while gameplay continues and surface a nonintrusive New Build Ready notice with Switch Now/Later.

## Q150: Development hot reload
Locked: Restart into New Build action; capture/save needed context, stop old core cleanly, run compatibility checks, and start new Build. Never live-swap ROM bytes in a running core.

## Q151: Development build matching
Locked: multi-signal matching suggests likely existing Game and may preselect it at high confidence, but uncertain ROMs are never silently attached.

## Q152: Build version ordering
Locked: parse recognizable semantic versions/build numbers/dates into a structured sort key while preserving original version text; ambiguous cases fall back to import/creation date and are manually correctable.

## Q153: Build display names
Locked: concise Build names such as Original, v0.95, Debug 43; title/author/version remain structured metadata rather than repeated in a long display name.

## Q154: Base Build presentation
Locked: clean/original ROM is explicitly marked Base Build, remains playable, and anchors patch lineage.

## Q155: Multiple Base Builds
Superseded 2026-10-06: a Game has at most one Base Build. Choosing a replacement demotes the previous one; every patch recipe still records its exact source Build and hash.

## Q156: Region/language variants
Locked: normally group fundamentally same title as one Game with region/language Build properties; user may separate. No-Intro relationships are high-confidence evidence but not identical to the app's semantic Game model.

## Q157: No-Intro family grouping
Locked: unambiguous No-Intro family matches are grouped automatically but shown in Import Review before commit; lower-confidence relationships are suggestions.

## Q158: Revisions
Locked: revisions are Builds of the same Game, exact hashes/revision metadata preserved, preferred/default Build selectable.

## Q159: Preferred Build
Locked: each Game has an explicit Preferred Build. App may initialize intelligently, but explicit user choice is never silently changed because another Build was recently used.

## Q160: Preferred Save Profile per Build
Locked: each Build may remember a preferred Save Profile, falling back to Game preferred profile; compatibility rules override preference.

## Q161: Game title semantics
Locked: top-level Game title is what the user perceives as the game. A promoted hack is titled by its hack/game name; base title remains lineage metadata.

## Q162: Alternate titles
Locked: primary display title plus alternate titles/aliases, all indexed for search without cluttering normal UI.

## Q163: Metadata editing
Locked: presentation metadata is user-overridable while canonical/provider values remain preserved. Technical identity fields such as ROM hashes are immutable.

## Q164: Metadata provenance UI
Locked: normal UI stays clean; Metadata Details exposes field source/confidence when useful.

## Q165: Metadata refresh
Locked: canonical/provider metadata may refresh quietly; user overrides are never overwritten.

## Q166: Artwork refresh
Locked: no automatic artwork refresh after selection. Provide manual Check for New Artwork action.

## Q167: Artwork cropping
Locked: preserve original image and support non-destructive crop/reposition for presentation.

## Q168: Artwork scope
Locked: Game-level by default with optional Build-specific artwork overrides.

## Q169: Document scope
Locked: documents may belong to Game, Build, or both, with semantic type (Manual, README, Changelog, Guide, Map, Other). Build views inherit applicable Game docs.

## Q170: Document bookmarks
Locked: v1 remembers last-read position only. Bookmarks/highlights/annotations later.

## Q171: Closing in-game manual
Locked: restore the gameplay pause/running state that existed before the manual was opened.

## Q172: Background audio/emulation
Locked: backgrounding pauses emulation/audio and triggers lifecycle autosave.

## Q173: Audio interruptions
Locked: genuine audio interruptions pause safely; normal route changes are handled without restarting the game.

## Q174: External display controls
Locked: external display is gameplay-focused; iPhone becomes controller-focused companion while retaining Quick Actions/manual/states/Build switching.

## Q175: External display rendering
Locked: independent render target sharing the emulated framebuffer, with display-specific scaling/aspect/shader/safe-area optimization.

## Q176: Bug-report export privacy
Locked: preview/checklist before export; useful technical context can be selected by default while full memory/save/notes and sensitive/bulky data require explicit inclusion.

## Q177: Crash reporting privacy
Locked: opt-in only. May include non-content emulator diagnostics, never automatically ROMs, saves, screenshots, memory, filenames, notes, or library contents.

## Q178: Community Catalog backend scope
Locked: v1 supports moderated metadata plus artwork and patch references/uploads where legally appropriate; no commercial ROM hosting. Creator-controlled homebrew binary publishing is later.

## Q179: ROM/patch acquisition boundary
Locked: users supply commercial ROMs. Catalog may link legitimate project/release pages and distributable patches, never commercial ROM acquisition.

## Q180: Data integrity verification
Locked: hash at import and verify important assets when read/used, especially after sync/restore/migration. Corruption must not silently propagate over a known-good copy.

## Q181: Crash recovery
Locked: separate crash-recovery checkpoint and Recover Session / Start Normally prompt after abnormal termination; avoid automatic crash loops.

## Q182: Offline-first
Locked: core emulator/library features work fully offline; network features degrade independently and retry gracefully.

## Q183: Onboarding
Locked: minimal first-launch onboarding for Import, Quick Play, save/storage basics, and relevant opt-ins. Advanced concepts are introduced contextually.

## Q184: Developer Mode activation
Locked: Advanced -> Developer Mode normal toggle with explanation; advanced tools appear contextually rather than replacing the whole UI.

## Q185: Customizability philosophy
Locked: progressive disclosure: simple by default, deep when wanted. Strong presets/defaults lead; fine-grained controls live under Customize/Advanced/context menus/Developer Mode. Do not expose a knob merely because implementation permits it.

## Q186: Release discipline and MVP
Locked: core-complete v1, but build an Architecture Proof/MVP first. v1 hard requirements and product-defining architecture are release blockers; large auxiliary systems such as iCloud and Community Catalog target v1 but may move to v1.1 after explicit milestone review if they are the only blockers.

MVP must prove: SameBoy GB/GBC on iPhone; core abstraction; GRDB + managed/content-addressed storage; Game -> Builds -> Save Profiles; reliable ROM import/identity; add/replace Build without duplicate Game; promote Build to Game and merge back; multiple base/revision/region Builds; preferred Build/Profile; manual Save Profiles; battery saves; basic manual states + lifecycle autosave/autoresume; Quick Play sandbox/promotion; IPS+BPS patching with sources preserved; patch-derived Builds/provenance; Build switching/save safety; basic grid/list library; Metal video/audio; touch + Bluetooth controller; basic rumble/haptics; enough App -> System -> Game -> Build settings inheritance to prove the model.

Explicitly not required for MVP proof: iCloud, Community Catalog, Delta/Manic skin import, sophisticated shader suite, AirPlay, memory search/full cheat UI, manuals, archive import, elaborate layout editor, update discovery, link cable.

## Additional locked decisions/clarifications not numbered earlier
- Initial systems: GB/GBC; SameBoy core. Architecture supports mGBA for GBA post-v1.
- Minimum OS: iOS 17+. iPhone-first; iPad-specific polish later.
- Persistence: GRDB/SQLite metadata plus managed filesystem blobs; no ROM/save blobs in SQLite.
- Core pinning: latest compatible core on first launch, then pin per Build; nonintrusive update notice; explicit reversible migration checkpoint.
- Patch formats v1: IPS + BPS only; format subsystem pluggable.
- Artwork/metadata: pluggable provider chain.
- Rewind: memory-budgeted; visible presets 5s/15s/30s/1m/2m/5m; brief background survives, not long-term persisted.
- Fast-forward presets: 1.5x/2x/3x/4x/8x/Unlimited; audio configurable accelerated or muted. Slow motion: 0.25x/0.5x/0.75x.
- Lifecycle autosave: always write/update Auto State and battery save; autoresume global default Always with System, Game and Build Always/Ask/Never overrides; rolling 5 autosave states.
- Save states are always Build-specific and also bound to Save Profile/core serialization context; never shared across Builds.
- Save Profiles are manually creatable (blank, duplicate, import .sav, Quick Play promotion, future migration), flat list with subtle ancestry; one current .sav per profile; no rolling .sav history. Compatibility-risk operations fork/copy rather than mutate source.
- GB Studio: detect toolchain where possible; variable maps may attach to Builds; v1 detects/warns/prepares, save migration targeted v1.1. Do not claim safe migration without required maps.
- ROM naming: No-Intro parsing + hack-style/Maybe-Intro-like bracket metadata extraction; preserve original filename; normalize internally; physical rename explicit. Unknown ROMs can be manually matched to known game/base lineage even if base ROM is absent.
- Import architecture: Analyze -> ImportPlan -> ImportReview -> transactional Commit. Multi-asset imports show artwork candidates visually including auto-fetched default vs imported artwork. ZIP+7z v1; RAR tentative v1.1. Archives are temporary containers, not retained.
- Manuals/docs: first-class managed assets; PDF/CBZ/PNG/JPEG/WebP/TXT/Markdown; in-game overlay pauses gameplay; iPad side-by-side later.
- Library: smart + manual collections; grid/list/developer view; FTS5 live full-metadata search; tags on Games/Builds hidden behind context/overflow; sorting; content-aware duplicate import.
- Screenshots: Game gallery with Build association; optional export metadata or rendered bug-report strip; optional capture context includes selected watches/named variables/memory ranges/registers where available, frame/time, Build/hash/patches, RTC, cheats, Save Profile, core/settings. Full RAM capture is opt-in Developer Mode only.
- Quick Play: temporary sandbox, 24h default retention configurable; can copy existing save into sandbox but never writes source; promotion offers keep existing / replace after safety copy / create new profile.
- Link cable: v1.1; architecture supports local dual core and future proximity/SharePlay initiation. Do not use deprecated Multipeer Connectivity as new foundation.
- Game Boy Camera + Printer: v1.1. GBA/mGBA: post-v1. Chromecast: out of scope for now.
- iCloud target v1 but checkpoint after data model; full library state except ROM blobs; tombstones; 30-day Recently Deleted; safe field merges; divergent saves preserve both.
- Community Catalog: opt-in read+contribute, lightweight account only for contribution, moderation, source/provenance, nonintrusive update discovery, streamlined verified update import as new Build, background check default/no auto-download with optional pre-download, per-game update overrides, field-level corrections and optional Suggest Correction after local edit.
- Backups: import/export, versioned documented archive, optional password encryption, merge restore, migration reports; future adapters for Delta/Manic/Afterplay/Playtiles and others.

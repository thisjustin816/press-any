# Press Any

Press Any is an iPhone-first Game Boy and Game Boy Color emulator. It's built for ordinary play,
and it's strongest for the people who make and test homebrew and ROM hacks: a Game keeps one
identity while its ROM changes, saves stay safe across versions, and patches keep their sources.

This document says what the app is and how it behaves. Where something isn't built yet, it
carries its target release (v1, v1.1 or later); `docs/backlog.md` tracks what's done and what's
left. When a decision changes how the app behaves, update the section it touches in the same
change. There is no separate decision log.

## Principles

- **Simple by default, deep when wanted.** Presets and good defaults come first. Finer controls
  live under Customize, context menus, Advanced and Developer Mode. Don't expose a setting just
  because the code has a knob for it.
- **A ROM file is never the library identity.** The library is Game → Builds → Save Profiles.
- **Saves are never put at risk silently.** Anything that could lose or roll back a save either
  works on a copy or asks first.
- **Correct, full-speed emulation wins** over optional effects, and works fully offline.

## Platform and releases

- iOS 17.4 or later, iPhone first. iPad keeps working but gets no special design until later.
- SameBoy 1.0.3 for GB and GBC, built from its `Core/` only. SameBoy's `iOS/` directory needs
  its author's written permission to ship on the App Store, so none of its code, artwork or
  layouts are used.
- GBA comes through an mGBA adapter in 1.2 or 2.0, once GB/GBC is feature complete through v1
  and v1.1. Other systems aren't planned, but the library, storage, input and core abstractions
  mustn't rule them out.
- Light and Dark appearance.
- TestFlight first, then the App Store. The App Store release may be paid up front or unlock
  features with in-app purchase; the project's own source stays Apache-2.0 (`LICENSE`).
- The library, Game Details, Settings and every sheet are portrait. Gameplay also turns to
  landscape (see Landscape).

v1 is a good core experience: the library model with search, sorting and favorites, saves and
states with Library Backup, patching, Quick Play, Fast Forward, rumble, Bluetooth controllers,
landscape and the built-in layouts. Everything else waits for v1.1: iCloud sync, the Community
Catalog and metadata providers, tags and collections, archive and multi-asset imports, automatic
artwork and documents, rewind, slow motion, frame advance and Quick Actions, the model override,
curated shaders, the layout editor and skin import, screenshots and gameplay notes, external displays,
crash reporting and usage counts, and Developer Mode.

## Library model

### Game

A Game is what the player thinks of as the game. It survives ROM replacement, patching, new
versions, regional and revision variants, and Builds moving in or out. It has a UUID, a primary
title, a system, a preferred Build and a default Save Profile. A promoted hack is titled by its
own name; the base game's title stays as lineage. A hack that becomes an existing Game's
Preferred Build, in Import Review or Open Patch, offers its title for the Game ("Use Game Title:
Mole Mania DX"), on by default. Accepting it keeps the old title as an alias and makes the new
one the player's. Moving that hack out with Make Separate Game, which suggests the hack's title for
the new Game, gives the original Game back the title the hack was made from, as long as it still
holds it as an alias; a copy leaves the title alone. A patch without hack tags offers its title only when it adds words without
digits to the Game's.

A Game keeps alternate titles as aliases in an indexed table, ready for the later FTS5 index.
Library search already matches them. A No-Intro family's other regional titles become aliases
when a release joins the Game, so "Pocket Monsters Crystal" finds Pokémon Crystal. Rename Game,
in Game Details' menu or a Game's long-press menu in the library, keeps the former title as an
alias and records the player's title choice.

A Game stores whether it is a favorite. Merging Games keeps the survivor a favorite if either
was, and Make Separate Game carries the source Game's favorite state. v1 adds metadata
provenance; tags, collections, documents and typed artwork follow in v1.1.

### Build

A Build is one exact playable image within a Game. It has its own UUID, and its image identity,
the SHA-256 of its bytes, never changes once committed. Changing the bytes or a patch stack makes
a new Build. A Build is either an imported ROM or a patch recipe's result. It stores a concise
name, region, language, revision and version, lineage, toolchain detection, a preferred Save
Profile, its pinned core, settings overrides, and when it was added.

- **Preferred** is the Build Play starts. It's the player's explicit choice, never changed just
  because another Build was played.
- **Base** marks the clean original that patches build from. A Game has at most one Base Build:
  marking or importing a new one demotes the old. A Game made only of hacks may have none.
  Recipes keep their exact source Build and hash whatever happens to the Base mark.
- A Game holds one Build per image.

Each Build has one plain-text note, shown and edited in Build Details from its menu. Saving
preserves whitespace; Cancel leaves the stored note alone, and saving an empty note clears it.
FTS5 search over notes comes later. Build Details also shows its accumulated playtime. A session
adds the same played time to its Build and Save Profile on background and close, counting only
time since the last write. Game rollups and the statistics screen come later.

v1.1 adds a lightweight timeline (versions, hashes, parents, notes, import and activation history)
and a Build comparison screen. The comparison engine (changed bytes and ranges, size, banks,
header) exists; the screen doesn't yet.

### Save Profile

A Save Profile is a named playthrough with one current battery save, such as Main, Nuzlocke or
Testing. Profiles can be blank, duplicated, imported from a `.sav` or `.srm`, or promoted from Quick Play,
and they're listed flat, with a subtle "copied from" note rather than a tree. Compatible Builds
can deliberately share one. A Build remembers its preferred profile and falls back to the Game's
default.

There is no rolling battery-save history. Isolation comes from duplicating profiles. A profile
can carry only narrow playthrough settings (cheats, RTC offset, rewind where it makes sense; all
v1.1), never a full fifth settings layer.

### Save state

A save state belongs to one exact context: Build, Save Profile, image hash, core and state
serialization version. States never load across Builds, even when the Builds share a battery
save. Each state records its time and playtime. Manual and Auto States also keep a thumbnail and
an optional name. Manual states, lifecycle Auto States and crash-recovery checkpoints are separate
kinds.

### Patch recipe

A recipe records its exact base Build and hash, its ordered IPS or BPS patches, each step's
enabled state, each enabled step's input SHA-256, and the hash of its result. The executable
identity is the result's hash, not the recipe.

### Managed assets

Every binary (ROMs, patches, saves, states, thumbnails, artwork, variable maps) is a managed file
with a content hash, kind, size, relative path, original filename, provenance and integrity
status. Source assets are irreplaceable; generated patched ROMs are rebuildable cache.

## Storage and integrity

- Metadata lives in GRDB and SQLite. Binaries live in a managed folder in Application Support,
  never in the database and never in Files, where content-addressed paths could be renamed.
- Exact duplicate images share one file. A Build's UUID, not its hash, owns user records, so a
  copied Build can share a file without sharing saves.
- Files are placed before the database points at them, so a failed commit can leave an orphan to
  clean up but never a record pointing at a missing file. A failed import leaves no half-made Game
  or Build.
- Atomic writes use `F_FULLFSYNC` where available and sync the directory after the rename.
- The battery save is written whenever the game changes it, checked at most every five seconds of
  play, on its own queue so writes don't disturb frame pacing.
- Battery saves and save states are checked against their recorded SHA-256 before they reach the
  core, hashing the bytes already read. A mismatched battery save stops the launch, and a
  mismatched state isn't loaded, so the game boots from its battery save and says the resume point
  was kept. Either file is marked corrupt and left untouched: loading a damaged save would let the
  next flush write it back as the player's save.
- The mismatch can also mean the app closed between writing a battery save and recording its hash,
  when the file is the newest good save, so the stopped launch asks: Use It Anyway, Start a New
  Save, or Cancel. Use It Anyway first copies the file as found to "<profile> before playing", then
  records it as the profile's save and starts the game. The alert also points to Replace Save from
  File.
- Launch rehashes the ROM and patches it's about to use. Settings > Check Library Files rehashes
  every ROM and patch on demand, marks damaged ones, reports missing files, and removes files
  nothing uses and temporary files an interrupted write left over ten minutes ago. It runs only
  when asked, since rehashing a big library at every launch would slow startup.
- Automatic cleanup removes only disposable data: expired Quick Play sessions and staged copies
  an interrupted import left. It never touches source ROMs, patches, saves, documents, artwork or
  captures.
- v1: a storage screen by category that separates source data from rebuildable cache, safe
  cleanup, eviction of generated ROMs under pressure, and protection of in-flight files from
  cleanup.

### Exports and the Files folder

Press Any has a folder in the Files app for what it writes out. Exports go to its Exports folder:
a Save Profile's battery save as a `.sav`, and a Build's ROM (the original, or the rebuilt patched
ROM) under its canonical name. Exporting a whole Game as a package, in the Library Backup format
with ROMs only when asked, comes with the backup work. Later captures (recordings, bug reports)
land in the same folder.

## Importing

The pipeline is Analyze → Import Plan → Import Review → transactional commit. Analysis never
changes the library; review shows what will happen; commit is all or nothing.

### Sources and safety

- The file picker, and Share Sheet / Open In for `.gb`, `.gbc`, `.ips`, `.bps`, `.sav` and `.srm`. The document
  types are registered in Info.plist with `LSHandlerRank = Owner`. Each keeps
  `CFBundleTypeRole = Viewer`: opening stages a copy for play or import, so it needs no Editor
  role. The extension mappings stay in `UTImportedTypeDeclarations`; Press Any does not own
  these formats and does not export their types.
- Every picked or shared file is untrusted. Its size is checked before it's read, against a limit
  for its kind: 8 MB for a ROM (the most a header can declare), 16 MB for a patch, 4 MB for a
  battery save (TPP1 cartridges can declare 2 MB of RAM), 20 MB for artwork and 4 MB for a
  variable map.
- Staging copies only regular files, never links or folders, under a fixed name. The sender's file
  is never changed. The staging folder is emptied at launch.
- An IPS patch's trailing size can only truncate the result. A patch result over 8 MB fails when
  the Build is made.
- Artwork is decoded when it's set and stored as a PNG no larger than 1024 pixels on its long
  edge; a file that isn't a readable image is refused.
- The SameBoy bridge refuses images over 8 MB and checks the memory SameBoy will allocate first,
  and hands battery saves to the core zero-padded, because SameBoy reads up to 48 bytes past the
  cartridge RAM.

### Import Review

- The destination and Build details come first: a new Game or an existing one.
- **Matching an existing Game.** A known No-Intro dump joins the one Game that already holds a
  Build from its family; with several candidates it's a choice, not a default. Otherwise review
  suggests a Game whose title or alias matches the file's title, header title or a hack's base title,
  ignoring case, punctuation and spacing. Only whole titles match ("Mega Man 2" never joins
  "Mega Man"), and two matching Games suggest neither. A ROM whose header title matches a Build
  already in one Game suggests that Game, since homebrew builds of one project share a header
  title while their filenames change. When the title and header suggest different Games, neither
  is suggested. An uncertain ROM is never attached silently.
- **Match Game.** A ROM with no No-Intro match can be marked as a hack or another Build of a known
  game. Search the library and bundled No-Intro data, choose the base game, then confirm Import.
  A recorded base keeps its title, system and, when known, No-Intro family and release even if its
  ROM isn't in the library. The ROM stays Unknown; this choice never invents an image match or a
  patch source. Importing a release of that base family later offers the Game and a Base mark in
  review. Several Games with that lineage leave the destination to the player.
- **Regional proposals.** For No-Intro releases, the app's region and language order suggests the
  display title among the Game's releases and whether the arriving Build should be Preferred.
  A higher-ranked release offers the better title and Preferred mark in review; each can be
  declined before Import confirms them. Ties keep the existing choice. A player-set title is
  never replaced, and changing the setting doesn't rename or change Preferred in existing Games.
  Preexisting titles without recorded provenance also stay protected during import; Suggest Names
  lets the player opt them into regional title proposals.
- **Roles.** Other new Builds default to Preferred. A Build defaults to Base when the Game has none,
  unless it's a ROM hack. Where the Game has a Base, a No-Intro release leaves it alone, and so
  does anything arriving where a No-Intro release is the Base. Any other file is a homebrew or
  development build, and the newest is the Base: it replaces the Base unless its version or date
  sorts before the Base's. ROM hacks and
  patch-created Builds are Preferred but not Base. A ROM explicitly matched as a hack or another
  Build starts without a Base mark. A role the player sets stays when the destination changes.
- **Metadata.** Region, language, revision and version fill from the filename (see Naming) and a
  nonzero header revision, and the player can correct or clear them. Unknown tags stay as written.
  Review labels its fields and explains Base Build and a wrong header checksum.
- **Toolchain detection** runs when an image becomes a Build, and review shows what it found.
- **Artwork.** Review can add the Game's artwork from Photos or Files. The image is checked and
  downscaled when it's chosen, so an unreadable one is refused before importing, and it's set
  once the ROM is in the library, replacing an existing Game's artwork only when the player
  chose one. An exact duplicate doesn't offer it.
- **Duplicates.** An exact duplicate image never makes a second file or Build. Its existing Build
  keeps its metadata. In v1.1, a duplicate import still inspects anything new that came with it
  (saves, artwork, documents, patches).
- A file shared while another sheet is open, such as Import Review mid-edit or the Resume prompt,
  waits until that sheet closes.

### Planned (v1.1 unless noted)

- v1: development matching from several signals, preselecting a Game only at high confidence.
- 7z through libarchive, as a temporary container that isn't kept, with the same limits as zip.
  RAR is tentative.
- Multi-asset review that groups ROMs, patches, saves, artwork, documents, READMEs, changelogs,
  variable maps and skins, attaches several ROMs to one Game in one flow, and compares existing,
  fetched and packaged artwork visually.
- Importing while a game plays shows New Build Ready with Switch Now or Later; Developer Mode adds
  Restart into New Build. ROM bytes are never swapped in a running core.
- Sharing an itch.io page or a GitHub page with a ROM download offers its downloads, and the
  library's + menu browses itch.io's Game Boy tag and Homebrew Hub.

## Identity and naming

### No-Intro data

The app bundles No-Intro's Game Boy and Game Boy Color data. DAT-o-MATIC's Data Usage License
allows any lawful use, commercial included, with no attribution required; the app credits
No-Intro in Acknowledgements anyway, with the data's date.

- The source is DAT-o-MATIC's DB export for both systems. It lists every file No-Intro knows,
  trusted dumps and scene releases, with each game's title, region, languages, status, version and
  flags, and marks bad copies file by file. A generator turns the two exports into one compact
  bundled file: per game its canonical name, those fields and its family's root, and per file its
  SHA-1, size and bad flag. The key is SHA-1 because the export lacks SHA-256 for many GBC files.
- Refreshing is a human step, about every three months: a maintainer downloads the exports in a
  browser, runs the generator and opens a pull request. Nothing downloads from DAT-o-MATIC
  automatically, because it bans clients it takes for bots and lifts bans only by email. CI warns
  when the data is more than 90 days old. Signed downloadable updates wait for a host and a
  signing key.
- Each imported image stores its SHA-1 beside the SHA-256 that stays its identity. Dump status and
  family membership are looked up from the bundle when needed. Family titles are kept as searchable
  Game aliases when a release joins, and explicit Match Game choices keep base-game lineage even
  without the ROM. Refreshing the data never renames a Game or replaces a player's title.
  Suggest Names can offer the best regional title among releases already held by the Game.
- A known dump takes its canonical name ahead of the filename, and a Game created from one is
  titled by its regional title. The original filename is always kept.
- A Build's Technical Info shows Verified (with the dump's name), Bad Dump, Modified (patched from
  a verified dump) or Unknown. The app never alters a ROM to make it match.

### Naming rules

Settings > Library > Regions and Languages starts with USA, Europe, Japan. Both lists can be
reordered, added to or cleared; languages break a region tie, starting with En, Fr, De, Es, It, Ja.
A release listing several regions or languages uses its best-ranked tag; World is available in
every region. Unlisted tags sort after listed ones. These preferences supply suggestions applied
only after confirmation in review. Existing titles with no recorded provenance stay protected
during import. The player can opt into the order by accepting a regional title in Suggest Names.

Filenames are evidence, not truth. Parsed values keep their source, the player's corrections win,
and identity and bytes never change. The same rules name Builds in Import Review, Quick Play
promotion and Open Patch.

- Region and language groups, "Rev 1" or "Rev A" (a retail revision), "v1.2" and "Version 1.2"
  are recognized. A dotted "Rev 0.2.0" is a homebrew version. Versions keep a semver suffix such
  as "-beta.3" and sort by their numeric part. Loose forms such as "r2" or a bare trailing number
  stay in the title, since "R-Type" and "Mega Man 2" look the same.
- In a name joined by hyphens or underscores, a "v5" or "v1.2" word mid-name becomes the version
  and the words after it the status: "Serve-Sisters-Coop-v5-Stability" is "Serve Sisters Coop",
  version 5, status Stability. A dotted number needs no "v": "match-land-live-0.3.0+live1" is
  "Match Land Live", version 0.3.0+live1, with an all-lowercase name capitalized and words such as
  DX and SGB kept in capitals. Underscored or hyphenated numbers after a "v" word are its dotted
  parts: "mole_mania_dx_v1_3" is "Mole Mania DX", version 1.3. A lone "v2" is never the whole
  title.
- A date stamp after the title, as in "AeonMetalFighters_20261006_classic", becomes the version,
  shown as "2026-10-06" and sorted by date; the words after it become the status. Only a valid
  eight-digit or hyphenated date counts, and never as the whole title.
- A file with no version tags is named for the day it's added, "2026-10-06", then the time for a
  second one the same day. A hack with nothing else to name it is "Hack".
- A patch's Build is named by its title, followed by any version or other tag: "Mole Mania DX
  v1.3". When the patch's title is the Game's own, only the tag remains, so "Example (Rev 1)"
  applied to Example is "Rev 1".
- A suggested name that repeats one already in the Game gains the day ("v1.0 · Oct 6"), then the
  time, then a number. A name the player typed is left alone. A Build sharing its name with
  another shows its date and time in the list.
- Suggest Names, in the library's view menu, shows Game title suggestions above Build names.
  A Game with No-Intro releases gets a title suggestion when its best-ranked release under the
  app's region and language order has a different title. This uses the same selection as Import
  Review, including stable ties; missing Build region or language fields use the matched release's
  data. It includes protected titles because choosing Rename is an explicit opt-in. Games without
  a No-Intro release get no title suggestion.
  Each row shows the current title, proposed title and release region. Accepting the proposed
  title keeps the old title as an alias and leaves the Game following the order, so later imports
  can offer regional title proposals again. An edited title is the player's and stays protected;
  skipping leaves the Game unchanged. Preferred Builds are untouched.
  Build names still use the import naming rules for names that look generated: URL escapes, the
  bare source filename, repeats, or the generic "Original" and "Hack". Both kinds can be accepted,
  edited or skipped; nothing changes until Rename. With neither kind to suggest, review says
  Game titles and Build names look right.

### Planned (v1)

- Richer ROM-hack metadata (hack title, author, version from bracket conventions) and a
  normalized filename suggestion, without inventing fields.
- v1.1: Rename File to Canonical Name as an explicit action; bulk rename later.
- v1.1: artwork by region and patch review offering the Game's other regional Build when a patch
  expects it.
- Metadata provenance with a Metadata Details view, quiet provider refreshes that never overwrite
  the player's values, and Build version ordering from semantic versions, build numbers and dates.

## Restructuring Games

- **Make Separate Game** promotes a Build to its own Game, by Move (default) or Copy, without
  re-importing. Build-scoped data (states, recipes, toolchain reports, variable maps, settings,
  notes and playtime) always follows the Build. A review sheet chooses the Game-level things: it
  offers copies of the Game's artwork and Save Profiles, selecting the artwork and the profiles
  the Build plays or last wrote. Copies get their own files. The promoted Build plays its copy of
  the profile it played, and its states move to those copies, keeping their save times so Auto
  States still resume. The new Game records Split From, which survives the source Game's deletion.
  Promoting a Game's only Build by Move just renames the Game.
- **Merge into Another Game** reviews in its own sheet: Move or Copy, the target, and the profiles
  and artwork that come along. Move takes every profile, since the source Game goes away; the
  target keeps its artwork unless Use <source>'s Artwork is on. Copy offers the source's artwork
  and profiles. When the target already holds the same image, Copy skips that Build and Move is
  refused, since moving would drop the Build's states or let them cross Builds.
- **Suggest Game Merges**, in the library's view menu, lists Games whose Builds are images from
  the same No-Intro family. A hack patched from a release stays out, since it's its own Game. Review chooses the subset, the Game to keep
  and its surviving title. Merge confirms moves through Merge into Another Game; lineage,
  profiles, states and artwork follow that path. The survivor keeps its artwork, or the first
  available source artwork fills it. Duplicate images are refused before moving a family group.
  Merely opening the review changes nothing. A failed operation refreshes the remaining list;
  completed groups stay merged and can be reviewed in the library.
- A Build's menu has Mark as Base Build and Unmark as Base Build.

## Patching

- IPS and BPS for v1, through a pluggable format system; IPS32, UPS, xdelta and others later.
  Unsupported formats are identified and reported.
- Patching keeps the base ROM, the original patch files, the recipe and the result's hash. A
  patch's result is always a new Build, and toolchain detection runs on it.
- A base mismatch warns and allows an explicit Apply Anyway. For BPS, the warning compares the
  expected and selected input sizes and CRC32s.
- A patched Build's system comes from the patched ROM's own header, so a patch can turn a GB game
  into a GBC one or the reverse. A result too short for a header is refused.
- Generated ROMs are cache: kept for launch speed, evicted safely, rebuilt and hash-checked
  before launch. An output whose base or patch is missing isn't disposable.
- Open Patch (from a Game or a shared patch) requires choosing a Game and an explicit base Build.
- Each enabled step records the SHA-256 of the bytes it receives. Disabled steps have no input
  hash. Rebuilds check each recorded hash before applying its step and stop on a mismatch,
  naming the step and showing the expected and actual hashes together. Apply Anyway still checks
  the recorded input; it only bypasses the patch's own base check. Recipes without recorded input
  hashes still rebuild and check the final result.
- Build Technical Info lists the ordered patch filenames, Enabled or Disabled, and each expected
  input SHA-256 (touch and hold to copy), or Not recorded.
- v1.1: editable stacks (reorder, enable, disable, add, remove), each edit making a new Build;
  patch metadata with confidence, catalog over README over filename; BPS generation from a base
  and a modified Build. Future: Quick Play a patch without making a Build.

## Saves

### Profiles

- A profile's menu sets a one-emoji badge, shown before its name everywhere. Setting it leaves
  the profile's modified time alone, since that time decides whether an Auto State can restore.
- Deleting a profile asks first, naming it, and sends it to Recently Deleted with its save and
  states. A Game or Build that played it plays the Game's default instead.
- **Replace Save from File** asks first when the profile has a save, copies it to "<profile>
  before import", then writes the file. A blank profile fills without asking. An imported save
  records no writing Build, so it never raises the compatibility warning, and since it's newer
  than any Auto State, the next launch boots from it.
- A Game's default profile is starred, as its preferred Build is, and Play names the Build and
  save it will start, reading "New Save" when it will make one.
- The cartridge clock lives inside SameBoy's save, so games with a clock work. v1.1 adds
  a per-profile RTC offset and Developer Mode RTC controls.

### Build switching and compatibility

Each profile records which Build last wrote its save. Launching a Build with a save another Build
wrote checks the pair. It's risky when either Build was made with GB Studio, when detection names
different tools or engine versions, or when the headers declare different save hardware (bytes
0x147 and 0x149). A risky launch asks: Play with a Copy, Start a New Save, Use "<profile>" Anyway,
or Cancel. A copy or a new save becomes that Build's default, so it doesn't ask again. A save with
no recorded writer, or a check that fails, never blocks play: detection can add caution but never
proves two saves compatible.

A Build can keep variable maps (Attach Variable Map): GB Studio's `game_globals.i` or `globals.i`,
an RGBDS `.sym` or a GBDK `.noi`, stored immutably on that exact Build and listed in Technical
Info. They're kept for the GB Studio save migration in v1.1, which must be version gated and never
claims reliability from just an old ROM, old save and new ROM.

v1 adds declared save compatibility between Builds (known to share, known not to), used by this
check, and a warning when a Build of another region or language launches a profile, since many
games' saves don't carry across languages.

## Save states and lifecycle

- **Saving and loading.** Taking a manual or Auto State writes the battery save first. Manual
  state actions stop frames until they finish. Loading asks first when the game has saved since the battery save was
  last written, or when the state is older than the profile's save; going ahead keeps the current
  save as "<profile> before loading state". A state that fails partway puts the latest save back
  in the game.
- **Save States screen.** A profile's menu opens its states on every Build, newest first, with
  picture, Build and date. A state can be renamed (an empty name gives back "Save State" or "Auto
  State") or deleted to Recently Deleted. Loading stays in the game menu, where the Build and
  profile are already chosen. Crash-recovery checkpoints are hidden from both state lists.
- **Auto State.** Backgrounding, closing and switching sessions write the battery save and an
  Auto State, keeping the last five. Each step is attempted even if an earlier one fails, so the
  Auto State can recover progress a failed battery write lost. A close that fails keeps the game
  open, to retry or close without saving.
- **Restoring.** A library launch restores the newest Auto State for its Build and profile only
  when the profile's save hasn't been written since; otherwise it boots from the save and keeps
  the state. A SameBoy state carries the cartridge RAM it was taken with, so restoring an older
  one would roll a newer save back. A failed restore boots normally, keeps the state, and says so.
  If iOS ended the app after a library game went to the background and its Auto State was written,
  the next launch reopens that Build and Save Profile. A game the player closed does not reopen.
- **Resume Games** (Always by default; Ask or Never; App, System, Game or Build) decides whether a
  restorable Auto State is used, offered or ignored, at launch, on a background-session reopen,
  and when returning to the app. Crash recovery is a separate, explicit choice.
- **Pausing.** The game pauses whenever its scene goes inactive and lets go of every held button.
  After only an overlay (Control Center, Notification Center, a call banner) it resumes on its own
  unless the player had paused it; after the background, Resume Games decides. Backgrounding
  clears the open-session marker only after the Auto State is written; returning to play marks
  it open again.
- **Crash recovery.** During library play, one hidden `SaveStateKind.crashRecovery` checkpoint
  for the exact Build and Save Profile refreshes about once a minute of play, replacing the
  previous one in the existing state storage. A successful Auto State or clean close removes it.
  Starting a library game records an open session; clean close clears it.
  On the next launch, an open session with a checkpoint offers Recover Session or Start Normally.
  Recover Session opens that game from the checkpoint. Start Normally opens the library and keeps
  the checkpoint until the next launch of that Build, when it is removed. A crash never launches
  a game automatically, including a crash while recovering. Quick Play sessions are not recovered.
- One emulator session at a time.
- v1: Quick Save, configurable fixed slots, naming states when saving, configurable cleanup with
  pinned states exempt. v1.1: switching Build or profile from the game through the compatibility
  check and a relaunch.

## Quick Play

Quick Play plays a ROM without adding it to the library: the fast way for a developer to try a
fresh build.

- **Time to first frame is the primary metric.** The launch reads the image once, validates the
  header from that buffer, writes the sandbox copy, hashes the same buffer, and boots the core past
  the boot logo: the boot ROM still runs, unthrottled and undrawn with its chime dropped, and GBC
  uses SameBoy's `cgb_boot_fast`. A session resumed from its autosave doesn't boot at all. Nothing
  optional (shaders, skins, artwork, metadata, toolchain detection) runs before the first frame;
  detection runs only when Technical Info or Add to Library opens. Library launches show the boot
  logo unless Settings > Skip Boot Logo is on.
- A Quick Play session lives in a temporary workspace and never writes a library save. Using an
  existing save copies it in.
- The game menu shows Save State grayed out with "Add to Library to save states", and Add to
  Library closes the game and opens promotion. The session screen opens the ROM's Technical Info.
- Closing offers Keep for Later. Sessions expire after 24 hours; v1.1 makes that Immediately,
  24 hours or 7 days.
- An autosave records the battery file it was taken with and is skipped once that file is newer.
- **Add to Library** runs Import Review and can keep the library's existing save, replace it after
  a "<profile> before Quick Play" copy, or create a new profile. Kept progress becomes what the
  promoted Build plays, even when its ROM was already in the library; the Game's default and other
  Builds don't change. The session's autosave becomes the Build's Auto State for that profile, and
  a session with only a resume point can keep it in a new profile. Keeping the existing profile
  brings no state, since the state holds the discarded save. If the resume point can't move, the
  Build and save are still added and the session is kept.
- v1.1: screenshots, notes and debug captures in a session, moved over transactionally on
  promotion.

## Gameplay

### Controller layouts

Settings > Controller Layout (App, System, Game or Build; Game Boy by default) picks one of two
built-in layouts. Each also decides where the game picture goes.

A connected controller uses Game Boy while it drives the game, even when Playtiles is chosen,
so the picture and Orientation setting fit playing without the physical overlay. Disconnecting
restores the chosen layout without restarting the game, which pauses as for any unexpected
disconnect.

- **Game Boy** follows an original DMG-01's front panel, measured from Evan-Amos's public-domain
  photograph (`File:Game-Boy-FL.jpg` on Wikimedia Commons) and scaled to its 90 mm width. The
  D-pad (22.9 mm) and A and B (10.8 mm) are drawn at the hardware's size, about 6.1 points per
  millimeter, with A and B 16.8 mm apart on a 24.6° slope and SELECT and START tilted 18°,
  centered under the logo. Across the width the controls keep the Game Boy's proportions, pulled
  in so nothing leaves the screen. The picture sits at the top, the controls centered between its
  bezel and the logo, and touch areas reach 10 to 12 points past the drawn controls without
  overlapping.
- **Playtiles** uses the Playtiles GBC Delta skin's control frames, scaled to the screen, with
  START and SELECT in Game Boy order. A is larger than B, as in the skin, and controls respond
  across both the frame and the artwork. A raised alignment guide marks where the physical overlay
  sits. The skin's artwork isn't used.

The controls are drawn in code on a controller body behind them. Every control is raised like
the menu button: a face lit from above, light along the inside of its top edge and shade along its
bottom (deeper on bigger controls, up to 3 points), a thin rim and a shadow below. Pressed, it
goes flat, sinks a point, its shadow shrinks and its top edge shades the face. SELECT and START
are rubber pills, so they shade more from top to bottom, and Playtiles presses their labels into
them. The Game Boy D-pad never sinks: as in SameBoy's iOS app, it tips, so the held arm's end goes
into shade that fades out toward the center with no hard edge. Each arm has an arrow pressed into
it, and the dip at the center is lit as a hollow. The Game Boy layout prints "A" and "B" below the
buttons along their tilt and "SELECT" and "START" level below their pills; Playtiles keeps
unlabeled buttons and labeled pills.

**Controller Theme** (app-wide, Match System by default): Classic uses an original Game Boy's
colors sampled from the same photograph (warm gray body, gray lens, maroon-magenta A and B, dark
D-pad, gray pills, navy lettering); Dark is the same design on a near-black body with a charcoal
bezel and a lighter channel behind A and B. Match System picks Classic in Light Mode and Dark in
Dark Mode.

Touch: a sliding D-pad, sliding between A and B, and A+B together. Game Boy (portrait and
landscape) and Playtiles share the same direction rule: the weaker axis must exceed 67% of the
stronger one as well as the center dead zone to count as a diagonal. Away from the dead zone,
each diagonal spans about 22.5° around a corner (45°), and each cardinal spans about 67.5°.
The center dead zone stays at 16% of the pad's half-width on each axis.
The controller layout keeps the name Game Boy because it describes the hardware it recreates; the
App Store name, keywords and icon carry no Nintendo trademarks.

v1.1: a lightweight layout editor (screen and control position and size,
opacity, touch areas, separate portrait and landscape, a few control styles, saved presets),
opened from the game with the frame frozen for alignment and offering Save for This Game or Update
Shared Preset; Minimal, Fullscreen and one-handed presets; Delta and Manic skin import into the
native model, keeping the original package, previewing and reporting what isn't supported and
never mis-mapping a control; layout sharing through Files; per-device calibration for passive
accessories such as Playtiles and GameBaby, which are chosen by hand (an identifiable accessory
may suggest a preset, never switch to it); optional gestures, off by default; optional Turbo A
and B, not in the default layout.

v1.1: when the chosen layout fits a physical controller over the bottom of the screen, as Playtiles
does (and any later layout like it), the whole app moves into the top part of the screen that
stays visible: the library, Game Details, Settings, sheets and menus fit above the controller, and
its buttons move a focus through them, so the app can be used without taking the controller off.

### Landscape

Gameplay with the Game Boy layout turns to landscape, following Settings > Display > Orientation:
Automatic (the default, turning with the phone within its rotation lock), Portrait, or Landscape,
which turns the game at once even with the phone held upright and follows it between the two
sideways directions. Orientation inherits App, System, Game and Build, and a change from the game's
Settings sheet applies when the sheet closes. Playtiles without a connected controller, the library
and every sheet stay portrait whatever it says; closing a game held sideways returns to a portrait
library. With a controller connected, the Game Boy layout follows Orientation even if Playtiles
is the chosen layout.

Landscape uses the Game Boy Advance (AGB-001) arrangement whichever portrait layout is chosen: the
picture centered in its bezel at Screen Scaling's size, the D-pad on the left, A and B on the right,
and the Press Any button below the picture, where the Game Boy Advance prints its name. START and
SELECT are the Game Boy Advance's small round buttons, START above SELECT, right of the D-pad's
center and below it, each named on a recessed plate slanting down to the right beside it, placed
from a front photograph of an AGB-001; a tap on the plate counts. The D-pad and A and B keep the
Game Boy layout's sizes and drawing, and every control clears the phone's safe areas. Rotating
releases held input and keeps the game running or paused as it was, with Resume centered on the
picture. A connected controller still hides the touch controls.

### Game menu

- The Press Any wordmark at the bottom is a raised button with the wordmark pressed into it, on
  both layouts and themes, with or without a controller. Its tap area is 44 points tall. Settings
  > Tap Game for Menu (off by default) lets a tap on the picture open it too, but only for a touch
  that lands there, so a sliding thumb doesn't. VoiceOver finds it as the Game Menu button. The
  first game played says "Tap Press Any for the menu" once.
- Opening the menu stops frames and audio and releases held input. The menu holds Resume, Fast
  Forward (checked while on), Save State, Load State with each state, Settings, and Close Game in
  red in its own section. The game stays paused after the menu closes, after changing Fast Forward
  and after returning from another app, until the player chooses Resume. A paused game's Resume
  button sits centered on the game picture.
- **Settings** opens over the paused game at half height. A library game edits its Game's
  settings; Quick Play edits its system's. Layout, scaling, LCD filter and frame blending apply
  at once; the rest at the next launch.
- No controller button opens the menu by default, since Menu is START. v1 adds a fixed button
  combination that opens it; there's no button mapping in the app. The Home button is never
  taken, since Apple reserves it for the system.

### Picture

- **Screen Scaling** (App, System, Game or Build; Integer by default). Integer draws each Game Boy
  pixel as the largest whole number of device pixels that fits, centered on device pixels, falling
  back to Fill when not even one whole multiple fits. Fill draws as large as the frame allows at
  10:9, sampling each pixel flat and blending only across its edges. On the Game Boy layout the
  frame itself follows the setting.
- **Screen Colors** (System, Game or Build) is a different setting on each system, and only the
  one for the system at hand shows: in Game Boy or Game Boy Color settings, and in the Settings
  of a Game, a Build or the open game. App Settings doesn't show it.
  - Game Boy games choose their four shades, each named for the Game Boy screen it looks like:
    Green (Game Boy, the default), Olive (Pocket), Teal (Light) or Black & White.
  - Game Boy Color games choose how their colors are adjusted for a modern screen: Balanced (the
    default, SameBoy's Modern Balanced), Accurate (Modern Accurate), Boost Contrast, Reduce
    Contrast, Low Contrast, or Original, which shows the colors as the game stores them.

  Both change the open picture at once, including behind a paused Settings sheet, and stay
  applied through reset and state loads.
- **LCD filter**: LCD 1× and LCD 3×, the first of the display effects.
- **Frame Blending** (inheritable, Off by default): Blend averages each frame with the one before,
  as the slow LCD does, so a sprite drawn on alternate frames stays steady; LCD Ghosting weights
  the newest frame 0.5 and the two before 0.3 and 0.2. Both mix emulated frames, so 60 Hz and
  120 Hz look the same.
- The renderer is one plain Metal pass from SameBoy's 160×144 frame. Frames run on the display's
  refresh: each refresh adds the time since the last one, measured on the display's clock, and the
  game runs whole frames while it's owed one, then shows the newest. The game keeps its native
  59.73 Hz; on a 60 Hz screen one frame repeats about every four seconds. After a stall, a refresh
  longer than four frames counts as one frame, so the game doesn't race to catch up.
- v1.1: a curated, RetroArch-compatible shader library chosen after a community survey and device
  comparison (LCD1x, LCD3x and pixel-transparency variants are candidates; PT-SkyWalker541 is a
  candidate to audit), downloaded from pinned, license-checked sources with hashes and preserved
  licenses; independent inheritance of pipeline components and parameters; named presets; live
  switching from Quick Actions; a system-authentic default with raw pixels a tap away. Arbitrary
  `.slang` import is later.

### Sound

- Game sound plays through a buffer that starts at 40 ms. Each time playback runs dry the buffer
  grows 20 ms, up to 160 ms, and waits to refill, so a device under load gets one short gap
  instead of crackle; after 30 seconds without a shortfall it shrinks 20 ms. Playback runs up to
  0.5% fast or slow to track clock drift. The game's speed never changes for the sound. Sound more
  than three times the target behind is skipped. The app asks for 10 ms hardware buffers.
- **Sound** (app-wide): Follow Silent Switch by default, Always On, or Always Off, which mutes the
  game but leaves other apps' audio alone. It's in App Settings and in the game menu, where a
  change applies to the open game at once and becomes the app-wide setting.
- Genuine audio interruptions pause; route changes are handled without restarting.

### Speed

- **Fast Forward** in the game menu runs at Fast Forward Speed: 1.5×, 2× (default), 3×, 4×, 8× or
  Unlimited, inheritable, applied at once when changed from the game's Settings.
- **Fast Forward Audio**: Muted by default; Accelerated plays the sound sped up, pitch rising, up
  to 4×, and stays muted beyond.
- v1.1: Fast Forward from layouts, controller buttons and gestures through Quick Actions, hold or
  toggle; slow motion at 0.25×, 0.5× and 0.75×; rewind with 5 s, 15 s, 30 s, 1 min, 2 min and 5 min
  presets, memory-budgeted so the effective length can shrink on smaller devices, muted by
  default, surviving a brief trip to the background but never saved as a timeline; frame advance
  and a frame counter.

### Controllers, haptics and rumble

- Apple's GameController framework: Xbox, PlayStation, Switch-compatible, MFi and generic
  controllers. The D-pad and left thumbstick both drive the Game Boy D-pad; the stick has a radial
  dead zone of 25% and eight equal direction sectors. The controller's A and B buttons are Game Boy
  A and B; X is START, and Options or Y is SELECT. A PlayStation controller has no
  lettered buttons, so Circle is A and Cross is B, where a Game Boy has them, Triangle is START
  and Square is SELECT. Menu opens the game menu; pressing Menu again while it is open closes it
  and resumes, as Resume does. This works with touch controls hidden and uses no combo. Every
  Game Boy button keeps a controller button. The shoulders and triggers are left for Rewind and
  Fast Forward.
- Button mapping belongs to iOS: Settings > General > Game Controller customizations apply,
  including per-app ones, and are how a player moves any button. Press Any's defaults above are fixed: it has no button
  mapping of its own and won't add one. It declares Extended Gamepad support, which iOS
  needs for per-app customizations.
- With a controller connected the touch controls hide and the body stays. A touch outside the
  logo brings them back until the next controller button press. Settings > Controls > Hide Touch
  Controls, under With a Controller, is on by default.
- An unexpected disconnect pauses the game, releases held controller input, restores the chosen
  touch layout and shows a notice.
- Touch Haptics: Off, Light (default) or Medium, off while a controller is in use.
- Cartridge rumble goes to the controller when it can, the phone otherwise.
- v1.1: choosing Player 1 among several controllers (Player 2 is reserved for link play); Phone,
  Controller, Both or Off rumble routing with separate intensities.

### Quick Actions (v1.1)

One action registry powers the in-game menu, controller hotkeys and skin buttons: save and load
state, rewind, Fast Forward, slow motion, screenshot, note, manual, cheats, shader, Build and
profile switching, Build info, watches, frame advance, layout editing. It's reorderable, with
favorites. No separate command paths for menus, controllers and skins.

## Settings

Settings inherit App → System → Game → Build, the more specific winning. A level stores only
explicit overrides, the UI shows where an inherited value comes from, and Reset to Inherited
clears an override. The System level covers Game Boy and Game Boy Color. Save Profiles get only
the narrow playthrough overrides above. Sound is app-wide.

Inheritable today: controller layout, Orientation, Screen Scaling, Screen Colors (from System
down), LCD filter, Frame Blending, Fast Forward Speed and Audio, Resume Games and Skip Boot Logo.
App-wide: Controller Theme, Sound, Tap Game for Menu, Touch Haptics, Hide Touch Controls with a
Controller, and the region and language order.

App Settings is a short list of pages, like the iPhone's own Settings:

- **Controls**: Controller Layout and Controller Theme; Touch Haptics and Tap Game for Menu under
  Touch; Hide Touch Controls under With a Controller.
- **Display**: Orientation, Screen Scaling, and LCD Filter and Frame Blending under Effects.
- **Playing**: Sound; Fast Forward's Speed and Audio; Resume Games and Skip Boot Logo.
- **Systems**: Game Boy and Game Boy Color, each opening that system's settings.
- **Library**: Regions and Languages, Recently Deleted and Check Library.
- **About**: How Press Any Works, the Privacy Policy and Acknowledgements.

The settings for a system, a Game, a Build or the open game are one sheet, short enough to sit at
half height over a paused game. They're grouped under Display (Orientation, Screen Scaling, Screen
Colors, LCD Filter, Frame Blending), Controls (Controller Layout) and Playing (Fast Forward Speed
and Audio, Resume Games, Skip Boot Logo). Under each setting's name a note says where its value
comes from, such as "From Game Boy settings", or that it's set here.

v1.1 adds automatic DMG, GBC or SGB model selection with overrides at every level (no promise that
every GBC-only game works in DMG mode), and SGB palettes, borders and enhancements where SameBoy
exposes them; custom border editing is later.

## Deletion

- Games, Builds, Save Profiles and save states are deleted into Settings > Recently Deleted for 30
  days, with Restore and Delete Now, and purged at launch after that.
- Deletion is dependency-aware: the confirmation names patched Builds and emptied Games that go
  too, and a Game can't go while another Game's patch is built from it.
- Builds, Save Profiles and save states can also be deleted with a swipe to the left on their
  rows, and a Quick Play session discarded the same way. The swipe asks first, as the row's
  menu does. In Recently Deleted, swiping left is Delete Now and swiping right is Restore.
- A state deleted on its own comes back only once its profile and Build are back. Purging a
  profile or Build for good takes all its states, including ones waiting in another deletion.
- Purging writes a permanent tombstone so a deleted record can't come back from another device;
  tombstone expiry never counts as safe removal from an arbitrarily offline device.
- v1.1: lightweight Undo for recent structural changes.

## Shared files

- Press Any claims `.gb`, `.gbc`, `.ips`, `.bps`, `.sav` and `.srm` as an Owner handler. iOS has no user setting
  for a default app per file type. When two installed apps claim a type, iOS chooses which opens
  on a tap in Files; Owner rank does not guarantee Press Any wins. Share > Press Any (under More
  if needed) explicitly sends the file here.
- ROM document types also accept the identifiers in the public emulator plists below, so
  Press Any remains a handler when iOS resolves an extension to one of those types. Delta's
  current plist maps both `.gb` and `.gbc` to its `.game.gbc` identifier; it declares no separate
  `.game.gb`. No dedicated IPS/BPS identifiers were verified in these plists, so patches keep
  Press Any's imported identifiers only.

| Public Info.plist source | `.gb` identifier | `.gbc` identifier |
|---|---|---|
| [Delta](https://github.com/rileytestut/Delta/blob/c1d3d068e019e6493eed45654569db3cc5beb86a/Delta/Supporting%20Files/Info.plist) | `com.rileytestut.delta.game.gbc` | `com.rileytestut.delta.game.gbc` |
| [Provenance](https://github.com/Provenance-Emu/Provenance/blob/975f004a1e7a9a1b13db7d5c4899510a6fd866ae/Provenance/Provenance-AppStore-Info.plist) | `com.provenance.rom.gb` | `com.provenance.rom.gbc` |
| [SameBoy](https://github.com/LIJI32/SameBoy/blob/c458e7c5d2d350fb37a1931c40da9f758d28d240/iOS/Info.plist) | `com.github.liji32.sameboy.gb` | `com.github.liji32.sameboy.gbc` |
| [RetroArch](https://github.com/libretro/RetroArch/blob/2a515ab854de947bd3dad625c66e145a9d1a400b/pkg/apple/iOS/Info.plist) | `com.retroarch.gb` | `com.retroarch.gbc` |

- A shared zip, the way ROM hacks and homebrew are downloaded, opens each ROM, patch and save
  inside it in turn, as if each were shared on its own; readmes, folders and macOS metadata are
  skipped. Zip is registered at Alternate rank, so other zips keep opening where they did. It lists
  `com.pkware.zip-archive`, the type Files gives a .zip, as well as `public.zip-archive`. The
  zip is read in memory and never kept: at most 32 MB, its entries stored or deflated, each held
  to its own kind's size limit before it's inflated and checked against its CRC32. Encrypted,
  Zip64 and damaged archives are refused.
- A shared ROM offers Quick Play or Import to Library. A shared patch opens Open Patch, which
  needs a Game and a base Build. A BPS patch records its base ROM's size and CRC32, so Open Patch
  preselects the Build whose image matches, checking only images of that size. Without one, a
  Game whose title matches the patch's is preselected with its Base Build. A shared save opens
  Open Save, which imports it as a new Save Profile in the chosen Game. The Game is preselected
  when the save is named like exactly one Game's ROM file, as emulators name saves, or when its
  title matches one Game.
- A file shared mid-game opens over the game, which pauses as for the game menu and stays paused
  afterward. Quick Play from that sheet reads "Close Game and Quick Play": the running game closes
  the normal way, saving first, and a Quick Play session still offers Keep for Later before the new
  ROM starts.

## Library

- A square box-art grid (Show Titles on by default, and one column at accessibility text sizes)
  and a compact list, with search by primary title and aliases. Cartridges without artwork take a
  color per system and print the title on the label.
- Game Details lists Builds and Save Profiles, and Play starts the preferred Build with its
  profile. The Build menu groups playing and saves, details, editing, then Make Separate Game.
  Technical Info shows hashes (four groups of 16 on two lines, copied by touch and hold), the
  stored metadata, verification, when the Build was added, and Made With: an engine such as GB
  Studio above the toolchain it runs on, names as their projects spell them, version ranges as
  "x to y" or "x or later".
- Favorites appear as a small star on grid tiles and list rows, including tiles with titles hidden.
  Favorite in Game Details and Add to Favorites or Remove from Favorites beside Play and Rename
  in the library's long-press menu change the same Game flag. Favorites Only in the view menu
  works with title and alias search.
- A welcome screen on first launch explains the library, Builds, saves, Quick Play, the game
  menu, exports, and that the app comes with no games. It shows once, again only when its
  content version rises, never in automated runs, and never ahead of a shared file or game.
  Settings > How Press Any Works reopens it. v1 replaces it with onboarding that covers opt-ins
  and introduces advanced features in context.
- v1: SQLite FTS5 live search across titles, aliases, filenames, hack title, author, version,
  system, region, Build names, tags and document titles, title matches ranked first; manual and
  smart collections (GB, GBC, Homebrew, ROM Hacks, Favorites, Recently Played, Builds with
  updates); tags on Games and Builds behind long-press and overflow; sorting by title, recent
  play, added, playtime, year, system, developer, publisher, hack author, Build version and date,
  last Build change and manual order; play statistics (no permanent session log); an
  optional Developer view.

## Toolchain detection

A port of gbtoolsid's fingerprint logic and data, never its command-line tool. One detector
serves Import Review, Technical Info, Quick Play and the save check. A Build keeps one report per
detector; Technical Info detects again and keeps a changed result, and "not recognized" is a
stored result. Each finding carries a version or range, evidence, and a confidence from its own
signatures: high for two or more, medium for one, low when inferred. Layers can coexist (GB
Studio over GBDK, with an audio driver). RGBDS detection isn't guaranteed. Detection never names
or groups a Game and never proves two saves compatible.

## Planned areas

Areas marked v1.1 wait for it; the rest target v1.

### Cheats and memory tools (v1.1)

Cheat management (add, remove, enable, disable, keep) in Game Genie, GameShark and the formats
SameBoy supports; a pluggable cheat database keyed to verified ROMs, adding selectively and never
enabling anything on its own; optional groups and search. Memory search: exact, unknown, changed,
unchanged, increased, decreased, by an amount, greater or less, in signed or unsigned 8 and 16-bit
and hex; results can be edited, frozen, watched, turned into a cheat or copied. Named searches last
for the session. A watch list with an optional Developer HUD and short in-memory history. Developer
Mode writes take effect at once, with Undo Last Write and a clear frozen marker. A full debugger,
disassembler and VRAM viewer are later.

### Screenshots, notes and debug context (v1.1)

An in-app gallery where every capture belongs to its exact Build, exported clean, with metadata,
or with a rendered Build Info or Bug Report strip. An optional capture context records selected
watches, named variables when maps exist, memory ranges, registers, frame and time, Build, hash
and patches, RTC, cheats, profile, core and settings; a full RAM snapshot is opt-in in Developer
Mode. Bug-report exports preview a checklist, and memory, saves and notes need explicit inclusion.
Game notes and timestamped gameplay notes; each Build already has a plain-text note in Build Details.

### Documents (v1.1)

Manuals, READMEs, changelogs, guides and maps as managed copies (PDF, CBZ, PNG, JPEG, WebP image
sets, TXT, Markdown), belonging to a Game, a Build or both. A reader opens over the paused game,
remembers the last position, and restores the running or paused state on close. Search in text
formats only if it's easy; no OCR. Side-by-side reading on iPad is later.

### Artwork (v1.1)

Automatic artwork on import, which a setting can turn off, through pluggable providers: included
or imported files, the Community Catalog, Libretro thumbnails, OpenVGDB pending its license,
optional SteamGridDB with the player's own key, and a fallback generated from the game's title
screen, recorded as generated so anything chosen or more specific wins. Priority: the player's
choice, then hack-specific, then inherited from the base game, then generated. Several typed
images per Game (box front and back, cartridge, title screen, screenshots, logo, custom) with one
primary, a Game default and Build overrides, and non-destructive crops. Only the chosen image is
cached; nothing rechecks after a choice except Check for New Artwork. Provenance (provider, URL,
date, rights, crop) is kept, and private artwork is never published. There's no paid artwork
agreement.

### External display (v1.1)

AirPlay and wired displays show the game as an independent render target with its own scaling,
aspect and shader, while the phone becomes a controller with Quick Actions, the manual, states and
Build switching. Chromecast is out of scope.

### iCloud (v1.1)

Syncs everything except ROMs: metadata, profiles and saves, states, cheats, settings, tags,
artwork and document overrides, patches, layouts, notes, captures and statistics. Field-level
merges where safe; divergent `.sav` files are both kept for the player to choose, keep both as
separate profiles, or duplicate first. Deletions sync as tombstones. iCloud is sync, not hidden
save history.

### Community Catalog (v1.1)

v1.1 reads a signed catalog file offline: Game and Build metadata, expected hashes, lineage and
where to download patches, never ROMs. Playing, importing and patching never depend on it. The
hosted service follows: anonymous reading, an account to contribute, optional attribution,
moderation with reasons for rejections, field-level corrections with evidence, Suggest This
Correction after a local edit (never automatic), and no comments or ratings. Update discovery shows
a quiet badge by default, with optional verified pre-download and per-Game overrides; an update
arrives through Import Review as a new Build, leaving the old one for rollback. No commercial ROM
hosting; creator-published homebrew comes later through its own rights-aware flow. Original
community metadata aims for CC0, and imported data and media keep their own rights.

### Backups

Library Backup export and import: a documented, versioned archive with a manifest, ordinary files,
checksums and a schema version. User data is included and ROMs only when asked. Optional password
encryption, with no recovery promise. Restore merges by stable IDs and hashes with conflict review,
or replaces the whole library on request, and shows a report before and after. Adapters for Delta,
Manic, Afterplay and Playtiles exports come later and report what they can't carry over.

### Developer Mode (v1.1)

An Advanced toggle with an explanation. Its tools (memory search and editing, watches, hashes,
patch provenance, frame advance, RTC controls, save details) appear in context rather than
replacing the interface.

### Privacy and telemetry

Crash reports and anonymous usage counts (v1.1) are both opt-in. Usage counts are numbers only (Games,
Builds per Game, profiles shared by Builds, Quick Play sessions promoted), never titles, hashes,
filenames or library contents; where they go and the privacy copy are still open. Nothing
automatic ever uploads ROM, save or state bytes, screenshots, memory, filenames, notes or library
contents. Provider queries and catalog uploads describe their consent accurately. Service keys
stay on servers and user keys in secure storage. The privacy manifest declares file timestamp
access (C617.1) for cleaning stale temporary files.

### Accessibility

Dynamic Type in the normal interface, good contrast and status that doesn't rely on color, Reduce
Motion, large and configurable touch targets, one-handed layouts (v1.1, with the layout editor),
controller remapping through iOS's Game Controller settings, controller navigation where
practical, sensible VoiceOver labels, and haptics never as the only feedback.
Narrated gameplay isn't a v1 requirement.

### Performance

Correct timing comes first. Under thermal pressure (v1.1, once shaders and rewind exist), optional shaders, rewind
length and background work give way before gameplay, audio or input do; emulation speed and save behavior never change
silently. The default shader must hold full speed on the slowest supported device.

### Architecture seams

- Platform IDs are neutral data values (`gb`, `gbc`, later `gba`). Platform, hardware (such as an
  original GBC or a ModRetro Chromatic), distribution and compatibility records are separate
  concepts; core compatibility isn't hardware compatibility.
- Contracts say `GameImage` and `PersistentSave` rather than ROM and battery; GB-specific UI still
  says ROM and .sav. Cores and toolchain detectors have registries; platforms, image analyzers and
  patch formats get theirs in v1.1, with input and memory descriptors.
- A Build pins the core version it first launched with. v1.1 shows a quiet notice when a newer core
  is available and makes migration an explicit, reversible checkpoint that starts a new state
  lineage; rolling back is offered only when the old core can actually run.
- `FeatureEntitlementProvider` keeps StoreKit out of the domain, core, storage and import code.
  Losing an entitlement never locks away saves, exports or anything the player made.
- Optional Included Games: a small set of rights-cleared homebrew, imported through the normal
  path from a manifest with permission records; a release fails if it packages an unapproved ROM.

## v1.1 and later

- **v1.1:** cheats and memory tools (above), with states recording their cheat configuration and
  offering to restore it; the app's screens fitting above a controller that covers the bottom of the screen, as
  with Playtiles, and navigable with its buttons; link cable (local first, then nearby; not built on Multipeer Connectivity), GB Studio
  save migration, Game Boy Camera and Printer, RAR, skin authoring beyond the editor, video and GIF
  capture framed like a Game Boy, `.gbproject` import and export, better ROM comparison and BPS
  generation, side-by-side manuals on iPad, itch.io and Homebrew Hub browsing and shared game pages.
- **Later:** mGBA for GBA (1.2 or 2.0), network link play, RetroAchievements, a full debugger,
  deterministic replay, arbitrary `.slang` shaders, Apple TV and macOS, creator-published
  homebrew, document annotations and OCR, Save Profile locking, developer tools (a watched folder
  whose new ROMs import as Builds, GitHub releases or CI builds as Builds, a tester bug-report
  bundle) and iOS integration (a Continue Playing widget, Siri and Shortcuts, Spotlight).
- **Out of scope:** Chromecast, getting commercial ROMs, silently repairing ROMs, live ROM
  swapping, and social features in the catalog.

## Rights and dependencies

- Project source is Apache-2.0; that never relicenses dependencies, shaders, artwork or games.
  Prefer permissive dependencies; GPL, AGPL and LGPL components need approval, mGBA's MPL needs
  deliberate compliance, and Delta and Manic format support must not copy their AGPL code.
- GRDB resolves through SwiftPM at a pinned version; SameBoy is a pinned submodule. Upstream
  licenses are kept in `THIRD_PARTY_NOTICES.md`.
- No commercial ROMs or saves as fixtures. `TestROMs/` holds original, redistributable ROMs built
  from source beside them, each listed in `TestROMs/manifest.json`.
- App Store screenshots and previews show homebrew and the original test ROMs only.
- v1.1 adds CONTRIBUTING, SECURITY, a code of conduct and a trademark policy, with DCO sign-off and
  no copyright-assignment CLA.

## Automation

Generated data comes from reviewed, reproducible GitHub Actions workflows with pinned inputs,
recorded provenance and output digests; update jobs open pull requests rather than publishing.
Fork jobs get no secrets. A workflow whose source or rights aren't settled stays honestly disabled
rather than echoing success. `docs/ci.md` lists what runs today; still to come are toolchain
fingerprint updates, the shader catalog, Included Games verification, fixture regeneration,
license and privacy audits, and OpenVGDB (disabled until its license is clear). No-Intro data is
refreshed by hand, as above.

TestFlight builds are signed and uploaded by GitHub Actions from a temporary keychain, so no Mac is
needed. Each commit on `main` uploads once its checks pass, and any branch can be uploaded by hand
to test it on a phone before merging; `docs/release.md` and `docs/testflight.md` cover setup.

## Evidence

`docs/acceptance-matrix.md` defines the evidence levels: L1 domain, L2 persistence and storage, L3
headless SameBoy, and L4 Apple SDK, simulator and physical device, which are never claimed from
syntax checks. `docs/mvp-verification.md` is the device checklist. The architecture proof was
accepted on 2026-10-06; its checks stay as regression coverage for one Game across many Builds,
safe profile sharing and forking, Build-specific states, deterministic patch rebuilds, Quick Play
isolation and promotion, and promote and merge preserving lineage.

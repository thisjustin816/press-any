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

- iOS 17 or later, iPhone first. iPad keeps working but gets no special design until later.
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
curated shaders, the layout editor and skin import, screenshots and notes, external displays,
crash reporting and usage counts, and Developer Mode.

## Library model

### Game

A Game is what the player thinks of as the game. It survives ROM replacement, patching, new
versions, regional and revision variants, and Builds moving in or out. It has a UUID, a primary
title, a system, a preferred Build and a default Save Profile. A promoted hack is titled by its
own name; the base game's title stays as lineage.

v1 adds aliases (indexed for search, including a No-Intro family's regional titles), favorites
and metadata provenance; tags, collections, documents and typed artwork follow in v1.1.

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

v1 adds Build notes, per-Build playtime and a lightweight timeline (versions, hashes, parents,
notes, import and activation history), and a Build comparison screen. The comparison engine
(changed bytes and ranges, size, banks, header) exists; the screen doesn't yet.

### Save Profile

A Save Profile is a named playthrough with one current battery save, such as Main, Nuzlocke or
Testing. Profiles can be blank, duplicated, imported from a `.sav`, or promoted from Quick Play,
and they're listed flat, with a subtle "copied from" note rather than a tree. Compatible Builds
can deliberately share one. A Build remembers its preferred profile and falls back to the Game's
default.

There is no rolling battery-save history. Isolation comes from duplicating profiles. A profile
can carry only narrow playthrough settings (cheats, RTC offset, rewind where it makes sense),
never a full fifth settings layer.

### Save state

A save state belongs to one exact context: Build, Save Profile, image hash, core and state
serialization version. States never load across Builds, even when the Builds share a battery
save. Each state keeps a thumbnail of its frame, the time, playtime and an optional name. Manual
states, lifecycle Auto States and (v1) crash-recovery checkpoints are separate kinds.

### Patch recipe

A recipe records its exact base Build and hash, its ordered IPS or BPS patches, each step's
enabled state, and the hash of its result. The executable identity is the result's hash, not the
recipe.

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

- The file picker, and Share Sheet / Open In for `.gb`, `.gbc`, `.ips` and `.bps`. The document
  types are registered in Info.plist.
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
  suggests a Game whose title matches the file's title, header title or a hack's base title,
  ignoring case, punctuation and spacing. Only whole titles match ("Mega Man 2" never joins
  "Mega Man"), and two matching Games suggest neither. An uncertain ROM is never attached silently.
- **Roles.** Every new Build defaults to Preferred. It defaults to Base when the Game has none,
  unless it's a ROM hack. Where the Game has a Base, only a newer homebrew release defaults to
  replacing it: one whose version or date sorts after the Base's, or any versioned file when the
  Base has none. A retail revision or a beta leaves a clean Base alone. ROM hacks and
  patch-created Builds are Preferred but not Base. A role the player sets stays when the
  destination changes.
- **Metadata.** Region, language, revision and version fill from the filename (see Naming) and a
  nonzero header revision, and the player can correct or clear them. Unknown tags stay as written.
  Review labels its fields and explains Base Build and a wrong header checksum.
- **Toolchain detection** runs when an image becomes a Build, and review shows what it found.
- **Duplicates.** An exact duplicate image never makes a second file or Build. Its existing Build
  keeps its metadata. In v1.1, a duplicate import still inspects anything new that came with it
  (saves, artwork, documents, patches).
- A file shared while another sheet is open, such as Import Review mid-edit or the Resume prompt,
  waits until that sheet closes.

### Planned (v1.1 unless noted)

- v1: development matching from several signals, preselecting a Game only at high confidence.
- ZIP and 7z through libarchive, as temporary containers that aren't kept. Limits on nesting
  depth, size and ratio; no path traversal or links; malformed and password-protected archives
  fail cleanly. RAR is tentative.
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
- Each imported image stores its SHA-1 beside the SHA-256 that stays its identity. Nothing else
  No-Intro says is stored: dump status, family and regional titles are looked up when needed, so
  the library never carries stale names.
- A known dump takes its canonical name ahead of the filename, and a Game created from one is
  titled by it. The original filename is always kept.
- A Build's Technical Info shows Verified (with the dump's name), Bad Dump, Modified (patched from
  a verified dump) or Unknown. The app never alters a ROM to make it match.

### Naming rules

Filenames are evidence, not truth. Parsed values keep their source, the player's corrections win,
and identity and bytes never change. The same rules name Builds in Import Review, Quick Play
promotion and Open Patch.

- Region and language groups, "Rev 1" or "Rev A" (a retail revision), "v1.2" and "Version 1.2"
  are recognized. A dotted "Rev 0.2.0" is a homebrew version. Versions keep a semver suffix such
  as "-beta.3" and sort by their numeric part. Loose forms such as "r2" or a bare trailing number
  stay in the title, since "R-Type" and "Mega Man 2" look the same.
- A date stamp after the title, as in "AeonMetalFighters_20261006_classic", becomes the version,
  shown as "2026-10-06" and sorted by date; the words after it become the status. Only a valid
  eight-digit or hyphenated date counts, and never as the whole title.
- A file with no version tags is named for the day it's added, "2026-10-06", then the time for a
  second one the same day. A hack with nothing else to name it is "Hack".
- A suggested name that repeats one already in the Game gains the day ("v1.0 · Oct 6"), then the
  time, then a number. A name the player typed is left alone. A Build sharing its name with
  another shows its date and time in the list.
- Suggest Build Names, in the library's view menu, offers these names for Builds whose names look
  generated: URL escapes, the bare source filename, repeats, or the generic "Original" and "Hack".
  Nothing is renamed until the player chooses Rename.

### Planned (v1)

- Richer ROM-hack metadata (hack title, author, version from bracket conventions) and a
  normalized filename suggestion, without inventing fields.
- Rename File to Canonical Name as an explicit action; bulk rename later.
- Match Game for unknown ROMs, including base-game lineage without owning the base ROM, and
  offering to link the base when it's imported later.
- Regional releases: a preferred region and language order (USA, Europe, Japan by default) that
  picks a Game's display title and which regional Build defaults to Preferred; Import Review
  proposes the better title and the Preferred mark when a higher-ranked region arrives, and the
  player confirms; nothing renames a Game on its own. Also artwork by region, patch review
  offering the Game's other regional Build when a patch expects it, and a reviewed suggestion to
  merge Games already in the library that are one No-Intro family.
- Metadata provenance with a Metadata Details view, quiet provider refreshes that never overwrite
  the player's values, and Build version ordering from semantic versions, build numbers and dates.

## Restructuring Games

- **Make Separate Game** promotes a Build to its own Game, by Move (default) or Copy, without
  re-importing. Build-scoped data (states, recipes, toolchain reports, variable maps, settings)
  always follows the Build. A review sheet chooses the Game-level things: it offers copies of the
  Game's artwork and Save Profiles, selecting the artwork and the profiles the Build plays or last
  wrote. Copies get their own files. The promoted Build plays its copy of the profile it played,
  and its states move to those copies, keeping their save times so Auto States still resume. The
  new Game records Split From, which survives the source Game's deletion. Promoting a Game's only
  Build by Move just renames the Game.
- **Merge into Another Game** reviews in its own sheet: Move or Copy, the target, and the profiles
  and artwork that come along. Move takes every profile, since the source Game goes away; the
  target keeps its artwork unless Use <source>'s Artwork is on. Copy offers the source's artwork
  and profiles. When the target already holds the same image, Copy skips that Build and Move is
  refused, since moving would drop the Build's states or let them cross Builds.
- A Build's menu has Mark as Base Build and Unmark as Base Build.

## Patching

- IPS and BPS for v1, through a pluggable format system; IPS32, UPS, xdelta and others later.
  Unsupported formats are identified and reported.
- Patching keeps the base ROM, the original patch files, the recipe and the result's hash. A
  patch's result is always a new Build, and toolchain detection runs on it.
- A base mismatch warns and allows an explicit Apply Anyway.
- A patched Build's system comes from the patched ROM's own header, so a patch can turn a GB game
  into a GBC one or the reverse. A result too short for a header is refused.
- Generated ROMs are cache: kept for launch speed, evicted safely, rebuilt and hash-checked
  before launch. An output whose base or patch is missing isn't disposable.
- Open Patch (from a Game or a shared patch) requires choosing a Game and an explicit base Build.
- v1: each step records the input hash it expects, so a stacked IPS patch can't apply to the
  wrong input unnoticed, and review shows expected and selected hashes side by side; editable
  stacks (reorder, enable, disable, add, remove), each edit making a new Build; patch metadata
  with confidence, catalog over README over filename.
- v1.1: BPS generation from a base and a modified Build. Future: Quick Play a patch without
  making a Build.

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
- The cartridge clock lives inside SameBoy's save, so games with a clock work. v1 adds a
  per-profile RTC offset and Developer Mode RTC controls.

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

- **Saving and loading.** Taking a state writes the battery save first. Loading or saving stops
  frames until it finishes. Loading asks first when the game has saved since the battery save was
  last written, or when the state is older than the profile's save; going ahead keeps the current
  save as "<profile> before loading state". A state that fails partway puts the latest save back
  in the game.
- **Save States screen.** A profile's menu opens its states on every Build, newest first, with
  picture, Build and date. A state can be renamed (an empty name gives back "Save State" or "Auto
  State") or deleted to Recently Deleted. Loading stays in the game menu, where the Build and
  profile are already chosen.
- **Auto State.** Backgrounding, closing and switching sessions write the battery save and an
  Auto State, keeping the last five. Each step is attempted even if an earlier one fails, so the
  Auto State can recover progress a failed battery write lost. A close that fails keeps the game
  open, to retry or close without saving.
- **Restoring.** A library launch restores the newest Auto State for its Build and profile only
  when the profile's save hasn't been written since; otherwise it boots from the save and keeps
  the state. A SameBoy state carries the cartridge RAM it was taken with, so restoring an older
  one would roll a newer save back. A failed restore boots normally, keeps the state, and says so.
- **Resume Games** (Always by default; Ask or Never; App, System, Game or Build) decides whether a
  restorable state is used, offered or ignored, at launch and when returning to the app.
- **Pausing.** The game pauses whenever its scene goes inactive and lets go of every held button.
  After only an overlay (Control Center, Notification Center, a call banner) it resumes on its own
  unless the player had paused it; after the background, Resume Games decides.
- One emulator session at a time.
- v1: Quick Save, configurable fixed slots, naming states when saving, configurable cleanup with
  pinned states exempt, a separate crash-recovery checkpoint with Recover Session or Start Normally (no automatic crash
  loops; a force-quit gives no final callback), returning to the previous game after a relaunch,
  and switching Build or profile from the game through the compatibility check and a relaunch.

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
- Closing offers Keep for Later. Sessions expire after 24 hours; v1 makes that Immediately, 24
  hours or 7 days.
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
  sits. Its diagonals need the weaker axis to exceed 65% of the stronger one as well as the center
  dead zone, which widens the straight directions. The skin's artwork isn't used.

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

Touch: a sliding D-pad with natural diagonals, sliding between A and B, and A+B together. The
controller layout keeps the name Game Boy because it describes the hardware it recreates; the
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
  A and B; Menu or X is START, and Options or Y is SELECT. A PlayStation controller has no
  lettered buttons, so Circle is A and Cross is B, where a Game Boy has them, Triangle is START
  and Square is SELECT. The shoulders and triggers are left for Rewind and Fast Forward.
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
- v1: choosing Player 1 among several controllers (Player 2 is reserved for link play); Phone, Controller, Both or Off
  rumble routing with separate intensities.

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
App-wide: Controller Theme, Sound, Tap Game for Menu, Touch Haptics and Hide Touch Controls with a
Controller.

App Settings is a short list of pages, like the iPhone's own Settings:

- **Controls**: Controller Layout and Controller Theme; Touch Haptics and Tap Game for Menu under
  Touch; Hide Touch Controls under With a Controller.
- **Display**: Orientation, Screen Scaling, and LCD Filter and Frame Blending under Effects.
- **Playing**: Sound; Fast Forward's Speed and Audio; Resume Games and Skip Boot Logo.
- **Systems**: Game Boy and Game Boy Color, each opening that system's settings.
- **Library**: Recently Deleted and Check Library.
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
- A state deleted on its own comes back only once its profile and Build are back. Purging a
  profile or Build for good takes all its states, including ones waiting in another deletion.
- Purging writes a permanent tombstone so a deleted record can't come back from another device;
  tombstone expiry never counts as safe removal from an arbitrarily offline device.
- v1: lightweight Undo for recent structural changes.

## Shared files

- A shared ROM offers Quick Play or Import to Library. A shared patch opens Open Patch, which
  needs a Game and a base Build.
- A file shared mid-game opens over the game, which pauses as for the game menu and stays paused
  afterward. Quick Play from that sheet reads "Close Game and Quick Play": the running game closes
  the normal way, saving first, and a Quick Play session still offers Keep for Later before the new
  ROM starts.

## Library

- A square box-art grid (Show Titles on by default, and one column at accessibility text sizes)
  and a compact list, with search by primary title. Cartridges without artwork take a color per
  system and print the title on the label.
- Game Details lists Builds and Save Profiles, and Play starts the preferred Build with its
  profile. The Build menu groups playing and saves, details, editing, then Make Separate Game.
  Technical Info shows hashes (four groups of 16 on two lines, copied by touch and hold), the
  stored metadata, verification, when the Build was added, and Made With: an engine such as GB
  Studio above the toolchain it runs on, names as their projects spell them, version ranges as
  "x to y" or "x or later".
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
  last Build change and manual order; favorites and play statistics (no permanent session log); an
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
Game notes, Build notes and timestamped gameplay notes.

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

Correct timing comes first. Under thermal pressure, optional shaders, rewind length and background
work give way before gameplay, audio or input do; emulation speed and save behavior never change
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

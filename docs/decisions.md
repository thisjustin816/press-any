# Decisions

Product decisions made after the specs in `docs/specs/`, newest first. Each entry wins over the
specs where they conflict; update the spec it touches in the same change.

## 2026-10-05: Pause when the app goes inactive, and keep Quick Play progress with its Build

**Decision.** The game pauses whenever its scene goes inactive, not only in the background, and
lets go of every held button. After only an overlay such as Control Center, Notification Center or
a call banner, it picks up again on its own, unless the player paused it. After a trip to the
background, Resume Games (Always, Ask or Never) decides, as before. Loading or saving a state
stops frames until it finishes, and loading a state asks first whenever the game has saved since
its battery save was last written, since that in-game save is newer than any state. Taking a state
writes the save first. A state that fails partway puts the latest save back in the game.

When Quick Play is added to the library with its progress kept, the promoted Build plays that save
by default, even when the ROM was already in the library as a Build: the player chose to keep this
progress. The Game's default and other Builds don't change. A session with only a resume point,
from a game with no battery save, can keep it in a new profile. If the resume point can't be
moved, the Build and save are still added and the Quick Play session is kept, so the resume point
isn't lost.

A patched Build's system comes from the patched ROM's own header, by the rules import uses, so a
patch can make a Game Boy game a Game Boy Color one or the reverse. A result too short to hold a
header is refused. Patched Builds made before this keep the system they were given; none have been
released, so there is no repair.

The privacy manifest declares file timestamp access with reason C617.1, for the cleanup of stale
temporary files inside the app's own container.

**Why.** A review found that the state-load warning looked only at when the save was last written,
so an in-game save not yet written could be lost; that Quick Play progress from a game with no
battery save was dropped on promotion, and kept progress wasn't what Play picked; that patched
Builds always took their base's system, which also picks SameBoy's model and boot ROM; that the
game ran on under Control Center and other overlays; and that the manifest left out the cleanup's
timestamp reads.

## 2026-10-05: Adaptive audio, and registries wait for v1

**Decision.** Game sound plays through a buffer that starts at 40 ms. Each time playback runs out
of sound, the buffer grows 20 ms, up to 160 ms, and playback waits for it to fill before it starts
again, so a device under load gets one short gap instead of a crackle. After 30 seconds with no
shortfall it shrinks 20 ms. To hold the buffer near its target as the output's clock drifts from
the emulator's, playback runs up to 0.5% faster or slower; the game's speed never changes for the
sound (Q96). Sound that piles up past three times the target, after a stall or in Fast Forward,
is skipped so it doesn't play late. The app asks for 10 ms hardware buffers. Frames are scheduled
against fixed deadlines, so time lost oversleeping one frame is made up on the next instead of
running the game slightly slow.

The registries for platforms, image analyzers and patch formats move to v1. Cores and toolchain
detectors keep theirs.

**Why.** The audio queue was a fixed 250 ms ceiling that dropped the oldest sound when it filled
and played silence when it ran dry, with no target, so latency drifted anywhere up to 250 ms and
every shortfall clicked. The frame loop slept a full frame after each one, so oversleeping ran
the game a little slow and starved the queue. With Game Boy as the only platform, the three
registries would add structure nothing uses, and v1 adds the next platform or analyzer that
needs them.

## 2026-10-05: Import hardening

**Decision.** Every file the player picks is treated as untrusted. Each import checks the file's
size before reading or staging it, against a limit for its kind: 8 MB for a ROM, the largest a
header can declare; 16 MB for a patch; 4 MB for a battery save, since TPP1 cartridges can declare
2 MB of RAM; 20 MB for artwork; and 4 MB for a variable map. A larger file is refused with a
message saying so. Staging copies only regular files, never a link or a folder, under a fixed
name, and the app empties the staging folder at launch to clear copies an interrupted import left.
An IPS patch's trailing size can only truncate the result, as in Lunar IPS; a larger one is
ignored. Artwork is decoded when it is set and stored as a PNG no larger than 1024 pixels on its
long edge, and a file that isn't a readable image is refused. The SameBoy bridge hands battery
saves to the core in a zero-padded copy, because SameBoy reads up to 48 bytes past the cartridge
RAM when a save is longer than the RAM. SameBoy also doesn't check the allocation it makes when
loading a ROM, so the bridge refuses any image over 8 MB, the most a cartridge maps, and makes
sure the memory SameBoy will ask for is available before handing the image over. A patch whose
result is over 8 MB fails when the Build is made, not when it's played.

**Why.** A review with fuzzers and AddressSanitizer found a heap over-read in SameBoy's battery
loading, imports that read whole files of any size into memory, staging that trusted the picked
file's name and copied links, an IPS trailer that could grow any ROM to 16 MB, and artwork stored
at whatever size it was picked. Each could be reached with a file a player picked.

## 2026-10-05: Layouts at accessibility text sizes

**Decision.** At accessibility text sizes the library grid shows one column, with each title
wrapping in full, a Build's BASE tag moves to its own line under the name, and a full SHA-256
shows one 16-character group a line, each shrinking to fit rather than breaking. The screenshot
workflow can run at the largest size to check this.

## 2026-10-05: Future features, and the layout keeps its name

**Decision.** v1.1 adds browsing and downloading games from itch.io's Game Boy tag, in an in-app
browser, and from Homebrew Hub (hh.gbdev.io) through its API, from the library's + menu.
Downloads go straight to Import Review, with Quick Play. Video capture in v1.1 also frames
screenshots and clips like a Game Boy. Later: developer tools (a watched Files or iCloud Drive
folder whose new ROMs import as new Builds, GitHub releases or CI builds as Builds, and a tester
bug report bundle with the save, state, screenshot, Build hash and toolchain) and iOS integration
(a Continue Playing widget, Siri and Shortcuts, Spotlight). The controller layout keeps the name
Game Boy, which describes the hardware it recreates, as the system names do; the App Store name,
keywords and icon carry no Nintendo trademarks.

**Why.** Most Game Boy homebrew is published on itch.io and catalogued by Homebrew Hub, and the
app's Builds, toolchain detection and variable maps already serve the people who make it.

## 2026-10-05: Save safety fixes

**Decision.** A review found several ways a save could be lost or rolled back, and each now
behaves as follows:

- **In-game saves reach disk during play.** The game's battery save is written once it changes,
  checked at most every five seconds of play, in library sessions and Quick Play alike. A crash or
  a killed app loses at most those few seconds of in-game saving.
- **Background and close attempt every save step.** A failed battery write no longer skips the
  Auto State, which is then the way back to that progress. When a close fails, the game stays open
  so the save can be retried, or closed without saving.
- **Loading an older state warns first.** When a state is older than its profile's save, loading
  it would take the save back with it. The app asks, and when the player goes ahead it keeps the
  current save as "<profile> before loading state", as Replace Save from File does.
- **Quick Play resumes only from a current autosave.** An autosave taken before `battery.sav` was
  last written is skipped and the game boots from its save. Each autosave records the battery file
  it was taken with, since file dates are too coarse to order two writes made moments apart.
- **Make Separate Game takes a moved Build's states along.** They move to the profile copies the
  Build plays, so Load State still lists them and deleting an original profile leaves them. A copy
  keeps its original's save time, so its Auto States still resume.
- **Add to Library keeps the Quick Play resume point.** The session's autosave becomes the new
  Build's Auto State for the promoted profile, and the first launch resumes there under Resume
  Games. Keeping the existing profile brings no state, since the state holds the discarded save.
- **Writes are durable.** Atomic writes use `F_FULLFSYNC` where available and sync the directory
  after the rename, and Quick Play writes through the same writer. Check Library Files removes
  temporary files an interrupted write left behind, once they are ten minutes old.

**Why.** Each of these lost a save, or a resume point, in a case a player could reach: a crash
between backgrounds, a full disk, loading an old state, or reorganizing the library.

## 2026-10-05: Spec conflicts settled for the MVP

**Decision.** Each conflict the backlog listed between the specs, or between a spec and the code,
is settled, and the specs are updated to match:

- **Auto Resume** is set at App, System, Game and Build scope, like other settings. Save Profiles
  don't override it (`dec 8`, `dec 9` and `Q146` updated).
- **Toolchain detection** is an MVP feature, as `later 1` and `later 5` say (`prod` updated).
- **Quick Play detection** runs on demand, when Technical Info or Add to Library opens, and never
  before the first frame (`dec 14` updated).
- **Built-in layouts** are Game Boy and Playtiles; Minimal, Fullscreen and one-handed presets come
  with the layout editor, and "Classic" names a controller theme (`prod` updated).
- **The second settings layer** is called System (`later 7` updated).
- **Sound**, whether a game follows the silent switch, stays app-wide; other audio options can be
  inheritable when they arrive (`dec 10` updated).
- **With a controller connected**, a touch outside the logo brings the touch controls back until
  the next controller button press, and Settings > Controls has Hide Touch Controls with a
  Controller, on by default, as `Q109` says.
- **Touch Haptics** in Settings > Controls offers Off, Light and Medium, Light by default, and
  stays off while a controller is in use, as `Q91` says.
- **Fast Forward** stays a 2x toggle for the MVP; `Q81`'s presets arrive with the play-feel work.
- **Merging** reviews in the merge sheet, which shows Move or Copy, the target Game, and the Save
  Profiles and artwork that come along before Merge. That is the review `mvp` asks for.
- **Patch formats** are IPS and BPS for v1, as `Q78` says; IPS32, UPS and others come later
  (`dec 5` updated).
- **The default look** stays raw pixels for the MVP. `Q108`'s system-authentic default arrives
  with the curated shader library and the community survey it requires.

The MVP also gets a System settings screen for Game Boy and Game Boy Color, which the code
already reads but nothing could edit.

## 2026-10-04: Design review changes

**Decision.** Quick Play's game menu shows Save State grayed out with "Add to Library to save
states", and an Add to Library item that closes the game and opens that step. The import review
labels its Game Title and Build Name fields and explains Base Build and a wrong header checksum.
A Game's Play button names the Build and save it starts; Build rows no longer show a hash, and
the footer explains the star and BASE. The Build menu is grouped: playing and saves, details,
editing, then Make Separate Game. Library cartridges without artwork take the brand's magenta
for Game Boy Color and print the title on the label. Made With shows names as their projects
spell them (GB Studio, GB BASIC), GBDK-2020 versions without the detector's "2020." prefix,
ranges as "x to y" and open ranges as "x or later", and an audio driver's edition, such as
hUGETracker's SuperDisk, beside its kind rather than as a version. Settings groups its items
under Controls, Display, Sound and Playing. The Playtiles layout draws the Game Boy bezel in the
skin's screen frame around the picture, where the black background showed before; under Fill the
picture fills the frame, so there is none. The Dark
controller theme's bezel is a charcoal lighter than the body, so it reads as its own part on
both layouts. The library's view menu has Show Titles for the grid, on by default, for box art
that carries the name. A Game's default Save Profile is starred, as its preferred Build is, and
Play reads "New Save" when it will create one.

## 2026-10-04: A controller opens the game menu only from a button the player maps

**Decision.** No controller button opens the game menu by default. Controller settings will offer
"Open Menu" as an input any button can be mapped to, as SameBoy does. The Home button is never
taken: Apple's guidelines reserve it for the system. Menu and Options stay START and SELECT, and
tapping the logo opens the menu with a controller connected.

**Why.** Delta, Manic EMU and RetroArch turn off the system's use of Home to open their menus, but
Apple reserves Home for the system and says it may not honor that request. SameBoy leaves Home
alone and makes the menu a mappable input, which keeps START and SELECT on the buttons players
expect.

## 2026-10-04: One game menu, opened from the logo with or without a controller

**Decision.** Gameplay has one game menu, a pop-up menu that opens from the Press Any logo, and
from the game picture when Tap Game for Menu is on, with or without a game controller connected.
It holds Pause or Resume, Fast Forward with a checkmark while on, Save State, Load State with each
saved state, and Close Game in red in its own section. The corner Close and Menu buttons and the
action sheet are gone, and the Game Boy layout's picture sits under the status bar again.

**Why.** The logo stopped responding while a controller was connected, which was the only reason
for the corner buttons, and two menus for one job had drifted apart. Without the corner buttons,
nothing covers the top of the picture, so neither layout gives up room for them; Playtiles would
have had to shrink its picture.

## 2026-10-04: Screenshot review changes

**Decision.** Library artwork is square. A Game's Made With section lists an engine such as GB
Studio or ZGB above the toolchain it runs on, and explains itself behind a question-mark button
rather than in a footer naming the detector's version. The wordmark is heavy italic, as
`docs/NAMING.md` describes, at 26 points in the library and 28 on the controller. A Quick Play
session opens its ROM's Technical Info from the session screen. Full hashes show as four
groups of 16 on two lines, and touch and hold copies them. Lists in the interface use the serial
comma. The bezel's rounder bottom-right corner is sized to pass
the picture's corner at half the border's width; at 3.5 times the border it touched the picture.

## 2026-10-04: Original test ROMs are checked in

**Decision.** `TestROMs/` holds 14 small ROMs and two patches built from source in the same
directory: GBDK-2020, RGBDS, GB Studio, ZGB and hUGEDriver, in GB and GBC, plus a battery-save ROM,
a v1.0/v1.1 revision pair with IPS and BPS patches, and one with a wrong header checksum. The
AGENTS.md rule is about commercial ROMs, and these are original and redistributable under their
own licenses (`TestROMs/README.md`). `Scripts/verify-repo-hygiene.sh` still rejects every other game
image and saves, and requires each tracked ROM to match `TestROMs/manifest.json`. hUGEDriver's own
source is fetched at a pinned commit by its build rather than kept here, per the dependency policy.
The GB Studio ROMs are not byte-reproducible, so a rebuild changes their hashes and the manifest.
Screenshot runs (manual only) pick ROMs by the manifest's `hero` flag and `tags`. Package tests
check toolchain detection, header parsing and both patches against the manifest.

## 2026-10-04: Profile badges are one emoji, and profiles can be deleted

**Decision.** A Save Profile's badge is one emoji, set from its menu and shown before its name
wherever profiles are listed. Setting it leaves the profile's modified time alone, since that time
decides whether an Auto State can still be restored. A profile can be deleted from its menu after a
confirmation naming it, which also deletes its battery save and save states. A Game or Build that
played it plays the Game's default instead. The per-profile RTC offset waits for v1 (`dec 11`):
SameBoy keeps the cartridge clock inside the save, so games with a clock already work.

## 2026-10-04: The library check runs when asked

**Decision.** Settings > Check Library Files compares the managed files with the database. It
rehashes every ROM and patch, marks damaged ones, reports missing files, and removes leftover source
and generated files that nothing uses, such as those an interrupted import left behind. It runs
only when the user asks, since rehashing a large library at launch would slow every start. Saves
and states aren't rehashed: they change as they're played, and their writes are atomic.

## 2026-10-04: Promote and merge review what comes along

**Decision.** Make Separate Game and Merge Into Another Game open a review sheet before they
change anything. Build-scoped data (save states, recipes, toolchain reports, variable maps,
settings) always follows its Build; the sheet chooses the Game-level things:

- **Promote** offers to copy the Game's artwork and its Save Profiles. It selects the artwork
  and the profiles the Build plays or last wrote. Copies get their own files, so the two Games'
  artwork and saves diverge from there. The promoted Build plays the copy of the profile it
  played, or the new Game's default when that profile stayed behind.
- **Merge by Move** takes every Save Profile, since the source Game is deleted. When both Games
  have artwork, the target keeps its own unless Use <source>'s Artwork is on.
- **Merge by Copy** offers to copy the source's artwork and profiles, selecting the artwork when
  the target has none and the profiles the source Builds play or last wrote, plus the source
  Game's default.

A promoted Game records which Game it split from and that Game's title, shown as Split From. The
title stays after the source Game is deleted. Promoting a Game's only Build by Move renames the
Game, so it records no lineage.

A Build's menu also has Mark as Base Build / Unmark as Base Build, for imported Builds. A Game
can have several Base Builds, one per region or revision.

## 2026-10-04: Importing a .sav into an existing profile keeps a copy

**Decision.** A Save Profile's menu has Replace Save from File. When the profile already has a
save, the app asks first. It then copies the current save to "<profile> before import" and writes
the file, as Quick Play promotion does with "<profile> before Quick Play". A blank profile is
filled without asking. The imported save records no writing Build, so launching it never raises
the compatibility warning. Since the profile's save is newer than any Auto State, the next launch
boots from the imported save.

## 2026-10-04: A risky Build switch offers a copy of the save

**Decision.** Each Save Profile records which Build last wrote its battery save. Launching a
Build with a save written by another Build checks the pair first. The save is risky when either
Build was made with GB Studio, when both Builds have detection results naming different tools or
engine versions, or when their cartridge headers declare different save hardware (bytes 0x147
and 0x149). A risky launch asks before playing: Play with a Copy, Start a New Save, Use "<profile>"
Anyway, or Cancel. A copy or a new save becomes that Build's default save, so the
next launch doesn't ask again. A save with no recorded writer, or a check that fails, never
blocks play: detection can add caution but never proves two saves compatible.

A Build can also keep variable maps (Build menu > Attach Variable Map): GB Studio's
`game_globals.i` or `globals.i`, or an RGBDS `.sym` or GBDK `.noi` symbol file. Each map is
stored as an immutable source file on that exact Build and listed in Technical Info. Attaching a
map migrates nothing yet; it's kept for the v1.1 save migration.

## 2026-10-04: Toolchain detection runs on import and shows its findings

**Decision.** The gbtoolsid port runs whenever an image becomes a Build: on import, where Import
Review and Quick Play promotion show its findings, and on patching, where it detects the patched
result. Each Build keeps one report per detector (`build_toolchain_reports`). A Build's Technical
Info detects its image again and keeps the result if it changed, which covers Builds imported
before detection and newer signature data. Each finding carries a categorical confidence from its
own matched signatures: high for two or more, medium for one, low when it's inferred from other
findings. "Not recognized" is a stored result too. Detection never names or groups a Game, and
for saves it only adds caution (see "A risky Build switch offers a copy of the save").

## 2026-10-03: Controller themes

**Decision.** Both controller layouts draw a controller body behind the controls, with the game
picture showing through, in one of two color themes chosen by Settings > Controller Theme
(`controllerTheme`, app-wide, Match System by default):

- **Classic** uses an original Game Boy's colors, sampled from the same public-domain photograph
  the Game Boy layout is measured from: a warm gray body, a gray lens around the picture,
  maroon-magenta A and B, a dark D-pad, gray rubber pills and navy lettering.
- **Dark** is the same design on a near-black body, with the channel behind A and B lighter
  than the body.

Match System picks Classic in Light Mode and Dark in Dark Mode. On the Game Boy layout, as on
the hardware, "A" and "B" are printed below the buttons along their tilt, and "SELECT" and
"START" are printed level below their tilted pills. Both layouts print the app's wordmark
(`docs/NAMING.md`) at the bottom of the body, charcoal on Classic and gray on Dark, with its A in
the A button's magenta. Playtiles keeps its unlabeled buttons and labeled pills. With a game
controller connected the controls hide and the body stays.

## 2026-10-03: Screen scaling

**Decision.** Settings > Screen Scaling (`screenScaling`, Integer by default, overridable per
System, Game or Build) chooses how the game picture fills the layout's screen frame:

- **Integer** draws each Game Boy pixel as the same whole number of device pixels, the largest
  that fits, centered on device pixels, with nearest sampling. A frame too small for one whole
  multiple falls back to Fill.
- **Fill** draws the picture as large as the frame allows at the Game Boy's 10:9 shape. At a
  scale that isn't whole, nearest sampling would make some pixels a device pixel wider than
  others, so each Game Boy pixel is sampled flat and blended only across its edges, over about
  one device pixel.

On the Game Boy layout the frame itself follows the setting: a whole multiple under Integer, or
the full width inside the edge margins under Fill. SameBoy's core only produces the 160x144
frame; scaling is Press Any's.

## 2026-10-03: Sound follows the silent switch by default

**Decision.** Settings > Sound (`soundMode`, app-wide) is Follow Silent Switch by default, so a
phone set to silent plays no game sound. Always On plays through the switch, and Always Off mutes
the game while leaving other apps' audio playing.

## 2026-10-03: Built-in controller layouts

**Decision.** The on-screen controls come in two built-in layouts, chosen by Settings >
Controller Layout (`controllerLayout`, Game Boy by default, overridable per System, Game or Build):

- **Game Boy** follows the original Game Boy's front panel, measured from a photograph of a DMG-01
  and scaled to its specified 90 mm width. The photograph is Evan-Amos's `File:Game-Boy-FL.jpg` on
  Wikimedia Commons, which is in the public domain. Each control was found by its color, and its
  center and size were read from the smallest rectangle around it, with the screen window as the
  reference for position and tilt. The D-pad (22.9 mm) and A and B (10.8 mm) are drawn at the
  hardware's size, about 6.1 points per millimeter, with A and B 16.8 mm apart on a 24.6 degree
  slope and SELECT and START side by side, tilted 18 degrees. The hardware puts SELECT and START a
  little left of center; here they center under the logo. Across the width the controls keep the
  Game Boy's proportions, pulled in so nothing leaves the screen, and A and B close up only if B
  would crowd the D-pad. The game picture sits at the top, sized by Screen Scaling, and the
  controls are centered between its bezel and the logo. Touch areas reach 10 to 12 points past the
  drawn controls without overlapping. SameBoy's iOS layout isn't used: its `iOS/` directory needs
  the author's written permission to ship on the App Store.
- **Playtiles** uses the Playtiles GBC Delta skin's control frames, scaled to the screen, with
  START and SELECT swapped into Game Boy order. Controls are drawn at the skin artwork's sizes,
  where A is larger than B, and respond across both the frame and the artwork. The skin's Menu
  button, Quick Save, Quick Load and tap-the-game Fast Forward are left out. The skin's artwork
  isn't used; the controls are drawn in code.

Each layout also decides where the game picture goes, so the renderer draws into the layout's
screen frame.

Neither layout has a Menu button or gestures by default. As SameBoy opens its menu from its
logo, tapping the wordmark at the bottom opens the game menu, which holds Pause, Fast Forward,
the save states and Close. Its tap area is 44 points tall. Settings > Tap Game for Menu
(`tapGameForMenu`, app-wide, off by default) also lets a tap on the game picture open it, as
SameBoy does. The menu opens only for a touch that lands there, so a thumb sliding across doesn't
open it. The first game played says "Tap Press Any for the menu" once. VoiceOver finds the logo as
the Game Menu button. With a game controller connected the touch controls hide and the logo still
opens the menu.

## 2026-10-03: Merging into a Game that already holds the same image

**Decision.** A Game holds one Build per image. When a merge brings in a Build whose image the
target already holds, Copy skips that Build and Move is refused, naming the Builds involved.

**Why.** The source keeps its Build in a copy, so skipping loses nothing. A move would have to
drop the source Build, and the save states made with it, or fold its states into the target's
Build, which would let states cross Build boundaries.

## 2026-10-03: An Auto State older than its profile's save is not restored

**Decision.** A library launch restores the newest Auto State for its Build and Save Profile only
when the profile's battery save has not been written since that state was taken. Otherwise the
game boots from the battery save and the state stays on disk. Settings > Resume Games
(`autoResumePolicy`, Always by default, overridable per System, Game or Build) decides whether a
restorable state is used, offered, or ignored, and the same policy governs returning to the app
mid-session.

**Why.** A SameBoy state carries the cartridge RAM it was taken with. When two Builds share a
profile, or a `.sav` is imported, restoring an older state would roll the newer save back, and the
next flush would write the rollback over it.

## 2026-10-03: Quick Play is optimized for time to first frame

**Decision.** Quick Play's primary metric is the time from choosing a file to the first emulated
frame on screen. Its launch path does only the work it cannot run without:

1. Read the image once, validate the header from that buffer and write the sandbox copy.
2. Hash that same buffer. Promotion needs the hash, and with CryptoKit it costs milliseconds.
3. Boot the core past the boot logo and present frames. The boot ROM still runs, so the game
   starts in exactly the state hardware leaves it, but it runs unthrottled and undrawn and its
   chime is dropped. CGB sessions swap in SameBoy's `cgb_boot_fast`, which reaches the same
   hand-off without the animation; a session resumed from its autosave doesn't boot at all.

The launch path never loads shaders or post-processing, custom layouts, skins, artwork or other
optional assets. The gameplay screen uses the built-in code-drawn controls and the single plain
Metal pass. Toolchain detection, metadata lookup and anything else optional runs after the first
frame, or not at all for Quick Play.

**Why.** Quick Play is how a developer tests a fresh build, so it is repeated constantly, and any
optional work on its path is paid every time.

**Scope.** Library launches show the boot logo by default. Settings > Skip Boot Logo turns it off
for them (stored as `skipBootAnimation` at the app scope, so a System, Game or Build override can
change it for one launch).

**Cost.** On Linux, reading, validating, copying and hashing an 8 MB image (the GB/GBC maximum)
takes about 55 ms. Skipping the boot logo takes about 105 ms of emulation for DMG and 12 ms for
CGB, against 1.42 s and 3.14 s of animation. The device check in `docs/mvp-verification.md`
measures the real figure.

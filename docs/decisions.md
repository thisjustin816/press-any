# Decisions

Product decisions made after the specs in `docs/specs/`, newest first. Each entry wins over the
specs where they conflict; update the spec it touches in the same change.

## 2026-10-04: Screenshot review changes

**Decision.** Library artwork is square. A Game's Made With section lists an engine such as GB
Studio or ZGB above the toolchain it runs on, and explains itself behind a question-mark button
rather than in a footer naming the detector's version. The wordmark is heavy italic, as
`docs/NAMING.md` describes, at 26 points in the library and 28 on the controller. A Quick Play
session opens its ROM's Technical Info from the session screen. Full hashes show as four
groups of 16 on two lines, and touch and hold copies them. Lists in the interface use the serial
comma. With a game controller connected, the corner Close and Menu buttons no longer stay up:
like the touch controls' view, the game shows alone, and a touch on the screen brings the
buttons back for four seconds. They stay up while VoiceOver runs. The Game Boy layout's picture moves down below them while a controller is
connected, so they never cover it.

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
SameBoy does. The menu opens when the finger lifts within 10 points of where it landed, so a thumb
sliding across doesn't open it. The first game played with the touch controls says "Tap Press Any
for the menu" once. With VoiceOver, double-tapping the controls opens the menu. With a game
controller connected the touch controls hide and the corner Close and Menu buttons come back.

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

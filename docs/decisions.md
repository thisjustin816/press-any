# Decisions

Product decisions made after the specs in `docs/specs/`, newest first. Each entry wins over the
specs where they conflict; update the spec it touches in the same change.

## 2026-10-03: Controller themes

**Decision.** Both controller layouts draw a controller body behind the controls, with the game
picture showing through, in one of two color themes chosen by Settings > Controller Theme
(`controllerTheme`, app-wide, Match System by default):

- **Classic** uses the Game Boy colors SameBoy uses: a light gray body, a dark bezel around the
  picture, magenta A and B, gray D-pad and pills, and navy lettering. The drawing is Press Any's
  own, not SameBoy's artwork.
- **Dark** is the same design on a near-black body.

Match System picks Classic in Light Mode and Dark in Dark Mode. On the Game Boy layout, the
names are printed below the controls in small capitals along the tilt of A and B, as on a Game
Boy, and START and SELECT are slim pills on the same tilt. Both layouts print "Press Any"
at the bottom of the body, in the D-pad's charcoal on Classic and gray on Dark, with its A in
the A button's magenta. Playtiles keeps its unlabeled buttons and labeled pills. With a game controller connected the controls hide and the body stays.

## 2026-10-03: Sound follows the silent switch by default

**Decision.** Settings > Sound (`soundMode`, app-wide) is Follow Silent Switch by default, so a
phone set to silent plays no game sound. Always On plays through the switch, and Always Off mutes
the game while leaving other apps' audio playing.

## 2026-10-03: Built-in controller layouts

**Decision.** The on-screen controls come in two built-in layouts, chosen by Settings >
Controller Layout (`controllerLayout`, Game Boy by default, overridable per System, Game or Build):

- **Game Boy** is SameBoy 1.0.3's portrait layout (`GBVerticalLayout`): the game picture at the
  top at a whole number of device pixels per Game Boy pixel, the D-pad left, A above and right of
  B, and SELECT and START below them. The controls sit centered between the bezel and the logo,
  higher than SameBoy puts them, so the body has no empty band under the picture. SameBoy opens
  its menu from its logo; here Menu is a small round button between SELECT and START, unlike
  them so it isn't taken for a third Game Boy button.
- **Playtiles** uses the Playtiles GBC Delta skin's control frames, scaled to the screen, with
  START and SELECT swapped into Game Boy order. Controls are drawn at the skin artwork's sizes,
  where A is larger than B, and respond across both the frame and the artwork. It keeps the
  skin's Menu control and tap-the-game Fast Forward toggle; saving and loading states go
  through the menu. The skin's artwork isn't used; the controls are drawn in code.

Each layout also decides where the game picture goes, so the renderer draws into the layout's
screen frame.

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

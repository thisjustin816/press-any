# Display presets

Why the Gameplay presets use the filters and colors they do. `docs/product.md` (Picture) says
what each preset sets on each model; `THIRD_PARTY_NOTICES.md` has the sources, pinned revisions
and licenses.

## The three presets

Settings describes them as "As you remember it, polished for today's screens", "As the original
looked and felt" and "Just the game, with no effects added" (`GameplayPresetRow.detail`).

- **Nostalgic** is the standard: the game as people remember it, idealized, on a bright modern
  screen. Handhelds get a faint pixel grid, the frame blending their games' flicker effects expect
  and Button Bounce on. A Game Boy Color gets Soft, SameBoy's Modern Accurate correction made
  softer: the game's colors as a bright backlit screen shows them (see Game Boy Color colors).
  The Game Boy Advance gets the backlit AGS-101 SP's
  colors, the screen most players remember as the good one. The television models get sharp
  scanlines on a curved screen with small rounded corners, the look most players picture for a
  console on a TV, without the mask, glow and vignette that Accurate draws: Curved Scanlines on
  a Super Game Boy and Slightly Curved Scanlines on a Game Boy Player.
- **Accurate** is the original hardware late in its life: the Game Boy's and Pocket's screens as
  BGB measured them (below), with the original Game Boy's slow response (LCD Ghosting) or the
  faster Pocket's (Blend), Authentic GBC's measured subpixels with SameBoy's Reduce Contrast
  correction, SameBoy's color LCD with the published Game Boy Advance color profile, and two
  television models.
- **Clean** draws the game's pixels with nothing added.

Palettes stay outside the presets. A Game Boy palette is a taste most emulators let players
choose, and a preset that rewrote it would undo that choice whenever the player switched presets.
The Game Boy Light and the backlit SP run as a Pocket and a Game Boy Advance in SameBoy, so
they're looks, not models: the Light is the Teal (Light) palette, and the SP is the Backlit GBA
SP LCD filter.

## Sources

| Filter | Source | License | Why |
|---|---|---|---|
| Pixel Grid, RGB Subpixels | Press Any's own code, modelled on libretro's `lcd3x` by Gigaherz | Apache-2.0 (own); `lcd3x` is public domain | The grid family is the common "clean handheld" look; keeping v1.0's code keeps v1.0's LCD 1× and 3× unchanged |
| Monochrome LCD | Press Any's own shader, with the screen colors measured on [BGB's reality page](https://bgb.bircd.org/reality/) | Apache-2.0 (own); the colors are cited measurements | Both screens measured from color-corrected photos, by the method below |
| Game Boy Advance LCD | SameBoy `Shaders/LCD.fsh` | Expat | [SameBoy's scaling page](https://sameboy.github.io/scaling/) calls it "Ideal for Game Boy Color and Game Boy Advance" |
| Game Boy Color LCD | Authentic GBC 2.2 by fishku, subpixel geometry only | CC0 | Measured from a photo of a GBC's subpixels; [Chasm's developer](https://store.steampowered.com/oldnews/?appgroupname=Chasm&appids=312200&enddate=1775026800&feed=steam_community_announcements) ported it after comparing alternatives |
| Game Boy Advance and SP101 colors | `gba-color.slang`, `sp101-color.slang` by Pokefan531 and hunterk | Public domain | The long-running [color thread](https://forums.libretro.com/t/real-gba-and-ds-phat-colors/1540/220) compares them with hardware; they ship in RetroArch's shader collection |
| Scanlines, Curved Scanlines, Slightly Curved Scanlines, CRT 240p, CRT 480p | Press Any's own CRT, modelled on CRT-Lottes by Timothy Lottes | Apache-2.0 (own); CRT-Lottes is public domain | [libretro's CRT page](https://docs.libretro.com/shader/crt/) says CRT-Lottes "looks good at default settings, making it a good general-purpose choice" |

Authentic GBC's `coverage.inc`, which its shader includes, has no license statement, so Press
Any computes pixel coverage with its own math (an exact box-filtered rectangle).

Not used, because their headers declare the GPL: libretro's `lcd1x`, `zfast_lcd`, `crt-geom`,
`crt-easymode`, `crt-pi`, `crt-aperture` and `crt-guest-advanced`. Writing a general technique
from its math (a barrel warp, a Gaussian beam, a mask pattern) is fine; copying or porting their
code is not.

## Game Boy and Pocket screens

BGB's reality page photographs a Game Boy's and a Game Boy Pocket's screens under
color-accurate light, corrects the photos with a color checker, defocuses them and averages each
shade, so each color includes the gaps between pixels. Read from its swatches, lightest shade
first, then the screen with the LCD off:

| Screen | Shade 0 | Shade 1 | Shade 2 | Shade 3 | LCD off |
|---|---|---|---|---|---|
| Game Boy (DMG), measured | #759833 | #588f51 | #3b7560 | #2e615a | #948a04 |
| Game Boy Pocket (MGB), measured | #adbf92 | #96a67c | #727e64 | #5a635c | #c2cfa8 |
| Game Boy, Accurate | #89b13d | #64a25c | #3e7a64 | #2d5e58 | #aa9f05 |
| Game Boy Pocket, Accurate | #c9deaa | #a5b789 | #717c63 | #515953 | #e9f9cb |

The measured colors are what a reflective screen sends back in a lit room, which on a phone's
emissive screen reads as dim and flat (2.7:1 on the Game Boy). Accurate keeps their hues and
brightens them the same way on both models, in linear light: every color is multiplied by 1.4,
then the contrast of brightness alone is raised by a power of 1.4, keeping each color's
chromaticity: `out = 1.4 * c * (Y(c) / Y(shade 0)) ^ 0.4`, with Y the Rec. 709 luminance. That
gives 4.0:1 on the Game Boy and 7.1:1 on the Pocket, and one exposure for both keeps the Pocket
about 1.8 times as bright as the original, as measured. The owner chose this over the measured
colors as they are (2.7:1) and a stronger contrast power of 1.6 (4.9:1).
`EmulatorDomain/MonochromeScreen.swift` computes the table from the measurements, and
`MonochromeScreenTests` checks it.

**Pixel gaps.** BGB describes the gaps between pixels showing the unlit LCD, lighter and
yellower than a dark pixel, with the pixel squares slightly bluer than their averaged shade. The
filter draws each pixel as a square and the gaps, a sixth of a pixel wide and centered on the
pixel edges, in the screen's LCD-off color at a strength of 0.5 on the Game Boy and 0.3 on the
Pocket, whose pixels sit closer together. The square is darkened by the light its gaps add, so
each pixel's average stays the measured shade, as the defocused photos measured it. Around the
Game Boy's two darkest shades the yellow gap would add more red than the shade has, so there the
gap's strength drops to what the shade leaves room for (about 0.21 around the darkest and 0.39
around the next) and the average still matches. Each screen pixel takes the share of gap its
footprint covers, exactly, so the gaps don't alias in either scaling path and fade into the
pixels' average when the picture is too small to show them.

**Palettes.** The filter receives SameBoy's frame in the palette's colors and maps them with a
tone curve per channel through five knots, computed on the CPU (`MonochromeScreen`) and applied
in the shader. With the hardware's own palette, Green (DMG) on a Game Boy or Olive (Pocket) on
a Pocket, the knots take each of the palette's four shades and its LCD-off color to the table
above, so Accurate shows exactly those colors, and a blend of two neighboring shades from frame
blending lands on the blend of theirs. Any other palette is the player's choice of colors, so it
gets one curve for all three channels: the palette's lightest shade goes to the screen's lightest
brightness, its darkest to the screen's darkest, and the shades between where the hardware's own
palette puts them, and its LCD-off color, through the same curve, fills the gaps. Doing this in
the shader rather than giving the core a different palette keeps the palette setting, the core,
save states and captures untouched by the filter, and keeps palettes outside the presets in
storage and in the Custom check. Every model but the Pocket draws the original Game Boy's
screen: a Game Boy Color, Game Boy Advance, Super Game Boy or Game Boy Player given Monochrome
LCD under Customize shows its game's colors with the Game Boy's brightness and contrast, white
as the lightest and black as the darkest, and light gaps.

## Game Boy Color colors

BGB's reality page measures a Game Boy Color in light at white #d9e1c6 and black #17282d,
38:1. SameBoy's Reduce Contrast correction gives white #dbdfd7 and black #282420, 40:1, close
to it, so Accurate uses it with Authentic GBC's subpixels.

Nostalgic is the screen as people remember it, idealized: a bright backlit screen, which the
original Game Boy Color never had. SameBoy's Modern Accurate shows the game's colors as a
color-accurate modern screen would, stronger than that memory. Soft starts from Modern Accurate and works on each color in Björn Ottosson's OKLab color space
(https://bottosson.github.io/posts/oklab/), where lightness and color are separate:

- chroma (OKLab's a and b) is multiplied by 0.80;
- lightness L is raised to the power 0.92, which keeps black (0) and white (1) and lifts the
  middle tones a little;
- the result goes back to sRGB, clamped to the screen's range.

The amounts were chosen by eye, from rendered comparisons of a Game Boy Color game's first room
with chroma at 80%, 70% and 60% and Modern Accurate and Reduce Contrast beside them; 80% was the
one approved. True black stays black, which Reduce Contrast lifts.

The bridge does this in `SameBoyBridge.c`. SameBoy draws the game's colors uncorrected, and each
frame goes through a table of all 32,768 Game Boy Color colors, built when Soft is chosen from
Modern Accurate and the steps above (`SBSoftenColor`). The frame the core hands over already has Soft's colors, so
every picture taken from it matches gameplay. On a Game Boy Advance or Game Boy Player the table
starts from that screen's Modern Accurate, or a Game Boy Color's with As on a Game Boy Color.
Game Boy palettes don't change. A Game Boy Color boot palette chosen on a Game Boy is softened as
the Game Boy Color would show it, and a Super Game Boy shows Modern Accurate.

## Televisions

The CRT treatments are one shader with a `CRTParameters` value per television
(`App/Gameplay/DisplayFilterRendering.swift`). Tests assert the curvature orderings below on the
rendered picture, that CRT 480p has a finer mask than CRT 240p, and that each treatment keeps a
one-pixel outline dark and an edge under two thirds of a source pixel wide.

A phone shows a Game Boy pixel about 7 screen pixels wide, much larger than a CRT shader's
usual target, so softness that reads as analog on a monitor reads as blur here. The treatments
therefore reconstruct along each line more sharply than CRT-Lottes's default (hardness -3, which
leaves about a tenth of a neighbor in each pixel's center), keep glow faint so it doesn't fill in
dark outlines, and lock the phosphor mask to source pixels: each pixel carries the same whole
triads, and each screen pixel takes the share of each stripe it covers, so the mask never beats
against the picture and fades to its average when it's finer than the screen.

- **CRT 240p** (Super Game Boy, Accurate): a 1990s consumer set showing a SNES's 240-line
  picture: a standard-radius spherical shadow-mask tube (the research below), one beam per line
  with CRT-Lottes's default scanline hardness, which leaves dark gaps; a slot mask of two triads
  per SNES pixel, roughly what a 20-inch set's dot pitch gives; horizontal reconstruction (-5)
  that stays a little soft, as a composite picture did; a faint glow and a vignette. Its
  sharpness is the owner's call: `LCDFilterTests.testCRT240pSharpnessComparisonCapture` attaches
  the shipped tuning beside a crisper one (-6, glow 0.04) on the same picture.
- **CRT 480p** (Game Boy Player, Accurate): a 2000s set showing the player's 480-line output. The
  Game Boy Player's start-up disc outputs 480i on every cable and 480p over component or digital
  ([Nintendo World Report](http://www.nintendoworldreport.com/guide/2147/the-ultimate-game-boy-player-faq)
  calls it progressive scan compatible), and it draws each Game Boy line on two TV lines, with a
  Sharpness setting that softens the picture. So the treatment draws two beams per source line
  that nearly close up, sharper reconstruction (-6) for a component picture, an aperture grille
  of two and a half triads per pixel, a fainter glow and a light vignette, on the flattest tube
  still sold curved (below), with larger rounded corners.
- Interlacing isn't drawn. A CRT shows 480i's two fields one after the other, so a viewer never
  sees them combed together, and with each line drawn twice both fields carry the same picture
  until it moves. Drawing the previous frame on alternate lines, as a progressive screen weaving
  fields would, combs moving things in a way a CRT never did.
- **Curved Scanlines** (Super Game Boy, Nostalgic) and **Slightly Curved Scanlines** (Game Boy
  Player, Nostalgic): the television as players remember it, cleaned up. The crispest
  reconstruction of the treatments (-10 across, -8 along) keeps pixel art as sharp as the Pixel
  Grid, with small rounded corners and no mask, glow or vignette. Their warps are three quarters
  of CRT 240p's and two thirds of CRT 480p's, so each curves less than the same hardware's
  Accurate set and the Super Game Boy's more than the Game Boy Player's.
- **Scanlines**: the same crisp beam on a flat picture, with no warp and square corners, for
  players who want scanlines without a curve. The stored value `scanlines` has always meant this.

These are approximations of an RGB picture, not composite video or a named television.

### Curvature

The warp stands for the bulge of a television's glass. Sources, then the geometry, then the
numbers; what is sourced and what is inferred is marked.

**Tubes of the time (sourced).** Rectangular color tubes came in two faceplate contours,
spherical and cylindrical; a 1989 RCA patent calls the usual contour a "standard radius, 1R,
spherical faceplate" and gives, for a tube with a 635 mm screen diagonal, a standard radius of
about 1034 mm (1.63 diagonals) with a 52 mm sagittal height at the corners, and the industry's
flatter contours as 1.5R (about 1500 mm, 39 mm) and 2R (about 2000 mm, 26 mm), introduced "by
increasing the radius of curvature of the panels by a factor of 1.5 to 2" for better off-axis
viewing; a truly flat face was rejected then for the glass it needed
([US 4,887,001](https://patents.google.com/patent/US4887001A/en)). Sony's Trinitron tubes were
cylindrical, curved across and nearly flat down, because the aperture grille's vertical wires
have to be straight ([Sam's CRT FAQ](https://www.repairfaq.org/sam/crtfaq.htm),
[Wikipedia, Aperture grille](https://en.wikipedia.org/wiki/Aperture_grille)). Wikipedia's CRT
article records, citing an LG.Philips Displays monitor-tube catalogue, that screen radii grew
over time "from 30 to 68 inches" before faces became flat, and that flat-faced tubes thicken
toward the edges and "may not be completely flat on the inside"
([Wikipedia, Cathode-ray tube](https://en.wikipedia.org/wiki/Cathode-ray_tube)). Flat
faces arrived with Sony's 1996 Super Flat Trinitron and the FD Trinitron WEGA sets sold from
1997 in Japan and 1998 worldwide, applied to the whole 13 to 40 inch range; WEGA was the
top-selling television model in the United States in 2001 and had sold over 40 million sets by
2003, and production ended in the United States in 2006
([Wikipedia, FD Trinitron/WEGA](https://en.wikipedia.org/wiki/FD_Trinitron/WEGA)). Toshiba
introduced its first flat FST Pure set in 1999 and had sixteen flat-screen sets in seven sizes
by 2001 ([Widescreen Review, 2001](https://widescreenreview.com/news_detail.php?id=5748)), and
Panasonic announced its Tau series, "perfectly-flat screen television products", in 1999
([Widescreen Review, 1999](https://www.widescreenreview.com/news_detail.php?id=184)). CRTs were
still about four fifths of the televisions shipped worldwide in 2005
([The Register](https://www.theregister.com/on-prem/2006/03/14/world-lcd-tv-sales-overtake-crt-revenues/),
[EDN](https://www.edn.com/crt-still-rules-tv-market-isuppli-says/)). A hobbyist survey of
consumer sets puts the flatter "flat-curve" tubes in the late 1990s, the truly flat ones late
in the CRT era, and the traditional "bubble" curve before both
([CRT Database](https://crtdatabase.com/articles/flat-or-curved-crts-which-is-better)). Flat
faces didn't look flat either: Samsung SDI's tube patents say a flat-faced picture "appears
depressed to the user in the center portion", more so on large screens, and that the flat
outside, curved inside tubes that preceded theirs made pictures "appear bulged outward"
([US 6,774,553](https://patents.google.com/patent/US6774553B2/en)).

**Which set each treatment draws (inferred from the above).** A Super Game Boy (1994) or Super
Game Boy 2 (1998) played on the sets of the mid to late 1990s: spherical shadow-mask tubes of
1R to 2R and cylindrical Trinitrons, with flat faces only just arriving and premium. CRT 240p
draws the standard 1R spherical contour, the most curved of them, so it has the strongest curve
of the treatments as the product asks; a 1.5R flat-square set would give two thirds of its warp.
A cylindrical set would curve across only (warp x of 0), which the shader can draw, but most
sets were shadow-mask tubes, so the spherical contour stands for the era. A Game Boy Player
(2003 to the GameCube's end in 2007) played on sets where flat faces led sales but curved sets
were still everywhere: budget sets and the sets bought in the 1990s. A flat face would give no
curve at all, or the slight concave look above, and the product wants the player's set to read
as a CRT with some curve, so CRT 480p draws the flattest spherical contour the patent
describes, 2R: half of CRT 240p's warp. Both treatments draw the game as if it filled the
screen; on real hardware the Game Boy's window sat in the middle of a 4:3 raster, where the face
is flattest, so this is the look of the television, not of the window.

**From a tube to the shader's warp (own geometry).** The shader maps a screen position to the
source as `warped = centered * (1 + (y², x²) * warp)`, so the raster's top edge, a straight
line on the tube, sits at `1 / (1 + warp.y * x²)` of the half-height: the corners pull in by
about `warp.y`. On a convex face a straight raster edge recedes from the viewer toward the
corners by the face's sagitta, and from a viewing distance d that recession pulls the corners
in by about sagitta / d, which is what the warp draws. For a spherical face of radius R, a
half-width w and a half-height h, the sagitta of the corner relative to the edge's middle is
w² / 2R along the top edge and h² / 2R along a side, so `warp = (h² / 2Rd, w² / 2Rd)`; a
cylindrical face gives `(0, w² / 2Rd)`. `CRTParameters.sphericalWarp` computes this for a 4:3
face (w = 2/3 H, h = H/2, diagonal 5/3 H) from the radius in diagonals and the distance in
screen heights.

**The viewing distance (a choice).** The one unsourced number. The treatments use two screen
heights, about 60 cm from a 20-inch set: the close look at which the bulge of the glass is
plain. From ITU-R's preferred distance for a set that size, 7 heights
([ITU-R BT.500 as tabulated by screenfont.ca](https://screenfont.ca/tech/PVD.php)), the same
tubes bow under a third as much and the curve would be lost at a phone's size. Two heights also
puts the 1R set at CRT-Lottes's default warp (0.031, 0.042), the look libretro's CRT page calls
a good general-purpose choice.

| Tube | Radius | Warp at 2 heights (x, y) | Warp at 7 heights | Treatment |
|---|---|---|---|---|
| 1R spherical | 1.63 diagonals | 0.023, 0.041 | 0.007, 0.012 | CRT 240p |
| 1.5R spherical | 2.44 diagonals | 0.015, 0.027 | 0.004, 0.008 | |
| 2R spherical | 3.26 diagonals | 0.012, 0.020 | 0.003, 0.006 | CRT 480p |
| Flat face | none | 0, 0 | 0, 0 | not used: no curve, or a slight concave look |

Nostalgic's scanlines aren't research-bound: Curved Scanlines take three quarters of CRT 240p's
warp (0.017, 0.031) and Slightly Curved Scanlines two thirds of CRT 480p's (0.008, 0.014).

**The measured bow.** At a phone's size (a 160 by 144 picture drawn 1120 by 1008), the top
edge an eighth of the width in from a side drops below its middle by about 270 times the warp's
y: CRT 240p 10.9 px, Curved Scanlines 8.2 px, CRT 480p 5.3 px, Slightly Curved Scanlines 3.4
px, Scanlines 0; the sides bow by about 290 times the warp's x, from 6.7 px to 2.1 px; and the
corners, before their rounding, drop by about 500 times the warp's y, from 20 px to 7 px.
`LCDFilterTests.testCRTCurvatureOrderingsHoldOnTheRenderedPicture`
measures these edges to a fraction of a pixel with the beam evened out, then measures a line
drawn near the top with each filter as it ships, and asserts the orderings: Super Game Boy over
Game Boy Player in Accurate and in Nostalgic, each Nostalgic under its hardware's Accurate, all
four visible, Scanlines flat.

## Cost

The filters that imitate a physical screen sample sRGB views of the frames, so the GPU turns
each sample into linear light and the shader encodes the result once (three `pow` calls per
pixel). Per output pixel, without frame blending:

| Filter | Texture reads | `pow` calls |
|---|---|---|
| Off, Pixel Grid, RGB Subpixels | 1 | 0 |
| Backlit GBA SP LCD | 1 | 3 |
| Game Boy Color LCD | 4 | 3 |
| Game Boy Advance LCD | 3 to 6 | 3 |
| Monochrome LCD | 1 | 3 |
| Scanlines, Curved Scanlines, Slightly Curved Scanlines | 4 | 3 |
| CRT 240p, CRT 480p | 5 (4 in Low Power Mode or a serious thermal state) | 3 |

Frame blending multiplies the reads by the number of frames mixed. CRT glow reads a mipmap the
renderer builds for each new frame only while glow is on; Low Power Mode and a serious or
critical thermal state turn both off. Energy use on a phone is a device check in
`docs/mvp-verification.md`.

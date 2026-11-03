# Display presets

Why the Gameplay presets use the filters and colors they do. `docs/product.md` (Picture) says
what each preset sets on each model; `THIRD_PARTY_NOTICES.md` has the sources, pinned revisions
and licenses.

## The three presets

- **Nostalgic** is the standard: the screen as players remember it, cleaned up. Handhelds get a
  faint pixel grid with vivid colors, the frame blending their games' flicker effects expect and
  Button Bounce on. The Game Boy Advance gets the backlit AGS-101 SP's colors, the screen
  most players remember as the good one. The television models get flat, sharp scanlines, the
  look most players picture for a console on a TV.
- **Accurate** imitates the hardware: SameBoy's monochrome LCD with the original Game Boy's slow
  response (LCD Ghosting) or the faster Pocket's (Blend), Authentic GBC's measured subpixels with
  SameBoy's Low Contrast correction, SameBoy's color LCD with the published Game Boy Advance
  color profile, and two television models.
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
| Monochrome LCD, Game Boy Advance LCD | SameBoy `Shaders/MonoLCD.fsh`, `Shaders/LCD.fsh` | Expat | [SameBoy's scaling page](https://sameboy.github.io/scaling/) calls them "Ideal for the original Game Boy" and "Ideal for Game Boy Color and Game Boy Advance" |
| Game Boy Color LCD | Authentic GBC 2.2 by fishku, subpixel geometry only | CC0 | Measured from a photo of a GBC's subpixels; [Chasm's developer](https://store.steampowered.com/oldnews/?appgroupname=Chasm&appids=312200&enddate=1775026800&feed=steam_community_announcements) ported it after comparing alternatives |
| Game Boy Advance and SP101 colors | `gba-color.slang`, `sp101-color.slang` by Pokefan531 and hunterk | Public domain | The long-running [color thread](https://forums.libretro.com/t/real-gba-and-ds-phat-colors/1540/220) compares them with hardware; they ship in RetroArch's shader collection |
| Scanlines, CRT 240p, CRT 480p | Press Any's own CRT, modelled on CRT-Lottes by Timothy Lottes | Apache-2.0 (own); CRT-Lottes is public domain | [libretro's CRT page](https://docs.libretro.com/shader/crt/) says CRT-Lottes "looks good at default settings, making it a good general-purpose choice" |

Authentic GBC's `coverage.inc`, which its shader includes, has no license statement, so Press
Any computes pixel coverage with its own math (an exact box-filtered rectangle).

Not used, because their headers declare the GPL: libretro's `lcd1x`, `zfast_lcd`, `crt-geom`,
`crt-easymode`, `crt-pi`, `crt-aperture` and `crt-guest-advanced`. Writing a general technique
from its math (a barrel warp, a Gaussian beam, a mask pattern) is fine; copying or porting their
code is not.

## Televisions

The CRT treatments are one shader with a `CRTParameters` value per television
(`App/Gameplay/DisplayFilterRendering.swift`), and tests assert that both curve the
picture, CRT 240p more, and that CRT 480p has a finer mask.

- **CRT 240p** (Super Game Boy, Accurate): a 1990s consumer set showing a SNES's 240-line
  picture. Tubes of that era bowed visibly, so the barrel warp is about three times CRT-Lottes's default; one beam per line with CRT-Lottes's default hardness leaves dark gaps; the
  slot mask has a 6-pixel triad; horizontal reconstruction is soft; glow and a vignette follow.
- **CRT 480p** (Game Boy Player, Accurate): the Game Boy Player was sold until the GameCube's end
  (2007). By then many sets were flat-faced tubes: Sony sold flat FD Trinitron WEGA sets from the late 1990s
  ([Wikipedia](https://en.wikipedia.org/wiki/FD_Trinitron/WEGA)), and CRTs were still most TVs
  sold in 2005 ([ChannelWeb](https://www.channelweb.co.uk/analysis/1890232/crt-tv-sales-decline)).
  The Game Boy Player's start-up disc outputs 480i on every cable and 480p over component or
  digital ([Nintendo World Report](http://www.nintendoworldreport.com/guide/2147/the-ultimate-game-boy-player-faq)
  calls it progressive scan compatible), and it draws each Game Boy line on two TV lines, with a
  Sharpness setting that softens the picture. So the treatment is gently curved (a warp about CRT-Lottes's default) with rounded corners, two softer beams per source line, an
  aperture grille with a 3-pixel triad and lighter glow. Many sets were flatter and many were more curved.
- Interlacing isn't drawn. A CRT shows 480i's two fields one after the other, so a viewer never
  sees them combed together, and with each line drawn twice both fields carry the same picture
  until it moves. Drawing the previous frame on alternate lines, as a progressive screen weaving
  fields would, combs moving things in a way a CRT never did.
- **Scanlines** (both television models, Nostalgic): sharp lines with no mask or glow.

These are approximations of an RGB picture, not composite video or a named television.

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
| Monochrome LCD | 9 | 3 |
| Scanlines | 4 | 3 |
| CRT 240p, CRT 480p | 5 (4 in Low Power Mode or a serious thermal state) | 3 |

Frame blending multiplies the reads by the number of frames mixed. CRT glow reads a mipmap the
renderer builds for each new frame only while glow is on; Low Power Mode and a serious or
critical thermal state turn both off. Energy use on a phone is a device check in
`docs/mvp-verification.md`.

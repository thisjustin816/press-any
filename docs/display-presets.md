# Device display presets

Each model has one Accurate configuration. Customize can use any of the display treatments on
any model. The configurations use published shader defaults and the existing settings resolver.

| Model | Display implementation | Color handling |
|---|---|---|
| Game Boy | SameBoy Monochrome LCD | SameBoy DMG palette |
| Game Boy Pocket | SameBoy Monochrome LCD | SameBoy Pocket palette |
| Game Boy Light | SameBoy Monochrome LCD | SameBoy Light palette, lit-screen reference |
| Game Boy Color | Authentic GBC 2.2, single pass | SameBoy Low Contrast |
| Game Boy Advance | SameBoy LCD | Pokefan531/hunterk GBA sRGB profile |
| GBA SP AGS-101 | SameBoy LCD | Pokefan531/hunterk SP101 sRGB profile |
| Super Game Boy / SGB2 | CRT-Lottes, progressive raster | SameBoy SGB color curve |
| Game Boy Player | CRT-Lottes, woven current/previous fields | Original colors |

Handheld configurations use frame blending and button bounce. TV configurations disable both.
The GBA profiles process original core colors once, before LCD reconstruction. These models run
GB/GBC cartridges; native GBA emulation is separate work.

## Selection evidence

Established use, community preference and hardware accuracy are different claims. There is no
measured community consensus naming a single most accurate shader for all of these displays.

- **Monochrome LCD:** [SameBoy's filter comparison](https://sameboy.github.io/scaling/)
  recommends this filter for the original Game Boy and its color LCD filter for GBC/GBA.
  [Academic Quest's developer](https://two-headedboy.itch.io/academic-quest-1) also recommends
  Monochrome LCD with accurate frame blending. This establishes shipped use and an independent
  recommendation, but does not establish a majority preference or separate measured Pocket
  and Light panel models. Those devices share the filter with their distinct palettes.
- **Authentic GBC:** fishku's shader models the notched subpixels from a photograph of a real
  GBC. [Chasm's developer](https://store.steampowered.com/oldnews/?appgroupname=Chasm&appids=312200&enddate=1775026800&feed=steam_community_announcements)
  selected and ported it after comparing alternatives (July 8, 2025).
  [Community hardware comparisons](https://www.reddit.com/r/SBCGaming/comments/1q2vtpo/)
  report good accuracy, while also discussing brightness and comfort changes. Its upstream
  brightness 0.6, blur 0.3 and host subpixel offset Off are retained here.
- **GBA/SP101 color:** the [author's long-running development thread](https://forums.libretro.com/t/real-gba-and-ds-phat-colors/1540/220)
  documents hardware comparisons and separate backlit SP profiles. These profiles ship in
  Libretro's shader collection. [Later colorimetry discussion](https://forums.libretro.com/t/real-gba-and-ds-phat-colors/1540/290)
  identifies ongoing work on measurement and white-point handling. The selected profiles are
  established approximations, not a claim that the research has settled every color question.
  SameBoy's published color LCD filter supplies the grid; the complete combination is this
  app's curated configuration.
- **CRT-Lottes:** [Libretro's documentation](https://docs.libretro.com/shader/crt/)
  describes its good default appearance and RGB arcade-monitor target.
  [KNULLI's Curvature shader set](https://knulli.org/configure/customization/shaders/)
  uses its Fast relative, and [Clownacy's Dolphin port](https://clownacy.wordpress.com/2023/06/30/porting-crt-shaders-from-retroarch-to-dolphin/)
  documents choosing that relative after trying CRT-Pi. This supports adoption of the family,
  not a preference for every version. Press Any uses the original Lottes beam, reconstruction,
  mask and bloom defaults, with raster-edge feathering, vignette and a GBP field adapter.
  The reference is an RGB CRT, without composite/RF artifacts. It cannot reproduce every TV or
  connection. The GBP field adapter is app code, not an upstream Lottes feature.

SameBoy calls its original-display color simulation Low Contrast / Harsh Reality. Its separate
Modern Accurate mode corrects colors for a modern display; the preset uses Low Contrast for GBC.
SGB1 and SGB2 share their display configuration but retain distinct boot and clock behavior.
Only the backlit AGS-101 SP is offered.

## Reuse and verification

Exact sources, pinned revisions, licenses and author credits are in
[THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) and Settings > Acknowledgements. SameBoy's
common shaders use Expat, Authentic GBC uses CC0, and the selected Lottes and color-profile code
is public domain. LCD3x is also public domain, but its generic grid is superseded here; its
persisted value remains an alias. Libretro's LCD1x is GPL-2.0-or-later. Its implementation is not
used. SameBoy's iOS frontend is also excluded.

Automated Metal tests cover fractional and integer viewports, field alternation, bloom and
synthetic reference captures. Passing them establishes rendering behavior, not a physical
screen match. Stock-hardware comparisons, viewing conditions and iPhone performance remain
manual checks in [mvp-verification.md](mvp-verification.md).

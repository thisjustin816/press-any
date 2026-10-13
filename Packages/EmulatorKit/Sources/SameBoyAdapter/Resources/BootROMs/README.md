# SameBoy boot ROM resources

Press Any uses SameBoy's open boot ROMs, built with RGBDS from the `BootROMs/` source in the SameBoy submodule.

Generate them with:

```sh
make bootroms
```

This creates and copies:

- `dmg_boot.bin`, `mgb_boot.bin`, `sgb_boot.bin` and `sgb2_boot.bin`, for Game Boy, Game Boy Pocket,
  Super Game Boy and Super Game Boy 2
- `cgb_boot.bin`
- `cgb_boot_fast.bin`, the same CGB boot without its animation, which skips the logo on Game Boy Color
- `agb_boot.bin`, for Game Boy Advance and the Game Boy Player

The generated binaries are build products and are intentionally not committed. Their source is under SameBoy's Expat license.

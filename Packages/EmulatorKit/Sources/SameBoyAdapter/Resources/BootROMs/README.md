# SameBoy boot ROM resources

Press Any uses SameBoy's open boot ROMs, built with RGBDS from the `BootROMs/` source in the SameBoy submodule.

Generate them with:

```sh
make bootroms
```

This creates and copies:

- `dmg_boot.bin`
- `cgb_boot.bin`
- `cgb_boot_fast.bin`, the same CGB boot without its animation, which Quick Play uses to skip the logo

The generated binaries are build products and are intentionally not committed. Their source is under SameBoy's Expat license.

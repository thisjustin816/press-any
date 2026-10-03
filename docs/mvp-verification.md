# MVP device checklist

The MVP is done when these checks pass on a physical iPhone. Broader v1 work waits for them.
Do not commit commercial ROMs, saves, or other copyrighted test content.

## On a physical iPhone

Automated coverage runs in CI (`docs/ci.md`). These checks need a real device.

Verify with a user-supplied legal ROM:

- [ ] Generate/open the iOS project from a clean checkout.
- [ ] Launch a GB game and a GBC game through SameBoy with correct colors, orientation, native speed and audio.
- [ ] Touch input works with acceptable latency.
- [ ] Bluetooth controller works and disconnect behavior is safe.
- [ ] Cartridge rumble routes correctly to controller/phone where supported.
- [ ] Backgrounding pauses emulation, flushes battery save, and writes lifecycle autosave.
- [ ] Foreground autoresume honors Always / Ask / Never behavior.
- [ ] Add a modified ROM as a second Build; Game identity remains stable.
- [ ] Share a compatible Save Profile between Builds, then fork it and confirm divergence.
- [ ] State created on Build A is never loadable on Build B.
- [ ] Create an IPS/BPS-derived Build and launch it.
- [ ] Remove its generated-ROM cache, relaunch, and confirm deterministic rebuild.
- [ ] Quick Play a new test build using a copy of Main; mutate the temporary save; Main remains unchanged.
- [ ] Promote the Quick Play session and choose whether its save becomes a new/default profile.
- [ ] Quick Play an 8 MB image on device and record the time from choosing the file to the first frame; it opens on the game, not the boot logo, and nothing optional (shaders, skins, custom layouts, detection) loads before it. Then play for a minute and confirm normal speed and audio.
- [ ] A library game shows the boot logo by default; with Settings > Skip Boot Logo on, it opens on the game.
- [ ] Move a Build to its own Game and merge it back; Build identity and data remain intact.

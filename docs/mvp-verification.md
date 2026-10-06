# MVP device regression checklist

The owner accepted the working MVP on 2026-10-06. Keep these physical-iPhone checks as the
regression record; they no longer block v1 work.
Do not commit commercial ROMs, saves, or other copyrighted test content.

## On a physical iPhone

Automated coverage runs in CI (`docs/ci.md`). These checks need a real device.

The `Shared ROM and patch UI flows` CI job automates the share-sheet, queue and return-to-details
scenarios on a simulator. Keep these device checks pending until they pass on an iPhone.

Verify with a user-supplied legal ROM:

- [ ] Generate/open the iOS project from a clean checkout.
- [ ] Launch a GB game and a GBC game through SameBoy with correct colors, orientation, native speed and audio.
- [ ] Touch input works with acceptable latency.
- [ ] With Playtiles selected and the physical overlay aligned, press left/right/up/down slightly off-center: each stays straight. Deliberate diagonals and sliding back to straight directions still work.
- [ ] From Files and a browser's downloaded-file share sheet, open `.gb`, `.gbc`, `.ips` and `.bps` in the app (use More if needed). ROMs offer Quick Play or Import Review; patches require a Game and base Build. Cancelling leaves the sender's file and library unchanged. While gameplay is open, the shared file waits until the game and its session sheet close.
- [ ] Bluetooth controller works and disconnect behavior is safe.
- [ ] Cartridge rumble routes correctly to controller/phone where supported.
- [ ] Backgrounding pauses emulation, flushes battery save, and writes lifecycle autosave.
- [ ] Foreground autoresume honors Always / Ask / Never behavior.
- [ ] Add a modified ROM as a second Build; Game identity remains stable.
- [ ] Import a ROM with metadata tags, such as `Example (Europe) (En,Fr) (Rev A) [v1.10].gb`. Correct or clear Build Details in review. Reopen the app and confirm Technical Info shows the chosen values.
- [ ] Quick Play that ROM, then Add to Library. Build Details uses the picked filename's metadata.
- [ ] Share a compatible Save Profile between Builds, then fork it and confirm divergence.
- [ ] State created on Build A is never loadable on Build B.
- [ ] Create an IPS/BPS-derived Build and launch it.
- [ ] Keep Game Details open, share a patch to the app, apply it to that Game and return to details. The new Build appears without backing out and reopening the Game.

- [ ] Remove its generated-ROM cache, relaunch, and confirm deterministic rebuild.
- [ ] Quick Play a new test build using a copy of Main; mutate the temporary save; Main remains unchanged.
- [ ] Promote the Quick Play session and choose whether its save becomes a new/default profile.
- [ ] Quick Play an 8 MB image on device and record the time from choosing the file to the first frame, which the game screen shows as "First frame in N ms"; it opens on the game, not the boot logo, and nothing optional (shaders, skins, custom layouts, detection) loads before it. Then play for a minute and confirm normal speed and audio.
- [ ] On both controller layouts and in both themes, the Press Any wordmark looks like a raised button. Tapping it freezes the game and opens the menu with Resume; dismissing the menu leaves the game frozen until Resume. The button remains available with a physical controller. Game-picture taps open the same paused menu only when Settings > Tap Game for Menu is on. Dragging a thumb across either doesn't open it. The first game played shows "Tap Press Any for the menu." once, and never again.
- [ ] Screen Scaling: Integer shows every Game Boy pixel the same size on both layouts; Fill makes the picture larger, most visibly on Playtiles and on Pro Max phones, with even, sharp pixels and no shimmer while scrolling.
- [ ] Settings > Acknowledgements lists SameBoy, GRDB.swift and gbtoolsid, and each opens its license text or credit.
- [ ] Controller Theme: Classic shows dark status bar text and Dark light text, and Match System follows Light and Dark Mode. The library behind the game keeps its own appearance.
- [ ] A library game shows the boot logo by default; with Settings > Skip Boot Logo on, it opens on the game.
- [ ] Move a Build to its own Game and merge it back; Build identity and data remain intact.
- [ ] Make Separate Game shows a review with the Build's own Save Profiles and the artwork selected; the new Game gets copies, shows Split From, and the original Game is unchanged.
- [ ] Import a homebrew ROM (GB Studio, GBDK or RGBDS); Import Review and the Build's Technical Info show what it was made with.
- [ ] Play Build A of a homebrew Game, then launch Build B, made with different tools, with the same save; the warning appears, and Play with a Copy leaves the original save unchanged.
- [ ] Replace Save from File on a profile with a save asks first and keeps "<name> before import"; on a blank profile it doesn't ask.
- [ ] Load State shows each state's thumbnail.
- [ ] A profile's Badge takes one emoji, shows it beside the name in the profile list and the Play with Save and Default Save menus, and refuses text.
- [ ] Deleting a profile asks first, naming it; a Build that played it plays the Game's default afterwards.
- [ ] Delete a base Build that has a patched Build: the confirmation names the patched Build, and both leave the Game. Settings > Recently Deleted lists it with the days left; Restore brings both back with their save states. Delete Game from a Game's menu, relaunch, and restore it from Recently Deleted with its Builds and saves. Delete Now removes an item for good.
- [ ] The library list labels a Game Boy Color game "Game Boy Color".
- [ ] Settings > Check Library Files reports an intact library.
- [ ] Play for five minutes with speaker sound, then with Bluetooth headphones: no crackle, the sound keeps up with the picture, and switching between them keeps the sound. With Low Power Mode on, any gap is short and doesn't keep recurring.
- [ ] With a controller connected the touch controls hide; touching the screen shows them, and the controller's next button press hides them again. With Settings > Hide Touch Controls with a Controller off, they stay shown.
- [ ] Touch Haptics: Light by default, Medium is stronger, Off has none, and there are none while a controller hides the touch controls.
- [ ] Save in a game with a battery save, wait 10 seconds, then force-quit from the app switcher: relaunching keeps the in-game save.
- [ ] Save a state, then save in the game, then load the state: it asks first, and Load keeps the newer save as "<profile> before loading state".
- [ ] In Quick Play the game menu shows Save State grayed with "Add to Library to save states", and Add to Library… opens the promotion review.
- [ ] Settings > Systems > Game Boy Color opens settings that apply to every Game Boy Color game without its own.
- [ ] Save in a game, then within a few seconds load a state taken before that save: it asks first, Cancel changes nothing, and Load keeps the newer save as "<profile> before loading state".
- [ ] Quick Play a game with no battery save, play past the title screen, and Add to Library with a new profile: Play on the new Build resumes there.
- [ ] Quick Play a ROM already in the library with a copy of its save, play, and Add to Library with a new profile: Play on that Build continues the Quick Play progress, and the Game's other Builds keep their saves.
- [ ] A patch that turns a Game Boy game into a Game Boy Color one makes a Game Boy Color Build that boots in color, and still does after Remove Generated ROM.
- [ ] Pull down Control Center and Notification Center mid-game: the game stops, and picks up again when they close. With a button held when they open, nothing stays pressed. Lock and unlock, and switch apps, with Resume Games set to Always, Ask and Never in turn. A game paused from the menu stays paused through all of these.
- [ ] At the largest accessibility text size, the library shows one column with full titles, and a Game's Builds, saves and Technical Info hashes stay readable.
- [ ] In a game, Fast Forward from the game menu runs at the Fast Forward Speed setting: change it between 1.5×, 4× and Unlimited in the game menu's Settings while Fast Forward is on, and the speed follows at once. A Game's own setting overrides App Settings.
- [ ] Fast Forward Audio Muted is silent while Fast Forward runs, and the sound returns at normal speed with no burst of old sound. Accelerated plays the sound sped up with the game at 2× and 4×, and stays muted at 8× and Unlimited.
- [ ] On both layouts, in Classic and Dark, the D-pad, A, B, SELECT and START look raised like the menu button and sink when pressed. On Playtiles the alignment guide also looks raised, lit along its top edge with a shadow below. Pausing from the menu shows Resume centered on the game picture on both layouts, clear of the guide and controls.
- [ ] A game without artwork shows its placeholder cartridge filling most of the library tile and sitting cleanly in the list row's thumbnail, in both themes.
- [ ] Files shows a Press Any folder under On My iPhone. Export ROM on a Build and Export Save on a profile with a save each add a file to Press Any › Exports, a patched Build's ROM matches its Technical Info hash, and exporting again adds a numbered copy. Opening a ROM from that folder still offers Quick Play or Import.

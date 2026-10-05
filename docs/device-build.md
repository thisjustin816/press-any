# Installing Press Any on an iPhone

These steps build Press Any on a Mac and install it on your own iPhone with a free Apple ID.
The app uses no capability that needs a paid Apple Developer Program membership, such as
iCloud, push notifications or App Groups, so free signing is enough.

## Requirements

- A Mac with a current Xcode. CI builds with Xcode 26.6; your Xcode must also support the iOS
  version on your phone.
- An iPhone on iOS 17 or later.
- [Homebrew](https://brew.sh).
- An Apple ID.
- A Game Boy or Game Boy Color ROM you are entitled to use. The original homebrew ROMs in
  `TestROMs/roms/` are available for testing; `TestROMs/README.md` describes them and their licenses.

## 1. Get the code and generate the project

```bash
git clone --recurse-submodules https://github.com/thisjustin816/press-any.git
cd press-any
brew install xcodegen rgbds
make bootstrap
open PressAny.xcodeproj
```

`make bootstrap` builds SameBoy's open-source boot ROMs with RGBDS and generates
`PressAny.xcodeproj` from `project.yml` with XcodeGen. The project file is generated and not
committed. In an existing clone, run `git submodule update --init` before `make bootstrap`.

## 2. Set up signing

1. In Xcode, open **Settings → Accounts** and add your Apple ID. A *Personal Team* appears.
2. Find the team ID: select the **PressAny** target, open **Signing & Capabilities** and pick
   your Personal Team, then search **Build Settings** for `DEVELOPMENT_TEAM`. The value is a
   10-character code.
3. Create your local signing file, which Git ignores:

   ```bash
   cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig
   ```

4. Set `DEVELOPMENT_TEAM` in it to your team ID.

Regenerating the project with `make generate` or `make bootstrap` keeps these values, because
they live outside the generated project.

Xcode registers the bundle identifier `com.thisjustin816.PressAny` to your team. If it reports
that the identifier is unavailable, set `BUNDLE_ID_SUFFIX = .dev` in the same file to build as
`com.thisjustin816.PressAny.dev`. A different identifier is a different app to iOS, with its
own data.

## 3. Prepare the iPhone

1. Connect the iPhone to the Mac with a cable, unlock it and tap **Trust**.
2. On the iPhone, open **Settings → Privacy & Security → Developer Mode**, turn it on and
   restart. The option appears only after the phone has been connected to Xcode once.

## 4. Build and run

1. Choose your iPhone as the run destination in the Xcode toolbar.
2. Press **⌘R**.
3. The first launch is blocked until you trust the certificate: on the iPhone, open
   **Settings → General → VPN & Device Management**, select your Apple ID and tap **Trust**.
   Then open Press Any from the home screen or press **⌘R** again.

After the first install, Xcode can also deploy over Wi-Fi when the phone and Mac are on the
same network.

## 5. Add a game

Put a `.gb` or `.gbc` file in the Files app, for example in iCloud Drive, then import it from
the Press Any library screen.

## Limits of free signing

- The app stops launching 7 days after it was installed. Run it from Xcode again to renew it.
  Games, saves and states stay, because the bundle identifier is unchanged.
- A free account can have at most 3 sideloaded apps on a device at once.

## Troubleshooting

| Symptom | Fix |
|---|---|
| "Signing requires a development team" | Set `DEVELOPMENT_TEAM` in `Config/Signing.local.xcconfig` (step 2), then rebuild. |
| The iPhone is not listed as a run destination | Unlock it, confirm **Trust**, and turn on Developer Mode (step 3). |
| "Failed to register bundle identifier" | Set `BUNDLE_ID_SUFFIX` (step 2). |
| "Untrusted Developer" on launch | Trust the certificate (step 4). |
| The app stopped opening after a week | Run it from Xcode again. |
| `make bootstrap` says SameBoy source is missing or not found | Run `git submodule update --init`. |
| `make bootstrap` says RGBDS is required | Run `brew install rgbds`. |
| `.gb` or `.gbc` files are grayed out in the file picker | Open an issue with the iOS version and the file name. |

## Next

Work through the device checks in `docs/mvp-verification.md` on the phone.

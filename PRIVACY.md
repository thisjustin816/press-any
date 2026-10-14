# Press Any Privacy Policy

Last updated: October 14, 2026

Press Any is a Game Boy and Game Boy Color emulator for iPhone, developed by
Justin Beeson. This policy describes the current app, including builds
distributed through TestFlight.

## Information the app collects

Press Any does not collect or transmit personal information to the developer.
The app does not require an account and contains no advertising, analytics,
tracking, or third-party crash-reporting SDKs. Its gameplay and library features
work offline. Optional artwork lookups use an online service.

## Information stored on your device

The app processes the files you choose to import and stores your library in its
private storage on your device. This includes game ROMs, patches, game metadata,
artwork, battery saves, save states and their thumbnails, Save Profiles, playtime,
and app settings. These files and records support emulation and library management.
ROMs, patches, saves, states, private artwork and your edited titles are never uploaded
to the developer or an artwork service. Online artwork requests use recognized release
names as described below.

Press Any uses local settings, file timestamps, and system timing information to
save preferences, manage temporary files, and schedule gameplay. These uses are
declared in the app's Apple privacy manifest and do not track you across apps or
websites.

## Online artwork

After import, automatic artwork is on by default. For a recognized release, Press Any
requests box art from Libretro's public thumbnail service at `thumbnails.libretro.com`.
The request contains the system and canonical release name from the bundled No-Intro
data, or the recognized base game for a modified Build. Libretro and its hosting
providers receive that request and your network address. No ROM bytes, ROM hashes,
saves, account information or player-edited names are sent.

Turn off Find Artwork on Import in Settings > Library > Artwork to stop automatic
requests. Check for New Artwork in a Game's Artwork menu makes an explicit request
even with automatic lookups off. Find Missing Artwork in the library's More menu
checks Games without artwork the same way, preserving existing and deliberately removed artwork.
Assigned images are saved in your local library, along with their source URL,
provider, fetch date and rights notice. Canceling a Game's preview discards its download;
canceling the library search keeps artwork already saved.
The app uses no tracking cookies for artwork requests and never publishes your artwork.

## Files, backups, and Apple services

When you import a file through the iOS file picker, its source may be your device,
iCloud Drive, or another file provider you choose. That provider handles its own
storage and transfers under its privacy policy. Press Any does not provide its
own cloud synchronization service.

iOS may include app data in a device backup or restore according to your Apple
settings. Apple also handles App Store downloads and may collect diagnostics
according to your settings. When you use TestFlight, Apple may provide the
developer with beta diagnostics or feedback under TestFlight's terms and your
choices. Press Any does not operate a separate diagnostics collection service.

Press Any Plus is an optional in-app purchase. Apple handles the purchase, payment,
refunds and Family Sharing through the App Store. The app asks the App Store, through
Apple's StoreKit, whether Plus is owned on your Apple Account, and keeps no record of
its own. Nothing about the purchase is sent to the developer by the app; Apple gives
developers sales reports under its own terms.

For information about these services, see
[Apple's privacy policy](https://www.apple.com/legal/privacy/).

## Keeping and deleting local data

Library data stays in the app's storage until you remove it or delete the app.
Temporary and cached files may be removed during normal app maintenance.
Deleting Press Any using iOS's Delete App option removes its local app data from
the device. That includes the Press Any folder in Files, where exports and backups
are written: it belongs to the app. Copies you share or save elsewhere, and your
original imported files, stay where they are and must be managed separately through
iOS or the relevant file provider.

## Support and contact

For privacy questions or support, contact the developer through the
[Press Any issue tracker](https://github.com/thisjustin816/press-any/issues).
Information you choose to include in a support request is used to respond to that
request. GitHub issues are public, so include only information you want to share
publicly. Do not attach private game libraries, saves, or other personal files.

GitHub operates that support service under its own
[privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement).

## Changes to this policy

If the app's data handling changes, this policy will be updated and its revision
date changed. The current policy is available in the
[Press Any repository](https://github.com/thisjustin816/press-any/blob/main/PRIVACY.md).

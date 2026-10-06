# Release

TestFlight builds come from the `TestFlight` workflow
(`.github/workflows/testflight.yml`), which uploads each commit on `main` once its
checks pass and any branch when started by hand. GitHub's macOS runner builds a
Release archive, signs it with an Apple Distribution certificate and App Store
provisioning profile, checks its privacy manifest, uploads it with an App Store
Connect team API key and fills in What to Test from the commits since the previous
upload. No Mac or local Xcode is needed.

Follow [TestFlight and App Store screenshots](testflight.md) for the app record,
certificate request, provisioning profile, all six repository secrets, build
upload, tester invitations and screenshot artifacts. The workflow uses an App
Manager API key; it does not create certificates or profiles through the API.

The iOS build workflow also verifies an unsigned Release archive on pull requests.
After installing the beta, work through `docs/mvp-verification.md` and record its
build number. A successful upload does not prove the physical-device checks.

External testing requires beta information and may require Beta App Review. An
App Store release also needs the store listing, screenshots, age rating, App
Privacy answers for the shipped app, and the rights and disclosures in
`docs/acceptance-matrix.md` under Release.

## Refreshing the No-Intro data

The app carries No-Intro's list of known Game Boy and Game Boy Color dumps in
`Packages/EmulatorKit/Sources/GameIdentity/Resources/KnownDumps.json`. Refresh it every three
months or so, and before an App Store release. No-Intro edits these DATs continually; mirrors that
refresh by hand have picked up changes every two to four months. CI's hygiene job warns when the
file is more than 90 days old or still empty.

1. On DAT-o-MATIC (datomatic.no-intro.org), open Download. In the No-Intro list, select the DB
   icon, the third, on the "Nintendo - Game Boy" row, then on the "Nintendo - Game Boy Color" row.
   Use a browser: DAT-o-MATIC bans clients it takes for bots, and it has no API.
2. Run `make known-dumps GB=<Game Boy .zip> GBC=<Game Boy Color .zip>`. The script reads the zips
   as downloaded.
3. Open a pull request with the updated file. Its description is the summary the script printed:
   the games added, removed and renamed, any it left out for having no file, and clones whose
   parent the export doesn't include.

The data reaches testers with the next TestFlight upload from `main`.

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

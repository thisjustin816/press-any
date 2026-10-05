# Release

TestFlight builds come from the manual `TestFlight` workflow (`.github/workflows/testflight.yml`).
It archives the app in Release on a macOS runner, signs it with the team's cloud-managed
distribution certificate, checks the privacy manifest in the archived app, and uploads it. No Mac
or local Xcode is needed. App Store review, store listing and external testing come later.

## One-time setup

1. **Register the bundle ID.** In the Apple Developer site, Certificates, Identifiers & Profiles >
   Identifiers > +, choose App IDs > App, and register the explicit bundle ID
   `com.thisjustin816.PressAny` with no extra capabilities. It can't be changed or reused once the
   app record exists.
2. **Create the app record.** In App Store Connect, Apps > + > New App: platform iOS, a name
   (unique on the App Store; it needn't match the home screen name), primary language, the bundle
   ID above, and any SKU, such as `press-any`.
3. **Create an API key.** In App Store Connect, Users and Access > Integrations > App Store Connect
   API > Team Keys, generate a key with the **Admin** role. Admin is needed for Xcode to create the
   cloud-managed distribution certificate and the App Store profile. Download the `.p8` file (it
   can be downloaded only once) and note the Key ID and the Issuer ID shown above the list.
4. **Find the Team ID** in the Apple Developer site, Membership details.
5. **Add four repository secrets** in GitHub, Settings > Secrets and variables > Actions:

   | Secret | Value |
   |---|---|
   | `APP_STORE_CONNECT_API_KEY_P8` | The whole `.p8` file, including its BEGIN and END lines |
   | `APP_STORE_CONNECT_KEY_ID` | The key's Key ID |
   | `APP_STORE_CONNECT_ISSUER_ID` | The Issuer ID |
   | `APPLE_TEAM_ID` | The Team ID |

   Only the TestFlight workflow reads them, and only in the steps that sign and upload. The key
   file is written to the runner's temporary folder and deleted at the end of the run.

## Uploading a build

1. In GitHub, Actions > TestFlight > Run workflow, on `main` unless testing a branch. The iOS
   build workflow already makes an unsigned Release archive on every pull request, so a build
   that reaches `main` should archive.
2. The build is version `MARKETING_VERSION` from `project.yml` with build number
   `<run number>.<attempt>`, so every run and re-run uploads a new build. The job summary names
   the version, build and commit.
3. App Store Connect processes the build, usually within 30 minutes, and emails when it's ready.
   Export compliance is already answered: `ITSAppUsesNonExemptEncryption` is false in
   `Config/PressAny-Info.plist`.
4. In App Store Connect, TestFlight > Internal Testing, add a group with yourself and turn on
   automatic distribution. Internal testers need no Beta App Review. Install the TestFlight app on
   the iPhone and accept the invite.

Then work through `docs/mvp-verification.md` on that build, noting its build number.

## Later

- **External testers** need Beta App Review, test information (a description, a feedback email)
  and a privacy policy URL.
- **App Store release** needs the store listing, screenshots, age rating, the App Privacy answers
  (no data collected), and the rights and disclosures in `docs/acceptance-matrix.md` "Release".

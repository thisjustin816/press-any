# TestFlight and App Store screenshots with GitHub Actions

No Mac is needed. GitHub's `macos-26` runner builds the app with Xcode. The
**TestFlight** workflow, automatic for `main` and manual for other branches, signs a
Release archive and uploads it to App Store Connect; the separate **Screenshots**
workflow captures simulator PNGs for download.

## 1. Create the Apple app record

An active paid Apple Developer Program membership is required for TestFlight.
Register an explicit identifier in Apple Developer with description `Press Any` and
bundle ID `com.thisjustin816.PressAny`. Leave the capabilities unchecked.

In [App Store Connect](https://appstoreconnect.apple.com/), choose **Apps → + → New App**:

| Field | Value |
|---|---|
| Platform | iOS |
| Name | Press Any (subject to Apple's name availability) |
| Primary language | English (U.S.) |
| Bundle ID | `com.thisjustin816.PressAny` |
| SKU | `press-any-ios` |
| User Access | Full Access, if shown |

The SKU is internal. Keep the bundle ID identical to `project.yml`, with no `.dev`
suffix. A registered App ID prefix may equal the Team ID, but they are separate
fields. The workflow reads the Team ID from Apple's provisioning profile.

For the App Store listing and external testing, use this Privacy Policy URL after
the policy is merged into `main`:
`https://github.com/thisjustin816/press-any/blob/main/PRIVACY.md`.

## 2. Create an Apple Distribution certificate without a Mac

On a trusted machine with OpenSSL (a Linux cloud terminal works), create a private
key and certificate signing request. Keep these files outside the repository:

```bash
umask 077
mkdir -p ../press-any-signing
openssl req -new -newkey rsa:2048 -nodes \
  -keyout ../press-any-signing/apple-distribution.key.pem \
  -out ../press-any-signing/PressAny-Distribution.csr \
  -subj '/CN=Press Any Distribution'
```

If the assistant has already generated the pair, use those files instead of
generating another key. The certificate must match that exact private key.

In [Apple Developer](https://developer.apple.com/account/resources/certificates/list),
open **Certificates → +**, choose **Apple Distribution**, upload the `.csr`, and
download the `.cer`. Keep the private key; Apple does not hold a recoverable copy.
Creating the certificate requires the appropriate developer-account permissions.

## 3. Create the provisioning profile

In Apple Developer, open **Profiles → +**. Under Distribution, choose **App Store
Connect** (some versions label it **App Store**), choose the Press Any App ID, and
select the Apple Distribution certificate from step 2. Name the profile
`Press Any App Store`, generate it, and download the `.mobileprovision` file.
This profile does not require registering devices.

## 4. Create an App Store Connect API key

In App Store Connect, open **Users and Access → Integrations → App Store Connect
API → Team Keys**. The Account Holder may first need to request API access.
Generate a team key named `Press Any GitHub Actions` with the **App Manager** role.
Record its **Key ID** and the **Issuer ID** shown on the page, then download its
`AuthKey_XXXXXXXXXX.p8` file. Apple permits downloading that key only once.
Use a team key: this workflow supplies an Issuer ID.

## 5. Add repository secrets

Open [the repository's Actions secrets settings](https://github.com/thisjustin816/press-any/settings/secrets/actions),
then choose **New repository secret** for each row:

| Secret name | Value |
|---|---|
| `APPLE_DISTRIBUTION_PRIVATE_KEY` | Entire `apple-distribution.key.pem` text, including BEGIN/END lines |
| `APPLE_DISTRIBUTION_CERTIFICATE_BASE64` | Base64 of Apple's downloaded `.cer` |
| `APPLE_PROVISIONING_PROFILE_BASE64` | Base64 of the downloaded `.mobileprovision` |
| `APP_STORE_CONNECT_KEY_ID` | API key's Key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID from the Team Keys page |
| `APP_STORE_CONNECT_PRIVATE_KEY` | Entire `.p8` text, including BEGIN/END lines |

Keep the two private keys out of chat, commits, workflow logs and downloadable
Actions artifacts. Add these as repository secrets, not environment secrets.
The upload job has `contents: read` and `actions: read`, and runs for pushes to
`main` or when started by hand from a branch in this repository, including feature
branches. A separate job without the secrets has `contents: write` to tag `main`
uploads. Review the selected branch's workflow and `Scripts/upload-testflight.sh`
before running them with signing secrets.

To convert a downloaded binary file without a Mac, run this in PowerShell and
paste the clipboard value into the matching GitHub secret:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path './distribution.cer').Path)) | Set-Clipboard
[Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path './Press_Any_App_Store.mobileprovision').Path)) | Set-Clipboard
```

Replace the example filenames with the downloaded names, and add each secret
before running the next command. A helper can also convert the `.cer` and
`.mobileprovision` files; neither contains the signing private key.

## 6. Upload a build

Every commit on `main` uploads on its own. When the **iOS build** workflow passes
on a push to `main`, the TestFlight workflow waits for **CI** on the same commit,
then archives and uploads it. A push that changes only `docs/`, `.github/` or
Markdown files since the previous upload is skipped. A failed or canceled iOS
build or CI run uploads nothing. An iOS build of `main` always runs to the end: a
newer push waits for it rather than canceling it, so a quick series of merges
still uploads. Only pull-request builds are replaced by a newer push. Because
GitHub runs a `workflow_run` workflow from `main`'s copy, and the job accepts only
pushes to this repository's `main`, pull requests never reach the signing secrets.

To upload a feature branch before merging, open **Actions → TestFlight → Run
workflow**, select the branch and run it. The selected branch supplies the
workflow and app source. Start from changes whose **CI** and **iOS build** checks
passed. No signing secret is needed for those checks or for screenshots.

To queue a feature branch from the GitHub CLI:

```bash
gh workflow run testflight.yml --repo thisjustin816/press-any --ref fix/shared-files-playtiles
```

The Actions run name includes the branch. Tags do not run the upload job. Uploads
share one queue across branches.

Each upload sets the build's **What to Test** text from the commits since the
previous upload: a merged pull request appears as its title and number. A `main`
build lists what changed since the last `main` upload; a feature branch build
lists the branch's own commits. The workflow tags each `main` upload
`testflight/<build>` at the commit it built. The next build's list starts at that
tag, and the tag maps a TestFlight build back to its commit. The text is posted
through the App Store Connect API once Apple has the build, which can take some
minutes. If that fails, the upload still counts and the run shows the warning;
add the text in App Store Connect if it matters for that build.

The upload workflow bootstraps the generated project and SameBoy boot ROMs,
imports the certificate into a temporary keychain, installs the provisioning
profile, archives the app, verifies its bundled privacy manifest, exports an IPA
using `Config/ExportOptions-TestFlight.plist` and uploads it with Apple's `altool`.
It deletes its temporary signing files and keychain when the script exits. It
does not publish an App Store release or add builds to tester groups; a beta release does that
(section 7). An internal
group with **automatic distribution** turned on receives each processed build; other
groups get a build once it is added to them in App Store Connect.

The marketing version comes from `MARKETING_VERSION` in `project.yml` (currently
`0.1`), and TestFlight shows it with the build number beside it, as `0.1 (57)`.
The version changes only when that value is edited. The build number is the
workflow's run number; a retried run adds its attempt, as `57.2`, because Apple
refuses a second binary with the same build number. Builds uploaded before this
scheme were numbered `1.<run>.<attempt>`; every run number since is higher. Keep
this workflow as the build-number source; other upload paths must avoid
collisions.

After a successful upload, wait for Apple's processing, then open **Apps → Press
Any → TestFlight**. Resolve any processing or compliance questions shown there.
The app's Info.plist already declares `ITSAppUsesNonExemptEncryption = false`.
If Apple asks an export-compliance question, answer for the actual uploaded app.

For your own device, create an **Internal Testing** group, select the processed
build and add yourself as an internal tester. Install Apple's TestFlight app on
your iPhone and accept the invitation. Internal testers must be eligible App
Store Connect users; external testers use **External Testing**, which requires
beta information and may require Apple's beta review.

## 7. Release a beta

Every `main` upload reaches the internal group on its own. A GitHub release sends a build further,
through the **Release** workflow (`.github/workflows/release.yml`).

Set up once:

1. In App Store Connect, create an **External Testing** group with a public link and fill in
   **Test Information** (beta description, feedback email, contact details). Beta App Review
   needs them before it accepts a build.
2. In GitHub, add a repository variable (**Settings → Secrets and variables → Actions →
   Variables**) named `TESTFLIGHT_PUBLIC_GROUP`, set to that group's name.

Then open **Actions → Release → Run workflow** on `main` and choose **beta**. The run tags
`main`'s newest TestFlight upload with the next beta tag for the version in `project.yml`, such as
`v0.1.0-beta.1` and then `v0.1.0-beta.2`, publishes the pre-release, adds the build to the group
and submits it for Beta App Review. It refuses a build that's already released. Testers get it once
Apple approves it: the first build of a version can take a day, and later ones are often quicker.

**Notes** becomes the build's What to Test. Left empty, it's the changes since the previous
release, beta or stable. The release's description on GitHub is the same text, followed by the
public group's join link.

A release published by hand works too: tag a commit on `main` with the version and a beta suffix
and mark it **Set as a pre-release**. Its build is the nearest `testflight/<build>` tag at or
before its commit, and an empty description gets one written for it. A release whose commit isn't
on `main` is refused, since it would run that commit's scripts with the API key.

Choosing **stable** tags the newest upload `v<version>`, such as `v0.1.0`, with the changes since
the previous stable release as its description, and names the build to submit. A version is
released as stable once; raise `MARKETING_VERSION` for the next. Submitting it to the App Store is
still done by hand in App Store Connect.

## 8. Download screenshots for App Store Connect

Open **Actions → Screenshots → Run workflow** and choose:

| Input | Value |
|---|---|
| device | iPhone 14 Plus (6.5-inch screenshots) |
| roms | hero |
| shots | summary |
| appearance | both (or light for one set) |
| text_size | default |
| import_rom | Leave the default |

After the run, download `screenshots-light-6.5-inch` and/or `screenshots-dark-6.5-inch` from its
**Artifacts** section and unzip them. Select the PNGs, not the included logs.
They show the original test ROMs from `TestROMs/`, with no commercial game images.

The iPhone 14 Plus captures are 1284 × 2778 pixels (or 2778 × 1284 in landscape),
which fit Apple's 6.5-inch screenshot slot. The workflow checks every PNG's
dimensions. Choose iPhone 17 Pro Max only for the separate 6.9-inch slot; those
larger PNGs will be rejected in the 6.5-inch slot. Use portrait captures for
portrait slots and landscape captures for landscape slots.
Choose up to ten clear images, for example the library, gameplay, the game page,
Build info and Settings. Check that each shows a loaded app, readable content and
features present in the Release build; screenshot seeding runs in Debug.

In **Apps → Press Any → the iOS version page → App Previews and Screenshots**,
select the iPhone display-size group and drag in the chosen PNGs. Screenshots
belong to the App Store version page; they are not required for internal
TestFlight testing. The project currently targets iPhone only, so it does not
need an iPad screenshot set. Capturing screenshots does not upload them to Apple.

## Troubleshooting

| Symptom | What to check |
|---|---|
| TestFlight job is skipped | For `main`, the iOS build run on that push failed or was canceled by a newer push; otherwise dispatch it from a repository branch, not a tag |
| Run succeeds but uploads nothing | The push changed only docs, workflows or Markdown since the previous upload; the run summary says so |
| What to Test is empty | The Set What to Test step's log; Apple may not have finished processing within its wait |
| `Missing ...` | The matching repository secret is present with the exact name |
| OpenSSL rejects the certificate or key | `.cer` is Apple's original DER file; the private key matches the CSR used for it |
| No matching provisioning profile / signing identity | Profile includes this certificate, is for `com.thisjustin816.PressAny`, and is App Store distribution; regenerate expired credentials |
| API authentication fails | Team key's Key ID, Issuer ID and full `.p8` text belong together; role allows build uploads |
| Duplicate build number | Retry the workflow; avoid uploading through a second numbering scheme |
| Upload succeeds but the build is absent | Wait for processing and check App Store Connect and Apple's processing email |
| Screenshot run fails | Download its artifact anyway and inspect `screenshots.log` and app/simulator logs; PNGs may be partial |

Distribution success does not verify gameplay on an iPhone. Use
`docs/mvp-verification.md` for the physical-device checks after installing the beta.

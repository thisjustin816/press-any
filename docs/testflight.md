# TestFlight and App Store screenshots with GitHub Actions

No Mac is needed. GitHub's `macos-26` runner builds the app with Xcode. The manual
**TestFlight** workflow signs a Release archive and uploads it to App Store Connect;
the separate **Screenshots** workflow captures simulator PNGs for download.

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
The workflow has `contents: read` and is manually dispatched from `main` only;
review changes to it and `Scripts/upload-testflight.sh` before merging them.

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

After the workflow is merged into `main`, open **Actions → TestFlight → Run
workflow**, select `main`, and run it. Start from a commit whose **CI** and
**iOS build** checks passed. No signing secret is needed for those checks or for
screenshots.

The upload workflow bootstraps the generated project and SameBoy boot ROMs,
imports the certificate into a temporary keychain, installs the provisioning
profile, archives the app, verifies its bundled privacy manifest, exports an IPA
using `Config/ExportOptions-TestFlight.plist` and uploads it with Apple's `altool`.
It deletes its temporary signing files and keychain when the script exits. It
does not publish an App Store release or automatically invite testers.

The marketing version comes from `project.yml` (currently `0.1.0`). The build
number encodes the workflow run and retry as three numeric components: run 1,
attempt 1 is `1.1.1`; run 100, attempt 1 is `2.0.1`. Retrying a run uploads a
different build number. Keep this workflow as the build-number source for this
marketing version; other upload paths must avoid collisions.

After a successful upload, wait for Apple's processing, then open **Apps → Press
Any → TestFlight**. Resolve any processing or compliance questions shown there.
The app's Info.plist already declares `ITSAppUsesNonExemptEncryption = false`.
If Apple asks an export-compliance question, answer for the actual uploaded app.

For your own device, create an **Internal Testing** group, select the processed
build and add yourself as an internal tester. Install Apple's TestFlight app on
your iPhone and accept the invitation. Internal testers must be eligible App
Store Connect users; external testers use **External Testing**, which requires
beta information and may require Apple's beta review.

## 7. Download screenshots for App Store Connect

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
| TestFlight job is skipped | Dispatch it from `main` |
| `Missing ...` | The matching repository secret is present with the exact name |
| OpenSSL rejects the certificate or key | `.cer` is Apple's original DER file; the private key matches the CSR used for it |
| No matching provisioning profile / signing identity | Profile includes this certificate, is for `com.thisjustin816.PressAny`, and is App Store distribution; regenerate expired credentials |
| API authentication fails | Team key's Key ID, Issuer ID and full `.p8` text belong together; role allows build uploads |
| Duplicate build number | Retry the workflow; avoid uploading through a second numbering scheme |
| Upload succeeds but the build is absent | Wait for processing and check App Store Connect and Apple's processing email |
| Screenshot run fails | Download its artifact anyway and inspect `screenshots.log` and app/simulator logs; PNGs may be partial |

Distribution success does not verify gameplay on an iPhone. Use
`docs/mvp-verification.md` for the physical-device checks after installing the beta.

#!/usr/bin/env bash
set -euo pipefail

required=(APPLE_DISTRIBUTION_PRIVATE_KEY APPLE_DISTRIBUTION_CERTIFICATE_BASE64
  APPLE_PROVISIONING_PROFILE_BASE64 APP_STORE_CONNECT_KEY_ID
  APP_STORE_CONNECT_ISSUER_ID APP_STORE_CONNECT_PRIVATE_KEY GITHUB_RUN_NUMBER
  GITHUB_RUN_ATTEMPT RUNNER_TEMP)
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "Missing $name. See docs/testflight.md for GitHub secret setup." >&2
    exit 1
  fi
done
if [[ ! $APP_STORE_CONNECT_KEY_ID =~ ^[A-Za-z0-9]+$ ||
      ! $GITHUB_RUN_NUMBER =~ ^[1-9][0-9]{0,5}$ ||
      ! $GITHUB_RUN_ATTEMPT =~ ^[1-9][0-9]?$ ]] || ((GITHUB_RUN_NUMBER > 999899)); then
  echo "Invalid API key ID, run number or run attempt." >&2
  exit 1
fi
if [[ "$(uname -s)" != Darwin ]]; then
  echo "TestFlight uploads require macOS/Xcode, provided by the GitHub Actions runner." >&2
  exit 1
fi
if [[ -e Config/Signing.local.xcconfig ]]; then
  echo "Use a clean Actions checkout; Config/Signing.local.xcconfig already exists." >&2
  exit 1
fi

umask 077
signing_dir="$(mktemp -d "$RUNNER_TEMP/testflight.XXXXXX")"
keychain="$signing_dir/signing.keychain-db"
profile_path=""
local_signing_created=false
original_keychains=()
while IFS= read -r line; do
  line="${line#*\"}"
  original_keychains+=("${line%\"*}")
done < <(security list-keychains -d user)
cleanup() {
  if ((${#original_keychains[@]})); then
    security list-keychains -d user -s "${original_keychains[@]}" || true
  fi
  security delete-keychain "$keychain" 2>/dev/null || true
  [[ -z $profile_path ]] || rm -f "$profile_path"
  if [[ $local_signing_created == true ]]; then
    rm -f Config/Signing.local.xcconfig
  fi
  rm -rf "$signing_dir"
}
trap cleanup EXIT

printf '%s' "$APPLE_DISTRIBUTION_PRIVATE_KEY" >"$signing_dir/distribution.key"
printf '%s' "$APPLE_DISTRIBUTION_CERTIFICATE_BASE64" | base64 --decode >"$signing_dir/distribution.cer"
printf '%s' "$APPLE_PROVISIONING_PROFILE_BASE64" | base64 --decode >"$signing_dir/profile.mobileprovision"
printf '%s' "$APP_STORE_CONNECT_PRIVATE_KEY" >"$signing_dir/AuthKey_$APP_STORE_CONNECT_KEY_ID.p8"
unset APPLE_DISTRIBUTION_PRIVATE_KEY APPLE_DISTRIBUTION_CERTIFICATE_BASE64
unset APPLE_PROVISIONING_PROFILE_BASE64 APP_STORE_CONNECT_PRIVATE_KEY

openssl x509 -inform DER -in "$signing_dir/distribution.cer" -out "$signing_dir/distribution.pem"
openssl x509 -in "$signing_dir/distribution.pem" -checkend 0 -noout
if ! cmp -s <(openssl pkey -in "$signing_dir/distribution.key" -pubout) \
    <(openssl x509 -in "$signing_dir/distribution.pem" -pubkey -noout); then
  echo "The distribution certificate does not match the signing private key." >&2
  exit 1
fi
security cms -D -i "$signing_dir/profile.mobileprovision" >"$signing_dir/profile.plist"
# Reject a development/ad-hoc profile or the wrong app before touching the keychain.
python3 - "$signing_dir/profile.plist" "$signing_dir/distribution.cer" <<'PY'
import datetime
import plistlib
import sys

with open(sys.argv[1], "rb") as source:
    profile = plistlib.load(source)
entitlements = profile["Entitlements"]
app_id = entitlements["application-identifier"]
if app_id.split(".", 1)[-1] != "com.thisjustin816.PressAny":
    sys.exit("Provisioning profile is not for com.thisjustin816.PressAny.")
if (entitlements.get("get-task-allow") or "ProvisionedDevices" in profile
        or profile.get("ProvisionsAllDevices")):
    sys.exit("Select an App Store Connect distribution provisioning profile.")
if profile["ExpirationDate"] <= datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None):
    sys.exit("Provisioning profile has expired; regenerate it in Apple Developer.")
with open(sys.argv[2], "rb") as source:
    if source.read() not in profile["DeveloperCertificates"]:
        sys.exit("Provisioning profile does not include this distribution certificate.")
PY
team_id="$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$signing_dir/profile.plist")"
profile_uuid="$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$signing_dir/profile.plist")"
profile_path="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/$profile_uuid.mobileprovision"
mkdir -p "$(dirname "$profile_path")"
cp "$signing_dir/profile.mobileprovision" "$profile_path"

keychain_password="$(openssl rand -hex 32)"
echo "::add-mask::$keychain_password"
export TESTFLIGHT_KEYCHAIN_PASSWORD="$keychain_password"
openssl pkcs12 -export -inkey "$signing_dir/distribution.key" \
  -in "$signing_dir/distribution.pem" -out "$signing_dir/distribution.p12" \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
  -passout env:TESTFLIGHT_KEYCHAIN_PASSWORD
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$signing_dir/distribution.p12" -k "$keychain" -P "$keychain_password" \
  -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain"
security list-keychains -d user -s "$keychain" "${original_keychains[@]}"
unset TESTFLIGHT_KEYCHAIN_PASSWORD

archive="$RUNNER_TEMP/PressAny.xcarchive"
export_dir="$RUNNER_TEMP/PressAny-export"
# The first component allows four digits, the other two allow two. Retries must upload a new
# version because Apple will not accept a second binary with the same build number.
version="$((1 + GITHUB_RUN_NUMBER / 100)).$((GITHUB_RUN_NUMBER % 100)).$GITHUB_RUN_ATTEMPT"
# Signing belongs to the app target's xcconfig: command-line profile settings would also
# reach package resource bundles, which do not support provisioning profiles.
local_signing_created=true
cat >Config/Signing.local.xcconfig <<EOF
CODE_SIGN_STYLE = Manual
CODE_SIGN_IDENTITY = Apple Distribution
DEVELOPMENT_TEAM = $team_id
PROVISIONING_PROFILE_SPECIFIER = $profile_uuid
BUNDLE_ID_SUFFIX =
EOF
xcodebuild -project PressAny.xcodeproj -scheme PressAny -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$archive" archive \
  CURRENT_PROJECT_VERSION="$version"

python3 - "$signing_dir/ExportOptions.plist" "$team_id" "$profile_uuid" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "wb") as output:
    plistlib.dump({
        "method": "app-store-connect",
        "destination": "export",
        "signingStyle": "manual",
        "signingCertificate": "Apple Distribution",
        "teamID": sys.argv[2],
        "provisioningProfiles": {"com.thisjustin816.PressAny": sys.argv[3]},
        "manageAppVersionAndBuildNumber": False,
        "uploadSymbols": True,
    }, output)
PY
xcodebuild -exportArchive -archivePath "$archive" -exportPath "$export_dir" \
  -exportOptionsPlist "$signing_dir/ExportOptions.plist"

API_PRIVATE_KEYS_DIR="$signing_dir" xcrun altool --upload-app --type ios \
  --file "$export_dir/PressAny.ipa" --apiKey "$APP_STORE_CONNECT_KEY_ID" \
  --apiIssuer "$APP_STORE_CONNECT_ISSUER_ID"
if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
  printf 'Uploaded Press Any build `%s`. Apple must process it before it appears in TestFlight.\n' \
    "$version" >>"$GITHUB_STEP_SUMMARY"
fi

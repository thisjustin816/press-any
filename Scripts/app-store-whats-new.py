#!/usr/bin/env python3
"""Sets an App Store version's English What's New from a text file in the repository.

Checks the text, finds the iOS App Store version with that version string and its en-US
localization, and prints the current and new lengths with the new text. With --apply it writes
the text, and only while the version is still editable. Anything unexpected stops the run before
it writes. .github/workflows/whats-new.yml runs it from main, with the App Store Connect key that
appstoreconnect.py reads. Standard library only.
"""

import argparse
import re
import sys
import unicodedata
import urllib.error

from appstoreconnect import client_from_environment, describe

# Apple's limit for an App Store version's What's New.
MAX_WHATS_NEW = 4000
LOCALE = "en-US"
VERSION = re.compile(r"[0-9]+\.[0-9]+(\.[0-9]+)?")
# App Store Connect IDs are numbers or UUIDs; anything else isn't put in a request path.
RESOURCE_ID = re.compile(r"[A-Za-z0-9-]+")
# The states in which Apple lets a version's metadata change. Every other state, including
# READY_FOR_SALE, PENDING_APPLE_RELEASE, WAITING_FOR_REVIEW and IN_REVIEW, is refused.
EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}


def character_count(text):
    """The length in UTF-16 code units, which is never less than the number of characters, so a
    text within it is within Apple's limit whether Apple counts characters or code units."""
    return len(text.encode("utf-16-le")) // 2


def read_text(path):
    """The file's text without its final newline, or exit naming what's wrong with it."""
    try:
        with open(path, "rb") as source:
            raw = source.read()
    except FileNotFoundError:
        sys.exit(f"{path} doesn't exist. Add it to main in a pull request first.")
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as error:
        sys.exit(f"{path} isn't UTF-8: {error}.")
    text = text.removesuffix("\n")
    if not text.strip():
        sys.exit(f"{path} is empty.")
    if text != text.strip():
        sys.exit(f"{path} starts or ends with a blank line or space.")
    for line, content in enumerate(text.split("\n"), start=1):
        for character in content:
            # Cc is control characters, tab and carriage return included; Cf is invisible
            # formatting characters, such as a byte order mark or a zero-width space; Zl and Zp
            # are line and paragraph separators other than a newline.
            if unicodedata.category(character) in ("Cc", "Cf", "Zl", "Zp"):
                sys.exit(f"{path} line {line} has the character U+{ord(character):04X}; use plain text.")
    if character_count(text) > MAX_WHATS_NEW:
        sys.exit(f"{path} is {character_count(text)} characters; What's New takes at most {MAX_WHATS_NEW}.")
    return text


def resources(response, kind):
    """The resources in a list response, checked to have the shape the rest of the script reads."""
    data = response.get("data") if isinstance(response, dict) else None
    if not isinstance(data, list):
        sys.exit(f"App Store Connect's list of {kind} has an unexpected shape.")
    if (response.get("links") or {}).get("next"):
        sys.exit(f"App Store Connect's list of {kind} has more than one page, so the match is ambiguous.")
    for item in data:
        if not (isinstance(item, dict) and item.get("type") == kind
                and isinstance(item.get("id"), str) and RESOURCE_ID.fullmatch(item["id"])
                and isinstance(item.get("attributes"), dict)):
            sys.exit(f"An item in App Store Connect's list of {kind} has an unexpected shape.")
    return data


def editable_version(client, app_id, version):
    """The app's one iOS App Store version with this version string, if Apple lets it change."""
    response = client.request(
        "GET",
        f"/apps/{app_id}/appStoreVersions?filter[versionString]={version}&filter[platform]=IOS"
        "&fields[appStoreVersions]=versionString,platform,appStoreState,appVersionState&limit=200",
    )
    matches = [
        item for item in resources(response, "appStoreVersions")
        if item["attributes"].get("versionString") == version and item["attributes"].get("platform") == "IOS"
    ]
    if not matches:
        sys.exit(f"App Store Connect has no iOS version {version}. Create it there first.")
    if len(matches) > 1:
        sys.exit(f"App Store Connect has {len(matches)} iOS versions named {version}, so the match is ambiguous.")
    match = matches[0]
    # appVersionState is Apple's newer name for the state; both must say the version is editable.
    states = [match["attributes"].get(name) for name in ("appStoreState", "appVersionState")]
    states = [state for state in states if state is not None]
    if not states:
        sys.exit(f"App Store Connect didn't give version {version}'s state.")
    for state in states:
        if state not in EDITABLE:
            sys.exit(f"Version {version} is {state}, so its What's New can't change. Only a version in "
                     f"{', '.join(sorted(EDITABLE))} is written.")
    return match, states[0]


def localization(client, version_id, version):
    """The version's en-US localization. A missing one isn't created: Apple makes it with the version."""
    response = client.request(
        "GET",
        f"/appStoreVersions/{version_id}/appStoreVersionLocalizations"
        "?fields[appStoreVersionLocalizations]=locale,whatsNew&limit=200",
    )
    matches = [
        item for item in resources(response, "appStoreVersionLocalizations")
        if item["attributes"].get("locale") == LOCALE
    ]
    if not matches:
        sys.exit(f"Version {version} has no {LOCALE} localization. Add English (U.S.) in App Store Connect first.")
    if len(matches) > 1:
        sys.exit(f"Version {version} has {len(matches)} {LOCALE} localizations, so the match is ambiguous.")
    current = matches[0]["attributes"].get("whatsNew")
    if current is not None and not isinstance(current, str):
        sys.exit(f"Version {version}'s {LOCALE} What's New has an unexpected shape.")
    return matches[0]["id"], current or ""


def publish(client, version, path, text, apply):
    app_id = client.app_id()
    found, state = editable_version(client, app_id, version)
    localization_id, current = localization(client, found["id"], version)

    print(f"Version {version} (iOS) is {state}, so its What's New can change.")
    print(f"{LOCALE} What's New in App Store Connect: {character_count(current)} characters.")
    print(f"{path}: {character_count(text)} of {MAX_WHATS_NEW} characters.")
    print("-----")
    print(text)
    print("-----")
    if current == text:
        print("App Store Connect already has this text, so nothing was written.")
        return
    if not apply:
        print("Preview only, so nothing was written. Run again with apply to write this text.")
        return

    response = client.request("PATCH", f"/appStoreVersionLocalizations/{localization_id}", {"data": {
        "type": "appStoreVersionLocalizations",
        "id": localization_id,
        "attributes": {"whatsNew": text},
    }})
    data = response.get("data") if isinstance(response, dict) else None
    attributes = data.get("attributes") if isinstance(data, dict) else None
    if not isinstance(attributes, dict) or attributes.get("whatsNew") != text:
        sys.exit(f"App Store Connect accepted the change but didn't return the same text. "
                 f"Check version {version}'s What's New in App Store Connect.")
    print(f"Wrote the {LOCALE} What's New for version {version}.")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--version", required=True, help="App Store version string, such as 1.1")
    parser.add_argument("--text", required=True, help="the What's New text file")
    parser.add_argument("--apply", action="store_true", help="write the text; without it, only preview")
    args = parser.parse_args()

    if not VERSION.fullmatch(args.version):
        sys.exit(f"{args.version!r} isn't a version such as 1.1 or 1.1.1.")
    # Every check on the text runs before the key is read or any request is made.
    text = read_text(args.text)
    try:
        with client_from_environment() as client:
            publish(client, args.version, args.text, text, args.apply)
    except urllib.error.HTTPError as error:
        sys.exit(f"App Store Connect answered {error.code}: {describe(error)}")


if __name__ == "__main__":
    main()

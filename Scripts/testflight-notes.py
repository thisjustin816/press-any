#!/usr/bin/env python3
"""TestFlight "What to Test" notes, written from the commits since the previous upload.

`notes` writes the notes for a commit and reports whether the app changed since the last
upload. `publish` sets them on the uploaded build through the App Store Connect API, using the
team API key in APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID and
APP_STORE_CONNECT_PRIVATE_KEY.

Each main upload is tagged `testflight/<build>` (.github/workflows/testflight.yml), so the
nearest such tag is where the next build's notes start. Standard library only.
"""

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

BUNDLE_ID = "com.thisjustin816.PressAny"
API = "https://api.appstoreconnect.apple.com/v1"
TAG_PREFIX = "testflight/"
# Apple's limit for What to Test.
MAX_NOTES = 4000
# Paths that never change the app, so a push touching only these needs no new build.
NON_APP = re.compile(r"^(docs/|\.github/|LICENSE$)|\.md$")


def git(*args):
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True).stdout


def previous_tag(sha):
    """The nearest upload tag at or before `sha`, or None before the first."""
    try:
        return git("describe", "--tags", "--abbrev=0", "--match", f"{TAG_PREFIX}*", sha).strip()
    except subprocess.CalledProcessError:
        return None


def change_titles(revisions):
    """One line per first-parent commit, newest first. A merged pull request is listed by its
    title, which GitHub puts in the merge commit's body."""
    log = git("log", "--first-parent", "--format=%s%x1f%b%x1e", *revisions)
    titles = []
    for entry in filter(None, (e.strip("\n") for e in log.split("\x1e"))):
        subject, _, body = entry.partition("\x1f")
        merge = re.match(r"Merge pull request #(\d+) ", subject)
        if merge:
            title = next((line.strip() for line in body.splitlines() if line.strip()), subject)
            titles.append(f"{title} (#{merge.group(1)})")
        else:
            titles.append(subject)
    return titles


def fit(header, titles):
    lines = [header]
    for index, title in enumerate(titles):
        more = f"- ...and {len(titles) - index} more"
        if len("\n".join(lines + [f"- {title}", more])) > MAX_NOTES:
            lines.append(more)
            break
        lines.append(f"- {title}")
    return "\n".join(lines)


def notes_command(args):
    short = git("rev-parse", "--short", args.sha).strip()
    if args.branch == "main":
        previous = previous_tag(args.sha)
        if previous:
            app_changed = any(
                not NON_APP.search(path)
                for path in git("diff", "--name-only", previous, args.sha).split()
            )
            titles = change_titles([f"{previous}..{args.sha}"])
            since = f"build {previous.removeprefix(TAG_PREFIX)}"
        else:
            app_changed = True
            titles = change_titles(["-20", args.sha])
            since = None
        header = f"main at {short}."
        if titles:
            header += f"\n\nChanges since {since}:" if since else "\n\nRecent changes:"
        else:
            header += f"\n\nNo changes since {since}." if since else ""
    else:
        app_changed = True
        titles = change_titles([f"origin/main..{args.sha}"])
        header = f"Branch {args.branch} at {short}, not yet on main."
        if titles:
            header += "\n\nChanges on the branch:"

    text = fit(header, titles)
    with open(args.output, "w", encoding="utf-8") as output:
        output.write(text + "\n")
    print(text)
    if "GITHUB_OUTPUT" in os.environ:
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
            output.write(f"app_changed={'true' if app_changed else 'false'}\n")


def base64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(signature):
    """openssl writes ECDSA signatures as DER; a JWT carries r and s as 32 bytes each."""
    if signature[0] != 0x30:
        raise ValueError("not a DER sequence")
    offset = 3 if signature[1] & 0x80 else 2
    raw = b""
    for _ in range(2):
        if signature[offset] != 0x02:
            raise ValueError("not a DER integer")
        length = signature[offset + 1]
        value = signature[offset + 2:offset + 2 + length].lstrip(b"\0")
        if len(value) > 32:
            raise ValueError("integer longer than 32 bytes")
        raw += value.rjust(32, b"\0")
        offset += 2 + length
    return raw


def token(key_id, issuer_id, key_path):
    now = int(time.time())
    header = base64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
    claims = base64url(json.dumps(
        {"iss": issuer_id, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}
    ).encode())
    signing_input = f"{header}.{claims}".encode()
    signature = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", key_path],
        input=signing_input, check=True, capture_output=True,
    ).stdout
    return f"{header}.{claims}.{base64url(der_to_raw(signature))}"


class Client:
    """Signs a new token for each request, since waiting on processing can outlast one."""

    def __init__(self, key_id, issuer_id, key_path):
        self.key_id = key_id
        self.issuer_id = issuer_id
        self.key_path = key_path

    def request(self, method, path, body=None):
        bearer = token(self.key_id, self.issuer_id, self.key_path)
        request = urllib.request.Request(
            f"{API}{path}",
            method=method,
            data=None if body is None else json.dumps(body).encode(),
            headers={"Authorization": f"Bearer {bearer}", "Content-Type": "application/json"},
        )
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.load(response)


def publish_command(args):
    with open(args.notes, encoding="utf-8") as source:
        text = source.read().strip()
    with tempfile.TemporaryDirectory() as directory:
        key_path = os.path.join(directory, "AuthKey.p8")
        descriptor = os.open(key_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w") as key:
            key.write(os.environ["APP_STORE_CONNECT_PRIVATE_KEY"])
        client = Client(os.environ["APP_STORE_CONNECT_KEY_ID"], os.environ["APP_STORE_CONNECT_ISSUER_ID"], key_path)
        publish_build_notes(client, args, text)


def publish_build_notes(client, args, text):
    apps = client.request("GET", f"/apps?filter[bundleId]={BUNDLE_ID}&fields[apps]=bundleId")["data"]
    if not apps:
        sys.exit(f"No App Store Connect app has the bundle ID {BUNDLE_ID}.")
    app_id = apps[0]["id"]

    # The build appears some minutes after the upload, and may refuse notes while it processes.
    deadline = time.monotonic() + args.wait_minutes * 60
    while True:
        try:
            builds = client.request(
                "GET",
                f"/builds?filter[app]={app_id}&filter[version]={args.build}"
                f"&filter[preReleaseVersion.version]={args.version}&fields[builds]=version",
            )["data"]
            if builds:
                set_notes(client, builds[0]["id"], text)
                print(f"Set What to Test on {args.version} ({args.build}).")
                return
            reason = "the build has not appeared yet"
        except urllib.error.HTTPError as error:
            if error.code in (401, 403):
                raise
            reason = f"App Store Connect answered {error.code}"
        if time.monotonic() > deadline:
            sys.exit(f"Gave up after {args.wait_minutes} minutes: {reason}.")
        print(f"Waiting: {reason}.")
        time.sleep(30)


def set_notes(client, build_id, text):
    localizations = client.request("GET", f"/builds/{build_id}/betaBuildLocalizations")["data"]
    existing = next((loc for loc in localizations if loc["attributes"]["locale"] == "en-US"), None)
    if existing:
        client.request("PATCH", f"/betaBuildLocalizations/{existing['id']}", {"data": {
            "type": "betaBuildLocalizations",
            "id": existing["id"],
            "attributes": {"whatsNew": text},
        }})
    else:
        client.request("POST", "/betaBuildLocalizations", {"data": {
            "type": "betaBuildLocalizations",
            "attributes": {"locale": "en-US", "whatsNew": text},
            "relationships": {"build": {"data": {"type": "builds", "id": build_id}}},
        }})


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    commands = parser.add_subparsers(required=True)

    notes = commands.add_parser("notes", help="write the notes for a commit")
    notes.add_argument("--sha", required=True)
    notes.add_argument("--branch", required=True)
    notes.add_argument("--output", required=True)
    notes.set_defaults(run=notes_command)

    publish = commands.add_parser("publish", help="set the notes on an uploaded build")
    publish.add_argument("--version", required=True, help="marketing version, such as 0.1.0")
    publish.add_argument("--build", required=True, help="build number, such as 1.3.1")
    publish.add_argument("--notes", required=True)
    publish.add_argument("--wait-minutes", type=int, default=25)
    publish.set_defaults(run=publish_command)

    args = parser.parse_args()
    args.run(args)


if __name__ == "__main__":
    main()

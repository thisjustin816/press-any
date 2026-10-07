#!/usr/bin/env python3
"""GitHub releases for TestFlight and the App Store.

`notes` writes a release's notes: the changes on main since the previous release. A beta counts
from the previous release of either kind, a stable release from the previous stable one.
`beta` gives the public TestFlight group the build a beta release points at and submits it for
Beta App Review, with the notes as its What to Test.

Release tags are `v<version>`, with a hyphenated suffix such as `v0.2.0-beta.1` for a beta. A
release's build is the nearest `testflight/<build>` tag at or before its commit (testflight.yml
tags each main upload). Standard library only.
"""

import argparse
import json
import sys
import urllib.error
import urllib.parse

from appstoreconnect import client_from_environment
from changelog import change_titles, fit, git, nearest_tag


def notes_command(args):
    commit = f"{args.tag}^{{commit}}"
    previous = nearest_tag(f"{commit}^", "v*", exclude=None if args.beta else "v*-*")
    if previous:
        titles = change_titles([f"{previous}..{commit}"])
        header = f"Changes since {previous}:" if titles else f"No changes since {previous}."
    else:
        titles = change_titles(["-20", commit])
        header = "Recent changes:"
    text = fit(header, titles)
    with open(args.output, "w", encoding="utf-8") as output:
        output.write(text + "\n")
    print(text)


def build_for(tag):
    """The TestFlight build number for the release's commit, and the commit that build came from."""
    upload = nearest_tag(f"{tag}^{{commit}}", "testflight/*")
    if not upload:
        sys.exit(f"No TestFlight upload is at or before {tag}.")
    return upload.removeprefix("testflight/"), git("rev-list", "-n", "1", upload).strip()


def describe(error):
    try:
        errors = json.loads(error.read())["errors"]
        return "; ".join(e.get("detail") or e.get("title", "") for e in errors)
    except Exception:
        return str(error)


def beta_command(args):
    number, built = build_for(args.tag)
    release = git("rev-list", "-n", "1", args.tag).strip()
    if built != release:
        print(f"{args.tag} is past the last upload; build {number} has the same app, from {built[:7]}.")
    with open(args.notes, encoding="utf-8") as source:
        notes = source.read().strip()

    with client_from_environment() as client:
        app_id = client.app_id()
        builds = client.request(
            "GET", f"/builds?filter[app]={app_id}&filter[version]={number}&fields[builds]=version,processingState"
        )["data"]
        if not builds:
            sys.exit(f"App Store Connect has no build {number}.")
        build_id = builds[0]["id"]
        name = urllib.parse.quote(args.group)
        groups = client.request(
            "GET", f"/betaGroups?filter[app]={app_id}&filter[name]={name}&fields[betaGroups]=name,isInternalGroup"
        )["data"]
        if not groups:
            sys.exit(f"No TestFlight group is named {args.group!r}.")
        group = groups[0]
        if group["attributes"]["isInternalGroup"]:
            sys.exit(f"{args.group!r} is an internal group, which gets every build already.")

        if notes:
            client.set_whats_new(build_id, notes)
        client.request("POST", f"/betaGroups/{group['id']}/relationships/builds",
                       {"data": [{"type": "builds", "id": build_id}]})
        print(f"Added build {number} to {args.group}.")
        try:
            client.request("POST", "/betaAppReviewSubmissions", {"data": {
                "type": "betaAppReviewSubmissions",
                "relationships": {"build": {"data": {"type": "builds", "id": build_id}}},
            }})
            print(f"Submitted build {number} for Beta App Review.")
        except urllib.error.HTTPError as error:
            # A build already submitted, or approved, answers 409; anything else is a real failure.
            if error.code != 409:
                sys.exit(f"Beta App Review submission failed ({error.code}): {describe(error)}")
            print(f"Build {number} was already submitted: {describe(error)}")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    commands = parser.add_subparsers(required=True)

    notes = commands.add_parser("notes", help="write a release's notes")
    notes.add_argument("--tag", required=True)
    notes.add_argument("--beta", action="store_true", help="count from the previous release of either kind")
    notes.add_argument("--output", required=True)
    notes.set_defaults(run=notes_command)

    beta = commands.add_parser("beta", help="give the public group a beta release's build")
    beta.add_argument("--tag", required=True)
    beta.add_argument("--group", required=True, help="the public TestFlight group's name")
    beta.add_argument("--notes", required=True)
    beta.set_defaults(run=beta_command)

    args = parser.parse_args()
    args.run(args)


if __name__ == "__main__":
    main()

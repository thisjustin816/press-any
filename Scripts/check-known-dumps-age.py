#!/usr/bin/env python3
"""Warn in CI when the bundled No-Intro data is due for a refresh.

No-Intro edits its Game Boy and Game Boy Color DATs continually, and downstream
mirrors that refresh by hand have picked up changes every two to four months.
This prints a GitHub Actions warning when KnownDumps.json is older than
MAX_AGE_DAYS or has never been filled. It never fails the job: the data being
stale is a chore, not a broken build. docs/release.md has the refresh steps.
"""

import datetime
import json
import pathlib
import sys

MAX_AGE_DAYS = 90
DATA = pathlib.Path(__file__).resolve().parent.parent / "Packages/EmulatorKit/Sources/GameIdentity/Resources/KnownDumps.json"


def message(data, today):
    if not data["games"]:
        return "The bundled No-Intro data is empty. Fill it with `make known-dumps` (docs/release.md)."
    generated = datetime.date.fromisoformat(data["generated"])
    age = (today - generated).days
    if age > MAX_AGE_DAYS:
        return (f"The bundled No-Intro data is from {generated.isoformat()}, {age} days ago. "
                "Refresh it with `make known-dumps` (docs/release.md).")
    return None


def main():
    text = message(json.loads(DATA.read_text(encoding="utf-8")), datetime.date.today())
    relative = DATA.relative_to(DATA.parents[5])
    if text:
        print(f"::warning file={relative},title=No-Intro data refresh due::{text}")
    else:
        print("The bundled No-Intro data is current.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

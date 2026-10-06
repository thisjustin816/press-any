#!/usr/bin/env python3
"""Generate KnownDumps.json from No-Intro's Parent/Clone XML DATs.

Download "Nintendo - Game Boy" and "Nintendo - Game Boy Color" as P/C XML from
DAT-o-MATIC in a browser, with Aftermarket included. A .zip holding one .xml
file works as well as the .xml itself. Never script the download: DAT-o-MATIC
bans clients it takes for bots (docs/decisions.md, "The game database is
No-Intro's").

The output keeps, per dump, what the app can't get from the canonical name: its
SHA-1, size, system, parent, release regions and whether No-Intro marks it a bad
dump. SHA-1 is the key because the P/C XML carries no SHA-256, and the standard
DATs lack it for many Game Boy Color dumps; every entry has a SHA-1. Records sort
by SHA-1, one per line, so the same input gives the same bytes and a refresh's
diff reads line by line. The summary printed at the end, the dumps added, removed
and renamed against the file being replaced, is the pull request description for
a refresh.

Usage: generate-known-dumps.py <gb .xml or .zip> <gbc .xml or .zip> <output .json>
"""

import datetime
import io
import json
import pathlib
import sys
import xml.etree.ElementTree as ElementTree
import zipfile

SOURCE = "No-Intro, DAT-o-MATIC Parent/Clone XML"
SYSTEMS = (("gb", "Nintendo - Game Boy"), ("gbc", "Nintendo - Game Boy Color"))


class DatError(Exception):
    pass


def read_xml(path):
    """The DAT's XML text, from the .xml file or the only .xml inside a .zip."""
    data = pathlib.Path(path).read_bytes()
    if data[:2] == b"PK":
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            names = [name for name in archive.namelist() if name.lower().endswith((".xml", ".dat"))]
            if len(names) != 1:
                raise DatError(f"{path}: expected one .xml or .dat in the archive, found {names}")
            data = archive.read(names[0])
    return data


def parse_dat(path, system, expected_name):
    """The DAT's version and its dumps, each a dict ready for the output file."""
    root = ElementTree.fromstring(read_xml(path))
    header_name = (root.findtext("header/name") or "").strip()
    if not header_name.startswith(expected_name) or header_name[len(expected_name):].strip(" ()").lower() not in ("", "parent-clone"):
        raise DatError(f"{path}: this is the DAT for {header_name!r}, not {expected_name!r}")
    version = (root.findtext("header/version") or "").strip()

    games = root.findall("game") or root.findall("machine")
    by_id = {game.get("id"): game.get("name") for game in games if game.get("id")}
    dumps, missing_hash = [], []
    for game in games:
        name = game.get("name")
        roms = game.findall("rom")
        if len(roms) != 1:
            raise DatError(f"{path}: {name!r} has {len(roms)} ROM entries, expected one")
        sha1 = (roms[0].get("sha1") or "").lower()
        if not sha1:
            missing_hash.append(name)
            continue
        parent = game.get("cloneof")
        if parent is None and game.get("cloneofid"):
            parent = by_id.get(game.get("cloneofid"))
            if parent is None:
                raise DatError(f"{path}: {name!r} names clone-of id {game.get('cloneofid')}, which no game has")
        regions = []
        for release in game.findall("release"):
            region = release.get("region")
            if region and region not in regions:
                regions.append(region)
        dump = {"sha1": sha1, "name": name, "size": int(roms[0].get("size")), "system": system}
        if parent:
            dump["parent"] = parent
        if regions:
            dump["regions"] = regions
        if roms[0].get("status") == "baddump":
            dump["bad"] = True
        dumps.append(dump)

    names = {dump["name"] for dump in dumps} | set(missing_hash)
    for dump in dumps:
        if "parent" in dump and dump["parent"] not in names:
            raise DatError(f"{path}: {dump['name']!r} is a clone of {dump['parent']!r}, which the DAT doesn't list")
    return version, dumps, missing_hash


def generate(gb_path, gbc_path, today=None):
    systems, dumps, skipped = [], [], []
    for (system, name), path in zip(SYSTEMS, (gb_path, gbc_path)):
        version, system_dumps, missing_hash = parse_dat(path, system, name)
        systems.append({"system": system, "dat": name, "version": version, "dumps": len(system_dumps)})
        dumps += system_dumps
        skipped += [f"{system}: {name}" for name in missing_hash]

    seen = {}
    for dump in dumps:
        other = seen.setdefault(dump["sha1"], dump)
        if other is not dump:
            raise DatError(f"{dump['name']!r} and {other['name']!r} have the same SHA-1 {dump['sha1']}")

    return {
        "source": SOURCE,
        "generated": (today or datetime.date.today()).isoformat(),
        "systems": systems,
        "dumps": sorted(dumps, key=lambda dump: dump["sha1"]),
    }, skipped


def summary(new, old, skipped):
    """What changed against the file being replaced, for the pull request."""
    old_dumps = {dump["sha1"]: dump for dump in (old or {}).get("dumps", [])}
    new_dumps = {dump["sha1"]: dump for dump in new["dumps"]}
    added = sorted(new_dumps[key]["name"] for key in new_dumps.keys() - old_dumps.keys())
    removed = sorted(old_dumps[key]["name"] for key in old_dumps.keys() - new_dumps.keys())
    renamed = sorted(
        (old_dumps[key]["name"], new_dumps[key]["name"])
        for key in new_dumps.keys() & old_dumps.keys()
        if old_dumps[key]["name"] != new_dumps[key]["name"]
    )
    lines = ["No-Intro data " + ", ".join(f"{s['dat']} {s['version']} ({s['dumps']} dumps)" for s in new["systems"]) + "."]
    for title, items in (("Added", added), ("Removed", removed)):
        lines.append(f"\n{title}: {len(items)}")
        lines += [f"- {item}" for item in items]
    lines.append(f"\nRenamed: {len(renamed)}")
    lines += [f"- {before} -> {after}" for before, after in renamed]
    if skipped:
        lines.append(f"\nLeft out, no SHA-1 in the DAT: {len(skipped)}")
        lines += [f"- {item}" for item in skipped]
    return "\n".join(lines)


def render(data):
    """JSON with one dump per line: compact, and a refresh's diff shows each dump changed."""
    head = {key: value for key, value in data.items() if key != "dumps"}
    lines = [json.dumps(head, ensure_ascii=False)[:-1] + ', "dumps": [']
    rows = [json.dumps(dump, ensure_ascii=False, separators=(",", ":")) for dump in data["dumps"]]
    lines += [row + ("," if index < len(rows) - 1 else "") for index, row in enumerate(rows)]
    lines.append("]}")
    return "\n".join(lines) + "\n"


def main(argv):
    if len(argv) != 4:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    output = pathlib.Path(argv[3])
    try:
        new, skipped = generate(argv[1], argv[2])
    except (DatError, ElementTree.ParseError, OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    old = json.loads(output.read_text(encoding="utf-8")) if output.exists() else None
    output.write_text(render(new), encoding="utf-8")
    print(summary(new, old, skipped))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

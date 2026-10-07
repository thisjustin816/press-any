#!/usr/bin/env python3
"""Generate KnownDumps.json from No-Intro's DB exports.

Download "Nintendo - Game Boy" and "Nintendo - Game Boy Color" from DAT-o-MATIC's
download page in a browser, using the DB column. A .zip holding the one .xml file
works as well as the .xml itself. Never script the download: DAT-o-MATIC bans
clients it takes for bots (docs/product.md, "No-Intro data").

The DB export lists every file No-Intro knows for a game: its own trusted dumps,
and scene releases it hasn't dumped itself. Each game becomes one record holding
those files' SHA-1s, sizes and bad-dump flags, its parent, and the fields No-Intro
records separately from the name: title, region, languages, development status,
version, and whether it is aftermarket or unlicensed. SHA-1 is the key because
the export lacks SHA-256 for many Game Boy Color files; every file has a SHA-1.

A clone names its parent by number. A clone whose parent the export doesn't
include stands alone and is counted in the summary. Records sort by system and
name, one per line, so the same input gives the same bytes and a refresh's diff
reads game by game. The summary printed at the end, the games added, removed and
renamed against the file being replaced, is the pull request description.

Usage: generate-known-dumps.py <gb .xml or .zip> <gbc .xml or .zip> <output .json>
"""

import datetime
import io
import json
import pathlib
import re
import sys
import xml.etree.ElementTree as ElementTree
import zipfile

SOURCE = "No-Intro, DAT-o-MATIC DB Export"
SYSTEMS = (("gb", "Nintendo - Game Boy"), ("gbc", "Nintendo - Game Boy Color"))


class DatError(Exception):
    pass


def read_export(path):
    """The export's file name and bytes, from the .xml or the only .xml inside a .zip."""
    path = pathlib.Path(path)
    data = path.read_bytes()
    if data[:2] != b"PK":
        return path.name, data
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        names = [name for name in archive.namelist() if name.lower().endswith(".xml")]
        if len(names) != 1:
            raise DatError(f"{path}: expected one .xml in the archive, found {names}")
        return pathlib.PurePath(names[0]).name, archive.read(names[0])


def parse_export(path, system, dat_name):
    """The export's version, its game records, the games with no file, and the clones whose
    parent is missing."""
    file_name, data = read_export(path)
    if not file_name.startswith(f"{dat_name} (DB Export)"):
        raise DatError(f"{path}: {file_name!r} is not the {dat_name!r} DB export")
    # The export puts <header> and <datafile> side by side, so they need one root to parse.
    text = re.sub(r"^\s*<\?xml[^>]*\?>", "", data.decode("utf-8"))
    root = ElementTree.fromstring(f"<export>{text}</export>")
    version = (root.findtext("header/version") or "").strip()
    games = root.findall("datafile/game")
    if not games:
        raise DatError(f"{path}: the export lists no games")

    by_number = {game.find("archive").get("number"): game for game in games}
    records, no_files = {}, []
    for game in games:
        name = game.get("name")
        files, seen = [], set()
        for part in game.findall("source") + game.findall("release"):
            for item in part.findall("file"):
                sha1 = (item.get("sha1") or "").lower()
                if not sha1 or sha1 in seen:
                    continue
                seen.add(sha1)
                entry = {"sha1": sha1, "size": int(item.get("size"))}
                if item.get("bad") == "1":
                    entry["bad"] = True
                files.append(entry)
        if not files:
            no_files.append(name)
            continue
        archive = game.find("archive")
        record = {"name": name, "system": system, "title": archive.get("name") or name}
        # `version` is as No-Intro writes it, a revision ("Rev 1") or a version ("v1.1").
        for key, attribute in (("region", "region"), ("languages", "languages"),
                               ("status", "devstatus"), ("version", "version1")):
            if archive.get(attribute) and archive.get(attribute) != "nolang":
                record[key] = archive.get(attribute)
        if archive.get("aftermarket") == "1":
            record["aftermarket"] = True
        if archive.get("licensed") == "0":
            record["unlicensed"] = True
        record["files"] = sorted(files, key=lambda entry: entry["sha1"])
        records[name] = (record, archive.get("clone"))

    # A parent is the family's root: follow clones of clones, and stop at one that's missing.
    unlinked = []
    for name, (record, clone) in records.items():
        parent, visited = None, {name}
        while clone and clone != "P":
            game = by_number.get(clone)
            if game is None or game.get("name") not in records or game.get("name") in visited:
                break
            parent = game.get("name")
            visited.add(parent)
            clone = records[parent][1]
        if clone and clone != "P" and parent is None:
            unlinked.append(name)
        if parent:
            record["parent"] = parent
    return version, [record for record, _ in records.values()], no_files, unlinked


def generate(gb_path, gbc_path, today=None):
    systems, games, skipped, unlinked = [], [], [], []
    for (system, name), path in zip(SYSTEMS, (gb_path, gbc_path)):
        version, records, no_files, orphans = parse_export(path, system, name)
        systems.append({
            "system": system, "dat": name, "version": version, "games": len(records),
            "files": sum(len(record["files"]) for record in records),
        })
        games += records
        skipped += [f"{system}: {game}" for game in no_files]
        unlinked += [f"{system}: {game}" for game in orphans]

    owners = {}
    for game in games:
        for item in game["files"]:
            other = owners.setdefault(item["sha1"], game)
            if other is not game:
                raise DatError(f"{game['name']!r} and {other['name']!r} share the file {item['sha1']}")

    return {
        "source": SOURCE,
        "generated": (today or datetime.date.today()).isoformat(),
        "systems": systems,
        "games": sorted(games, key=lambda game: (game["system"], game["name"])),
    }, skipped, unlinked


def summary(new, old, skipped, unlinked):
    """What changed against the file being replaced, for the pull request."""
    def by_file(data):
        return {item["sha1"]: f"{game['system']}: {game['name']}"
                for game in (data or {}).get("games", []) for item in game["files"]}
    old_files, new_files = by_file(old), by_file(new)
    old_names, new_names = set(old_files.values()), set(new_files.values())
    renamed = sorted({
        (old_files[key], new_files[key]) for key in new_files.keys() & old_files.keys()
        if old_files[key] != new_files[key]
    })
    renamed_from = {before for before, _ in renamed}
    renamed_to = {after for _, after in renamed}
    added = sorted(new_names - old_names - renamed_to)
    removed = sorted(old_names - new_names - renamed_from)
    lines = ["No-Intro data " + ", ".join(
        f"{s['dat']} {s['version']} ({s['games']} games, {s['files']} files)" for s in new["systems"]
    ) + "."]
    for title, items in (("Added", added), ("Removed", removed)):
        lines.append(f"\n{title}: {len(items)}")
        lines += [f"- {item}" for item in items]
    lines.append(f"\nRenamed: {len(renamed)}")
    lines += [f"- {before} -> {after}" for before, after in renamed]
    if skipped:
        lines.append(f"\nLeft out, no file in the export: {len(skipped)}")
        lines += [f"- {item}" for item in skipped]
    if unlinked:
        lines.append(f"\nClones whose parent the export doesn't include, kept on their own: {len(unlinked)}")
        lines += [f"- {item}" for item in unlinked]
    return "\n".join(lines)


def render(data):
    """JSON with one game per line: compact, and a refresh's diff shows each game changed."""
    head = {key: value for key, value in data.items() if key != "games"}
    lines = [json.dumps(head, ensure_ascii=False)[:-1] + ', "games": [']
    rows = [json.dumps(game, ensure_ascii=False, separators=(",", ":")) for game in data["games"]]
    lines += [row + ("," if index < len(rows) - 1 else "") for index, row in enumerate(rows)]
    lines.append("]}")
    return "\n".join(lines) + "\n"


def main(argv):
    if len(argv) != 4:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    output = pathlib.Path(argv[3])
    try:
        new, skipped, unlinked = generate(argv[1], argv[2])
    except (DatError, ElementTree.ParseError, OSError, ValueError, zipfile.BadZipFile) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    old = json.loads(output.read_text(encoding="utf-8")) if output.exists() else None
    if old is not None and "games" not in old:
        old = None  # the file written before the switch to DB exports
    output.write_text(render(new), encoding="utf-8")
    print(summary(new, old, skipped, unlinked))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

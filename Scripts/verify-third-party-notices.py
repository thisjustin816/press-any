#!/usr/bin/env python3
"""Fails when THIRD_PARTY_NOTICES.md doesn't name the dependency versions the build uses.

Every Swift package pin in Package.resolved must appear in the notices with its version, and
every git submodule with its pinned commit, so updating a dependency can't skip its notice.
"""
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NOTICES = (ROOT / "THIRD_PARTY_NOTICES.md").read_text(encoding="utf-8")
problems = []

for resolved in ROOT.glob("**/Package.resolved"):
    if ".build" in resolved.parts or "Dependencies" in resolved.parts:
        continue
    for pin in json.loads(resolved.read_text(encoding="utf-8")).get("pins", []):
        name = pin["location"].rstrip("/").removesuffix(".git").rsplit("/", 1)[-1]
        version = pin["state"].get("version") or pin["state"]["revision"]
        if name not in NOTICES:
            problems.append(f"{name} ({resolved.relative_to(ROOT)}) has no section in THIRD_PARTY_NOTICES.md")
        elif version not in NOTICES:
            problems.append(f"{name} is pinned at {version}, which THIRD_PARTY_NOTICES.md doesn't record")

# Submodules are read from the tree, so this works in a checkout without them initialized.
gitlinks = subprocess.run(["git", "ls-tree", "-r", "HEAD"], cwd=ROOT, capture_output=True, text=True, check=True)
for line in gitlinks.stdout.splitlines():
    mode, kind, commit, path = line.split(maxsplit=3)
    if kind == "commit" and commit not in NOTICES:
        problems.append(f"submodule {path} is pinned at {commit}, which THIRD_PARTY_NOTICES.md doesn't record")

for problem in problems:
    print(f"error: {problem}", file=sys.stderr)
if problems:
    sys.exit(1)
print("THIRD_PARTY_NOTICES.md records every pinned dependency.")

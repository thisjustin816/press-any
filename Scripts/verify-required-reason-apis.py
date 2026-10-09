#!/usr/bin/env python3
"""Fails when the app's code uses an API Apple lists as needing a reason and the privacy manifest
doesn't declare that category. Apple's list: https://developer.apple.com/documentation/bundleresources/
privacy_manifest_files/describing_use_of_required_reason_api

It reads the source, so it runs anywhere and on every pull request. It can't see inside the
SameBoy core or other binaries, so the archive's privacy report is still checked at release.
"""
import pathlib
import plistlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "App" / "PrivacyInfo.xcprivacy"
# What ships in the app: its own code and the package sources compiled into it.
SOURCES = [ROOT / "App", ROOT / "Packages" / "EmulatorKit" / "Sources"]
EXTENSIONS = {".swift", ".m", ".mm", ".c", ".h"}

CATEGORIES = {
    "NSPrivacyAccessedAPICategoryUserDefaults": r"\b(UserDefaults|NSUserDefaults|AppStorage)\b",
    "NSPrivacyAccessedAPICategoryFileTimestamp": (
        r"\b(creationDate|modificationDate|fileModificationDate|fileCreationDate|creationDateKey"
        r"|contentModificationDateKey|contentAccessDateKey|NSFileCreationDate|NSFileModificationDate"
        r"|getattrlist|fgetattrlist|getattrlistbulk)\b|(?<![A-Za-z0-9_])(stat|fstat|lstat|fstatat)\("
    ),
    "NSPrivacyAccessedAPICategorySystemBootTime": r"\b(systemUptime|mach_absolute_time)\b",
    "NSPrivacyAccessedAPICategoryDiskSpace": (
        r"\b(volumeAvailableCapacityKey|volumeAvailableCapacityForImportantUsageKey"
        r"|volumeAvailableCapacityForOpportunisticUsageKey|volumeTotalCapacityKey|systemFreeSize"
        r"|systemSize|NSFileSystemFreeSize|NSFileSystemSize|statfs|fstatfs|statvfs|fstatvfs)\b"
    ),
    "NSPrivacyAccessedAPICategoryActiveKeyboards": r"\bactiveInputModes\b",
}


def declared():
    with MANIFEST.open("rb") as handle:
        manifest = plistlib.load(handle)
    return {
        entry["NSPrivacyAccessedAPIType"]
        for entry in manifest.get("NSPrivacyAccessedAPITypes", [])
        if entry.get("NSPrivacyAccessedAPITypeReasons")
    }


def uses():
    found = {name: [] for name in CATEGORIES}
    patterns = {name: re.compile(pattern) for name, pattern in CATEGORIES.items()}
    for base in SOURCES:
        for path in sorted(base.rglob("*")):
            if path.suffix not in EXTENSIONS or not path.is_file():
                continue
            for number, line in enumerate(path.read_text(errors="ignore").splitlines(), 1):
                code = line.split("//", 1)[0]
                for name, pattern in patterns.items():
                    if pattern.search(code):
                        found[name].append(f"{path.relative_to(ROOT)}:{number}")
    return found


def main():
    declared_now = declared()
    problems = []
    for name, places in uses().items():
        if places and name not in declared_now:
            problems.append(
                f"{name} is used but not declared with a reason in App/PrivacyInfo.xcprivacy:\n  "
                + "\n  ".join(places[:5])
            )
    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

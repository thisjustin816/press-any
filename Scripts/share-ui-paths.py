#!/usr/bin/env python3
import sys


def requires_share_ui(paths):
    directories = (
        "App/Import/", "App/Library/", "App/Gameplay/", "App/QuickPlay/", "App/Backup/", "App/Settings/",
        "Packages/EmulatorKit/", "Config/", "TestROMs/", "ShareTestSender/", "ShareUITests/", "Scripts/lib/",
    )
    files = {
        "project.yml", "Makefile", ".gitmodules", ".github/workflows/ios-build.yml",
        "Scripts/bootstrap.sh", "Scripts/generate-sameboy-bootroms.sh", "Scripts/test-share-ui.sh",
        "Scripts/share-ui-paths.py", "Scripts/tests/test_share_ui_paths.py",
    }
    return any(path in files or path.startswith(directories) or
               (path.startswith("App/") and path.count("/") == 1) for path in paths)


if __name__ == "__main__":
    print(str(requires_share_ui(sys.stdin.buffer.read().decode().split("\0"))).lower())

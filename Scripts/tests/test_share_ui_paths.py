#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import subprocess
import sys
import unittest

selector = Path(__file__).resolve().parents[1] / "share-ui-paths.py"
spec = importlib.util.spec_from_file_location("share_ui_paths", selector)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ShareUIPathsTests(unittest.TestCase):
    def test_changes_to_a_shared_flow_or_its_build_inputs_run_the_suite(self):
        for path in [
            "App/RootView.swift", "App/AppContainer.swift", "App/PressAnyApp.swift",
            "App/Import/SharedFileInbox.swift", "App/Library/GameDetailView.swift",
            "App/Gameplay/GameplayViewController.swift", "App/QuickPlay/QuickPlayViews.swift",
            "App/Backup/LibraryRestoreView.swift", "App/Settings/ScopedSettingsView.swift",
            "Packages/EmulatorKit/Sources/Importing/ImportCoordinator.swift",
            "Packages/EmulatorKit/Dependencies/SameBoy", "Packages/EmulatorKit/Package.swift",
            "TestROMs/manifest.json", "ShareTestSender/ContentView.swift",
            "ShareUITests/SharedFileUITests.swift", "Scripts/test-share-ui.sh",
            "Scripts/share-ui-paths.py", "Scripts/tests/test_share_ui_paths.py",
            ".github/workflows/ios-build.yml", "Config/PressAny-Info.plist",
            "project.yml", "Makefile",
        ]:
            with self.subTest(path=path):
                self.assertTrue(module.requires_share_ui(["docs/product.md", path]))

    def test_unrelated_changes_do_not_start_a_mac_ui_job(self):
        self.assertFalse(module.requires_share_ui([]))
        self.assertFalse(module.requires_share_ui([
            "docs/product.md", "README.md", "App/Plus/PlusRoadmap.swift",
            "App/Assets.xcassets/AppIcon.appiconset/Contents.json",
            "AppTests/GameplayCaptureTests.swift", ".github/workflows/screenshots.yml",
        ]))

    def test_nul_input_handles_many_files_and_special_characters(self):
        paths = [f"docs/{i}.md" for i in range(500)] + ["App/Import/Renamed\nFlow.swift"]
        result = subprocess.run([sys.executable, str(selector)], input="\0".join(paths).encode() + b"\0",
                                capture_output=True, check=True)
        self.assertEqual(result.stdout.strip(), b"true")
        result = subprocess.run([sys.executable, str(selector)], input=b"docs/Only notes.md\0",
                                capture_output=True, check=True)
        self.assertEqual(result.stdout.strip(), b"false")


if __name__ == "__main__":
    unittest.main()

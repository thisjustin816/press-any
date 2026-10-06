#!/usr/bin/env python3
"""Tests for generate-known-dumps.py against the made-up DB exports beside this file."""

import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest
import zipfile

HERE = pathlib.Path(__file__).resolve().parent
SCRIPT = HERE.parent / "generate-known-dumps.py"
GB = HERE / "known-dumps" / "Nintendo - Game Boy (DB Export) (20261006-105659).xml"
GBC = HERE / "known-dumps" / "Nintendo - Game Boy Color (DB Export) (20261006-110346).xml"

spec = importlib.util.spec_from_file_location("generate_known_dumps", SCRIPT)
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)


class GenerateKnownDumpsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.dir = pathlib.Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def games(self):
        return {game["name"]: game for game in generator.generate(GB, GBC)[0]["games"]}

    def write(self, source, text):
        path = self.dir / source.name
        path.write_text(text, encoding="utf-8")
        return path

    def test_both_systems_become_one_file_sorted_by_system_and_name(self):
        result, skipped, unlinked = generator.generate(GB, GBC)
        self.assertEqual(
            [(s["system"], s["version"], s["games"], s["files"]) for s in result["systems"]],
            [("gb", "20261006-105659", 6, 7), ("gbc", "20261006-110346", 2, 2)],
        )
        keys = [(game["system"], game["name"]) for game in result["games"]]
        self.assertEqual(keys, sorted(keys))
        self.assertEqual(skipped, ["gb: Lost Ledger (USA) (Proto)"])
        self.assertEqual(unlinked, ["gb: Star Seed (World) (Demo) (Aftermarket) (Unl)"])

    def test_a_game_keeps_every_file_once_with_bad_copies_flagged(self):
        games = self.games()
        red = games["Pocket Critters - Red Version (USA, Europe)"]
        # Listed under both its trusted dump and a scene release, the same file counts once.
        self.assertEqual(red["files"], [{"sha1": "aa00000000000000000000000000000000000001", "size": 1048576}])
        aka = games["Pocket Critters - Aka (Japan)"]
        self.assertEqual([item.get("bad", False) for item in aka["files"]], [False, True])
        # A game No-Intro hasn't dumped itself still has its scene release's file.
        self.assertEqual(len(games["Pocket Critters - Rot (Germany)"]["files"]), 1)

    def test_structured_fields_come_from_the_archive_record(self):
        games = self.games()
        red = games["Pocket Critters - Red Version (USA, Europe)"]
        self.assertEqual((red["title"], red["region"], red["languages"]), ("Pocket Critters - Red Version", "USA, Europe", "En"))
        self.assertNotIn("aftermarket", red)
        moon = games["Moon Garden (World) (v1.1) (Aftermarket) (Unl)"]
        self.assertEqual(moon["version"], "v1.1")
        self.assertTrue(moon["aftermarket"])
        self.assertTrue(moon["unlicensed"])
        self.assertNotIn("languages", moon, "nolang is no language")
        self.assertEqual(games["Pocket Critters - Aka (Japan) (Rev 1)"]["version"], "Rev 1")
        self.assertEqual(games["Star Seed (World) (Demo) (Aftermarket) (Unl)"]["status"], "Demo")

    def test_a_parent_is_the_family_root(self):
        games = self.games()
        root = "Pocket Critters - Red Version (USA, Europe)"
        self.assertNotIn("parent", games[root])
        self.assertEqual(games["Pocket Critters - Aka (Japan)"]["parent"], root)
        # A clone of a clone points at the root, so a family is one level deep.
        self.assertEqual(games["Pocket Critters - Aka (Japan) (Rev 1)"]["parent"], root)
        self.assertEqual(games["Pocket Critters - Rot (Germany)"]["parent"], root)
        self.assertNotIn("parent", games["Star Seed (World) (Demo) (Aftermarket) (Unl)"], "a missing parent leaves it alone")
        self.assertEqual(games["Pocket Critters - Crystal Version (Europe) (Fr)"]["system"], "gbc")

    def test_the_same_input_gives_the_same_bytes_one_game_per_line(self):
        output = self.dir / "KnownDumps.json"
        runs = []
        for _ in range(2):
            subprocess.run([sys.executable, SCRIPT, GB, GBC, output], check=True, capture_output=True)
            runs.append(output.read_bytes())
        self.assertEqual(runs[0], runs[1])
        written = json.loads(runs[0])
        self.assertEqual(written["source"], generator.SOURCE)
        self.assertEqual(runs[0].decode().count("\n"), len(written["games"]) + 2)

    def test_a_zip_download_reads_like_the_xml(self):
        archive = self.dir / "gb.zip"
        with zipfile.ZipFile(archive, "w") as zipped:
            zipped.write(GB, GB.name)
        self.assertEqual(generator.generate(archive, GBC)[0], generator.generate(GB, GBC)[0])

    def test_swapped_files_are_refused(self):
        with self.assertRaisesRegex(generator.DatError, "not the 'Nintendo - Game Boy' DB export"):
            generator.generate(GBC, GB)

    def test_a_file_shared_by_two_games_is_refused(self):
        shared = self.write(GBC, GBC.read_text(encoding="utf-8").replace(
            "1200000000000000000000000000000000000012", "1100000000000000000000000000000000000011",
        ))
        with self.assertRaisesRegex(generator.DatError, "share the file"):
            generator.generate(GB, shared)

    def test_the_summary_lists_added_removed_renamed_and_left_out(self):
        new, skipped, unlinked = generator.generate(GB, GBC)
        old = json.loads(json.dumps(new))
        old["games"] = [game for game in old["games"] if not game["name"].startswith("Moon Garden")]
        old["games"].append({"name": "Gone Game (USA)", "system": "gb", "title": "Gone Game",
                             "files": [{"sha1": "ff" * 20, "size": 1}]})
        for game in old["games"]:
            if game["name"] == "Pocket Critters - Aka (Japan)":
                game["name"] = "Pocket Critters - Aka (Japan) (Old Name)"
        text = generator.summary(new, old, skipped, unlinked)
        self.assertIn("Added: 1\n- gb: Moon Garden (World) (v1.1) (Aftermarket) (Unl)", text)
        self.assertIn("Removed: 1\n- gb: Gone Game (USA)", text)
        self.assertIn("Renamed: 1\n- gb: Pocket Critters - Aka (Japan) (Old Name) -> gb: Pocket Critters - Aka (Japan)", text)
        self.assertIn("no file in the export: 1\n- gb: Lost Ledger (USA) (Proto)", text)
        self.assertIn("kept on their own: 1\n- gb: Star Seed", text)


if __name__ == "__main__":
    unittest.main()

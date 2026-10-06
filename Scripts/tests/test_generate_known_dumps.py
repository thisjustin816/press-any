#!/usr/bin/env python3
"""Tests for generate-known-dumps.py against the made-up DATs beside this file."""

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
GB = HERE / "known-dumps" / "gb.xml"
GBC = HERE / "known-dumps" / "gbc.xml"

spec = importlib.util.spec_from_file_location("generate_known_dumps", SCRIPT)
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)


class GenerateKnownDumpsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.dir = pathlib.Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def write(self, name, text):
        path = self.dir / name
        path.write_text(text, encoding="utf-8")
        return path

    def test_both_systems_become_one_sorted_file(self):
        result, skipped = generator.generate(GB, GBC)
        self.assertEqual(
            [(s["system"], s["version"], s["dumps"]) for s in result["systems"]],
            [("gb", "20261006-105659", 4), ("gbc", "20261006-110346", 2)],
        )
        hashes = [dump["sha256"] for dump in result["dumps"]]
        self.assertEqual(hashes, sorted(hashes))
        self.assertTrue(all(h == h.lower() for h in hashes))
        self.assertEqual(skipped, ["gb: Lost Ledger (USA) (Proto)"])

    def test_a_dump_keeps_its_parent_regions_and_size(self):
        dumps = {dump["name"]: dump for dump in generator.generate(GB, GBC)[0]["dumps"]}
        parent = dumps["Pocket Critters - Red Version (USA, Europe)"]
        self.assertNotIn("parent", parent)
        self.assertEqual(parent["regions"], ["USA", "EUR"])
        self.assertEqual(parent["size"], 1048576)
        self.assertEqual(dumps["Pocket Critters - Aka (Japan)"]["parent"], parent["name"])
        # A clone named only by id still finds its parent.
        self.assertEqual(dumps["Pocket Critters - Aka (Japan) (Rev 1)"]["parent"], parent["name"])
        self.assertEqual(dumps["Pocket Critters - Crystal Version (Europe) (Fr)"]["system"], "gbc")
        self.assertNotIn("regions", dumps["Moon Garden (World) (Aftermarket) (Unl)"])

    def test_the_same_input_gives_the_same_bytes(self):
        output = self.dir / "KnownDumps.json"
        runs = []
        for _ in range(2):
            subprocess.run([sys.executable, SCRIPT, GB, GBC, output], check=True, capture_output=True)
            runs.append(output.read_bytes())
        self.assertEqual(runs[0], runs[1])
        self.assertEqual(json.loads(runs[0])["source"], generator.SOURCE)

    def test_a_zip_download_reads_like_the_xml(self):
        archive = self.dir / "gb.zip"
        with zipfile.ZipFile(archive, "w") as zipped:
            zipped.write(GB, "Nintendo - Game Boy (Parent-Clone) (20261006-105659).xml")
        self.assertEqual(generator.generate(archive, GBC)[0], generator.generate(GB, GBC)[0])

    def test_swapped_files_are_refused(self):
        with self.assertRaisesRegex(generator.DatError, "not 'Nintendo - Game Boy'"):
            generator.generate(GBC, GB)

    def test_a_missing_parent_is_refused(self):
        broken = self.write("gb.xml", GB.read_text(encoding="utf-8").replace(
            '<game name="Pocket Critters - Red Version (USA, Europe)" id="0001">',
            '<game name="Renamed Parent" id="0001">',
        ))
        with self.assertRaisesRegex(generator.DatError, "doesn't list"):
            generator.generate(broken, GBC)

    def test_a_repeated_hash_is_refused(self):
        repeated = self.write("gbc.xml", GBC.read_text(encoding="utf-8").replace(
            "1200000000000000000000000000000000000000000000000000000000000012",
            "1100000000000000000000000000000000000000000000000000000000000011",
        ))
        with self.assertRaisesRegex(generator.DatError, "same SHA-256"):
            generator.generate(GB, repeated)

    def test_the_summary_lists_added_removed_and_renamed_dumps(self):
        new, skipped = generator.generate(GB, GBC)
        old = json.loads(json.dumps(new))
        old["dumps"] = [dump for dump in old["dumps"] if not dump["name"].startswith("Moon Garden")]
        old["dumps"].append({"sha256": "ff" * 32, "name": "Gone Game (USA)", "size": 1, "system": "gb"})
        for dump in old["dumps"]:
            if dump["name"] == "Pocket Critters - Aka (Japan)":
                dump["name"] = "Pocket Critters - Aka (Japan) (Old Name)"
        text = generator.summary(new, old, skipped)
        self.assertIn("Added: 1\n- Moon Garden (World) (Aftermarket) (Unl)", text)
        self.assertIn("Removed: 1\n- Gone Game (USA)", text)
        self.assertIn("Renamed: 1\n- Pocket Critters - Aka (Japan) (Old Name) -> Pocket Critters - Aka (Japan)", text)
        self.assertIn("no SHA-256 in the DAT: 1\n- gb: Lost Ledger (USA) (Proto)", text)


if __name__ == "__main__":
    unittest.main()

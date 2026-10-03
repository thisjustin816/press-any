#!/usr/bin/env python3
"""Build a ROM corpus and gbtoolsid's expected output for every ROM in it.

Usage: gbtoolsid-differential-corpus.py <built gbtoolsid checkout> <output directory>

The corpus holds gbtoolsid's own test ROMs plus synthetic ROMs that plant its signatures:
each fixed-address signature alone, each searched signature alone, GBForth's chained
startup, and seeded random combinations including truncated and corrupted plants. For each
ROM it writes <rom>.expected.txt (default mode) and <rom>.expected-strict.txt (-s), holding
gbtoolsid's text output without the "File:" line.
"""

import importlib.util
import pathlib
import random
import re
import shutil
import subprocess
import sys

ROM_SIZE = 0x8000
SEED = 20261003
RANDOM_ROMS = 600

# Load the generator's parsers without leaving a __pycache__ directory in Scripts/.
sys.dont_write_bytecode = True
here = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("gbtoolsid_data", here / "generate-gbtoolsid-data.py")
data = importlib.util.module_from_spec(spec)
spec.loader.exec_module(data)


def load_definitions(src):
    patterns, masked, addresses = {}, {}, {}
    for header in sorted(src.glob("entry_names_*.h")):
        text = data.strip_comments(header.read_text())
        for macro, raw in data.macro_calls(text):
            args = data.split_args(raw)
            if macro == "DEF_PATTERN_STR":
                patterns[args[0]] = list(data.c_string(args[1]).encode("latin-1")) + [0]
            elif macro == "DEF_PATTERN_BUF":
                patterns[args[0]] = data.byte_list(args[1])
            elif macro == "DEF_PATTERN_BUF_MASKED":
                values, mask = data.byte_list(args[2]), data.byte_list(args[3])
                masked[args[0]] = (values, mask + [0] * (len(values) - len(mask)))
            elif macro == "DEF_PATTERN_ADDR":
                addresses[args[0]] = data.int_expression(args[1])
    return patterns, masked, addresses


def load_usage(src):
    code = "\n".join(data.strip_comments(p.read_text()) for p in sorted(src.glob("sig_*.c")))
    at_pairs = sorted(set(re.findall(r"CHECK_PATTERN_AT_ADDR\(\s*(\w+)\s*,\s*(\w+)\s*\)", code)))
    buf = sorted(set(re.findall(r"FIND_PATTERN_BUF\(\s*(\w+)\s*\)", code)))
    noterm = sorted(set(re.findall(r"FIND_PATTERN_STR_NOTERM\(\s*(\w+)\s*\)", code)))
    masked = sorted(set(re.findall(r"FIND_PATTERN_BUF_MASKED\(\s*(\w+)\s*,", code)))
    return at_pairs, buf, noterm, masked


def base_image(rng, kind):
    if kind == "zero":
        return bytearray(ROM_SIZE)
    if kind == "ff":
        return bytearray([0xFF] * ROM_SIZE)
    return bytearray(rng.getrandbits(8) for _ in range(ROM_SIZE))


def plant(image, offset, values):
    if 0 <= offset and offset + len(values) <= len(image):
        image[offset:offset + len(values)] = bytes(values)


def masked_instance(rng, values, mask):
    return [v if m else rng.getrandbits(8) for v, m in zip(values, mask)]


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    root, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    binary = root / "gbtoolsid"
    if not binary.exists():
        sys.exit(f"{binary} not found; build gbtoolsid first")
    patterns, masked_defs, addresses = load_definitions(root / "src")
    at_pairs, buf, noterm, masked = load_usage(root / "src")
    at_pairs = [(p, a) for p, a in at_pairs if p in patterns and a in addresses]
    searched = [(name, "buf") for name in buf if name in patterns] + [(name, "noterm") for name in noterm if name in patterns]

    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    rng = random.Random(SEED)
    roms = {}

    for rom in sorted((root / "test").glob("*.gb*")):
        if rom.stat().st_size > 0:
            roms[f"upstream_{rom.name}"] = rom.read_bytes()

    for kind in ("zero", "ff", "random"):
        for name, addr in at_pairs:
            image = base_image(rng, kind)
            plant(image, addresses[addr], patterns[name])
            roms[f"at_{name}_{kind}.gb"] = bytes(image)

    for kind in ("zero", "random"):
        for name, how in searched:
            image = base_image(rng, kind)
            values = patterns[name][:-1] if how == "noterm" else patterns[name]
            plant(image, rng.randrange(0x150, ROM_SIZE - len(values)), values)
            roms[f"find_{name}_{kind}.gb"] = bytes(image)
        for name in masked:
            image = base_image(rng, kind)
            values, mask = masked_defs[name]
            plant(image, rng.randrange(0x150, ROM_SIZE - len(values)), masked_instance(rng, values, mask))
            roms[f"masked_{name}_{kind}.gb"] = bytes(image)

    # GBForth: startup_2 sits a fixed distance after startup_1, and startup_3 after startup_2.
    for i in range(8):
        image = base_image(rng, "random" if i % 2 else "zero")
        first = rng.randrange(0x150, ROM_SIZE - 0x100)
        second = first + addresses["sig_gbforth_startup_1_next_at"]
        plant(image, first, patterns["sig_gbforth_startup_1"])
        plant(image, second, patterns["sig_gbforth_startup_2"])
        if i < 6:
            plant(image, second + addresses["sig_gbforth_startup_2_next_at"], patterns["sig_gbforth_startup_3"])
        roms[f"chain_gbforth_{i}.gb"] = bytes(image)

    for i in range(RANDOM_ROMS):
        image = base_image(rng, rng.choice(["zero", "ff", "random"]))
        for name, addr in at_pairs:
            if rng.random() < 0.3:
                plant(image, addresses[addr], patterns[name])
        for name, how in searched:
            if rng.random() < 0.12:
                values = patterns[name][:-1] if how == "noterm" else list(patterns[name])
                roll = rng.random()
                if roll < 0.15 and len(values) > 1:
                    values = values[:-1]  # truncated: should usually not match
                elif roll < 0.3:
                    values = list(values)
                    values[rng.randrange(len(values))] ^= 0xFF  # corrupted byte
                plant(image, rng.randrange(0x100, ROM_SIZE - len(values)), values)
        for name in masked:
            if rng.random() < 0.2:
                values, mask = masked_defs[name]
                plant(image, rng.randrange(0x100, ROM_SIZE - len(values)), masked_instance(rng, values, mask))
        if rng.random() < 0.1:
            image = image[: rng.randrange(0x40, ROM_SIZE)]  # short images exercise bounds checks
        roms[f"random_{i:04d}.gb"] = bytes(image)

    for name, content in roms.items():
        path = out / name
        path.write_bytes(content)
        for suffix, flags in (("expected.txt", []), ("expected-strict.txt", ["-s"])):
            result = subprocess.run([str(binary), *flags, str(path)], capture_output=True, text=True, check=True)
            lines = [line for line in result.stdout.splitlines() if not line.startswith("File: ") and line.strip()]
            (out / f"{name}.{suffix}").write_text("\n".join(lines) + "\n")

    print(f"wrote {len(roms)} ROMs with expected gbtoolsid output to {out}")


if __name__ == "__main__":
    main()

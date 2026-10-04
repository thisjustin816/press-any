#!/usr/bin/env python3
"""Writes manifest.json and SHA256SUMS for a built test-roms tree. MIT licensed.

usage: make_manifest.py ROOT   (ROOT holds roms/, patches/ and src/release-tools/roms.json)
Sizes, hashes, system and mapper come from the built files; the script fails if a ROM's header
disagrees with roms.json or if roms/ holds a file roms.json does not list.
"""
import hashlib
import json
import os
import sys

MAPPERS = {
    0x00: "ROM ONLY", 0x01: "MBC1", 0x02: "MBC1+RAM", 0x03: "MBC1+RAM+BATTERY",
    0x19: "MBC5", 0x1A: "MBC5+RAM", 0x1B: "MBC5+RAM+BATTERY",
    0x1C: "MBC5+RUMBLE", 0x1D: "MBC5+RUMBLE+RAM", 0x1E: "MBC5+RUMBLE+RAM+BATTERY",
}


def sha256(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


def header_checksum_ok(rom):
    c = 0
    for b in rom[0x134:0x14D]:
        c = (c - b - 1) & 0xFF
    return c == rom[0x14D]


def main():
    root = sys.argv[1]
    meta = json.load(open(os.path.join(root, "src/release-tools/roms.json")))
    listed = {r["file"] for r in meta["roms"]}
    built = set(os.listdir(os.path.join(root, "roms")))
    if listed != built:
        raise SystemExit(f"roms/ and roms.json disagree: only built {sorted(built - listed)}, only listed {sorted(listed - built)}")
    roms = []
    for r in meta["roms"]:
        path = os.path.join(root, "roms", r["file"])
        data = open(path, "rb").read()
        system = "GBC" if data[0x143] in (0x80, 0xC0) else "GB"
        if system != r["system"]:
            raise SystemExit(f"{r['file']}: header says {system}, roms.json says {r['system']}")
        code = data[0x147]
        roms.append({
            "filename": r["file"], "name": r["name"], "system": system,
            "sdk": r["sdk"], "sdk_version": r["sdk_version"],
            "mapper": MAPPERS.get(code, f"unknown (0x{code:02X})"), "cartridge_type": f"0x{code:02X}",
            "cgb_flag": f"0x{data[0x143]:02X}", "sha256": hashlib.sha256(data).hexdigest(), "size": len(data),
            "header_checksum_ok": header_checksum_ok(data), "hero": r["hero"], "tags": r["tags"],
        })
    patches = []
    for p in meta["patches"]:
        path = os.path.join(root, "patches", p["file"])
        patches.append({
            "filename": p["file"], "format": p["format"], "source": p["source"], "target": p["target"],
            "source_sha256": sha256(os.path.join(root, "roms", p["source"])),
            "target_sha256": sha256(os.path.join(root, "roms", p["target"])),
            "sha256": sha256(path), "size": os.path.getsize(path), "hero": p["hero"], "tags": p["tags"],
        })
    manifest = {"name": "test-roms-v1", "roms": roms, "patches": patches}
    json.dump(manifest, open(os.path.join(root, "manifest.json"), "w"), indent=2)
    open(os.path.join(root, "manifest.json"), "a").write("\n")
    with open(os.path.join(root, "SHA256SUMS"), "w") as f:
        for d in ("patches", "roms"):
            for name in sorted(os.listdir(os.path.join(root, d))):
                f.write(f"{sha256(os.path.join(root, d, name))}  {d}/{name}\n")
    print(f"manifest.json: {len(roms)} ROMs, {len(patches)} patches")


if __name__ == "__main__":
    main()

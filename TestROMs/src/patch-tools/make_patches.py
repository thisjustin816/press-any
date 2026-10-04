#!/usr/bin/env python3
"""Builds IPS and BPS patches that turn one ROM into another, and checks them by applying them.

usage: make_patches.py SOURCE.gb TARGET.gb OUT_BASENAME   (writes OUT_BASENAME.ips and OUT_BASENAME.bps)
MIT licensed. Both ROMs must be the same size; the patches carry only the changed bytes.
"""
import sys
import zlib


def make_ips(src: bytes, dst: bytes) -> bytes:
    assert len(src) == len(dst) and len(dst) < 0xFFFFFF
    out = bytearray(b"PATCH")
    i = 0
    while i < len(dst):
        if src[i] == dst[i]:
            i += 1
            continue
        j = i
        last = i
        # merge changes separated by short runs of unchanged bytes
        while j < len(dst) and (j - i) < 0xFFFF and j - last <= 6:
            if src[j] != dst[j]:
                last = j
            j += 1
        end = last + 1
        chunk = dst[i:end]
        offset = i
        if offset == 0x454F46:  # "EOF" marker clash: start one byte earlier
            offset -= 1
            chunk = dst[offset:end]
        out += offset.to_bytes(3, "big") + len(chunk).to_bytes(2, "big") + chunk
        i = end
    out += b"EOF"
    return bytes(out)


def apply_ips(src: bytes, patch: bytes) -> bytes:
    assert patch[:5] == b"PATCH"
    out = bytearray(src)
    p = 5
    while patch[p:p + 3] != b"EOF":
        offset = int.from_bytes(patch[p:p + 3], "big")
        size = int.from_bytes(patch[p + 3:p + 5], "big")
        p += 5
        if size == 0:  # RLE record
            run = int.from_bytes(patch[p:p + 2], "big")
            data = patch[p + 2:p + 3] * run
            p += 3
        else:
            data = patch[p:p + size]
            p += size
        if offset + len(data) > len(out):
            out.extend(b"\0" * (offset + len(data) - len(out)))
        out[offset:offset + len(data)] = data
    return bytes(out)


def bps_number(n: int) -> bytes:
    out = bytearray()
    while True:
        x = n & 0x7F
        n >>= 7
        if n == 0:
            out.append(0x80 | x)
            return bytes(out)
        out.append(x)
        n -= 1


def make_bps(src: bytes, dst: bytes) -> bytes:
    """Same-size ROMs: SourceRead for unchanged runs, TargetRead for changed bytes."""
    assert len(src) == len(dst)
    out = bytearray(b"BPS1")
    out += bps_number(len(src)) + bps_number(len(dst)) + bps_number(0)
    i = 0
    while i < len(dst):
        j = i
        same = src[i] == dst[i]
        while j < len(dst) and (src[j] == dst[j]) == same:
            j += 1
        length = j - i
        if same:
            out += bps_number(((length - 1) << 2) | 0)  # SourceRead
        else:
            out += bps_number(((length - 1) << 2) | 1)  # TargetRead
            out += dst[i:j]
        i = j
    out += zlib.crc32(src).to_bytes(4, "little") + zlib.crc32(dst).to_bytes(4, "little")
    out += zlib.crc32(bytes(out)).to_bytes(4, "little")
    return bytes(out)


def read_bps_number(data: bytes, p: int):
    n, shift = 0, 1
    while True:
        x = data[p]
        p += 1
        n += (x & 0x7F) * shift
        if x & 0x80:
            return n, p
        shift <<= 7
        n += shift


def apply_bps(src: bytes, patch: bytes) -> bytes:
    assert patch[:4] == b"BPS1"
    assert zlib.crc32(patch[:-4]) == int.from_bytes(patch[-4:], "little"), "patch crc"
    p = 4
    src_size, p = read_bps_number(patch, p)
    dst_size, p = read_bps_number(patch, p)
    meta, p = read_bps_number(patch, p)
    p += meta
    assert src_size == len(src) and zlib.crc32(src) == int.from_bytes(patch[-12:-8], "little"), "source crc"
    out = bytearray()
    src_rel = dst_rel = 0
    end = len(patch) - 12
    while p < end:
        v, p = read_bps_number(patch, p)
        action, length = v & 3, (v >> 2) + 1
        if action == 0:
            out += src[len(out):len(out) + length]
        elif action == 1:
            out += patch[p:p + length]
            p += length
        else:
            off, p = read_bps_number(patch, p)
            off = -(off >> 1) if off & 1 else off >> 1
            if action == 2:
                src_rel += off
                out += src[src_rel:src_rel + length]
                src_rel += length
            else:
                dst_rel += off
                for _ in range(length):
                    out.append(out[dst_rel])
                    dst_rel += 1
    assert len(out) == dst_size and zlib.crc32(bytes(out)) == int.from_bytes(patch[-8:-4], "little"), "target crc"
    return bytes(out)


def main() -> None:
    src_path, dst_path, base = sys.argv[1:4]
    src, dst = open(src_path, "rb").read(), open(dst_path, "rb").read()
    ips, bps = make_ips(src, dst), make_bps(src, dst)
    assert apply_ips(src, ips) == dst, "IPS round trip failed"
    assert apply_bps(src, bps) == dst, "BPS round trip failed"
    open(base + ".ips", "wb").write(ips)
    open(base + ".bps", "wb").write(bps)
    print(f"{base}.ips {len(ips)} bytes, {base}.bps {len(bps)} bytes, both verified")


if __name__ == "__main__":
    main()

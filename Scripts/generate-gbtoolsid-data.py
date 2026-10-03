#!/usr/bin/env python3
"""Generate GBToolsIDData.swift from a gbtoolsid checkout.

The signature byte patterns, addresses and display strings live in gbtoolsid's
src/entry_names_*.h headers as DEF_* macros. This script reads those macros and
writes them as Swift constants, keeping the upstream identifiers so the ported
logic can be compared with the C source line by line.

Usage: generate-gbtoolsid-data.py <gbtoolsid checkout> <output .swift file>
"""

import ast
import pathlib
import re
import subprocess
import sys

MACRO = re.compile(r"\b(DEF_NAME_STR|DEF_PATTERN_STR|DEF_PATTERN_ADDR|DEF_PATTERN_BUF_MASKED|DEF_PATTERN_BUF)\s*\(")
C_STRING_ESCAPES = {"n": "\n", "t": "\t", "\\": "\\", '"': '"', "'": "'", "0": "\0"}


def strip_comments(text):
    """Remove // and /* */ comments without touching string literals."""
    out, i, n = [], 0, len(text)
    while i < n:
        if text.startswith("//", i):
            while i < n and text[i] != "\n":
                i += 1
        elif text.startswith("/*", i):
            end = text.find("*/", i + 2)
            i = n if end < 0 else end + 2
        elif text[i] == '"':
            j = i + 1
            while j < n and text[j] != '"':
                j += 2 if text[j] == "\\" else 1
            out.append(text[i:j + 1])
            i = j + 1
        else:
            out.append(text[i])
            i += 1
    return "".join(out)


def macro_calls(text):
    """Yield (macro, raw argument text) for every top-level DEF_* call."""
    for match in MACRO.finditer(text):
        depth, j = 1, match.end()
        while depth:
            ch = text[j]
            if ch == '"':
                j += 1
                while text[j] != '"':
                    j += 2 if text[j] == "\\" else 1
            elif ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
            j += 1
        yield match.group(1), text[match.end():j - 1]


def split_args(args):
    """Split on top-level commas, keeping AR_ARGS(...) groups and strings intact."""
    parts, depth, current, i = [], 0, [], 0
    while i < len(args):
        ch = args[i]
        if ch == '"':
            j = i + 1
            while args[j] != '"':
                j += 2 if args[j] == "\\" else 1
            current.append(args[i:j + 1])
            i = j + 1
            continue
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append("".join(current).strip())
            current = []
        else:
            current.append(ch)
        i += 1
    parts.append("".join(current).strip())
    return parts


def c_string(literal):
    """Decode one or more adjacent C string literals."""
    pieces = re.findall(r'"((?:[^"\\]|\\.)*)"', literal)
    if not pieces:
        raise ValueError(f"not a string literal: {literal!r}")
    raw = "".join(pieces)
    out, i = [], 0
    while i < len(raw):
        if raw[i] == "\\":
            nxt = raw[i + 1]
            if nxt == "x":
                hex_digits = re.match(r"[0-9A-Fa-f]{1,2}", raw[i + 2:]).group(0)
                out.append(chr(int(hex_digits, 16)))
                i += 2 + len(hex_digits)
                continue
            if nxt not in C_STRING_ESCAPES:
                raise ValueError(f"unsupported escape \\{nxt} in {literal!r}")
            out.append(C_STRING_ESCAPES[nxt])
            i += 2
        else:
            out.append(raw[i])
            i += 1
    return "".join(out)


def int_expression(text):
    """Evaluate an address such as 0x0150 or (6 + 1): integer literals, + - * and parentheses only."""
    def evaluate(node):
        if isinstance(node, ast.Expression):
            return evaluate(node.body)
        if isinstance(node, ast.Constant) and type(node.value) is int:
            return node.value
        if isinstance(node, ast.BinOp) and isinstance(node.op, (ast.Add, ast.Sub, ast.Mult)):
            left, right = evaluate(node.left), evaluate(node.right)
            return left + right if isinstance(node.op, ast.Add) else left - right if isinstance(node.op, ast.Sub) else left * right
        raise ValueError(f"unsupported address expression: {text!r}")
    return evaluate(ast.parse(text.strip(), mode="eval"))


def byte_list(arg):
    inner = re.sub(r"\\\s*\n", " ", arg).strip()
    if inner.startswith("AR_ARGS("):
        inner = inner[len("AR_ARGS("):-1]
    values = [v.strip() for v in inner.split(",") if v.strip()]
    result = [int(v, 0) for v in values]
    if any(v < 0 or v > 0xFF for v in result):
        raise ValueError(f"byte out of range in {arg!r}")
    return result


def swift_bytes(values):
    return "[" + ", ".join(f"0x{v:02X}" for v in values) + "]"


def swift_pattern(name, values):
    return f'GBToolsIDPattern(name: "{name}", bytes: {swift_bytes(values)})'


def swift_string(value):
    escaped = value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")
    return '"' + escaped + '"'


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    root = pathlib.Path(sys.argv[1])
    output = pathlib.Path(sys.argv[2])
    commit = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
    describe = subprocess.check_output(["git", "-C", str(root), "describe", "--tags", "--always"], text=True).strip()

    lines, seen = [], set()

    def declare(name, swift_type, value):
        if name in seen:
            raise ValueError(f"duplicate definition of {name}")
        seen.add(name)
        lines.append(f"    static let {name}: {swift_type} = {value}")

    for header in sorted((root / "src").glob("entry_names_*.h")):
        lines.append(f"\n    // MARK: {header.name}\n")
        text = strip_comments(header.read_text())
        for macro, raw in macro_calls(text):
            args = split_args(raw)
            if macro == "DEF_NAME_STR":
                declare(args[0], "String", swift_string(c_string(args[1])))
            elif macro == "DEF_PATTERN_STR":
                # Keep the terminator: the C macros size every pattern with sizeof(), and
                # FIND_PATTERN_STR_NOTERM is what drops the last byte.
                declare(args[0], "GBToolsIDPattern", swift_pattern(args[0], list(c_string(args[1]).encode("latin-1")) + [0]))
            elif macro == "DEF_PATTERN_ADDR":
                declare(args[0], "Int", f"0x{int_expression(args[1]):04X}")
            elif macro == "DEF_PATTERN_BUF":
                declare(args[0], "GBToolsIDPattern", swift_pattern(args[0], byte_list(args[1])))
            elif macro == "DEF_PATTERN_BUF_MASKED":
                pattern, mask = byte_list(args[2]), byte_list(args[3])
                if len(mask) > len(pattern):
                    raise ValueError(f"mask longer than pattern for {args[0]}")
                # C zero-fills a mask declared with sizeof(pattern) but given fewer values.
                mask += [0] * (len(pattern) - len(mask))
                declare(args[0], "GBToolsIDMaskedPattern",
                        f'GBToolsIDMaskedPattern(name: "{args[0]}", bytes: {swift_bytes(pattern)}, mask: {swift_bytes(mask)})')

    header_comment = f"""// Generated by Scripts/generate-gbtoolsid-data.py. Do not edit.
// Source: https://github.com/bbbbbr/gbtoolsid {describe} ({commit}), src/entry_names_*.h
// gbtoolsid is released into the public domain under the Unlicense.
// Identifiers keep their upstream C names so the port can be compared with the C source.

// swiftlint:disable all
enum GBToolsIDData {{
    static let upstreamRevision = "{describe}"
    static let upstreamCommit = "{commit}"
"""
    output.write_text(header_comment + "\n".join(lines) + "\n}\n")
    print(f"wrote {len(seen)} definitions from {describe} to {output}")


if __name__ == "__main__":
    main()

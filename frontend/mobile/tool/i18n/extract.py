#!/usr/bin/env python3
"""استخراجِ رشته‌های مبدأِ ترجمه از سورسِ Flutter.

دو منبع را می‌خوانَد:
 1. آرگومانِ literalِ `tr('...')` — حالتِ عادی.
 2. رشته‌های فارسیِ داخلِ اعلان‌های `...Src` — نگاشت‌های ثابتِ برچسب که در زمانِ
    اجرا با `tr(v)` ترجمه می‌شوند و آرگومانشان literal نیست.

خروجی: `build/sources.json` = {"strings": [...], "counts": {...}}
"""
import json
import os
import re
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", "..", "lib"))
BUILD = os.path.join(HERE, "data")

STR = re.compile(r"""(?:r?'((?:\\.|[^'\\])*)'|r?"((?:\\.|[^"\\])*)")""", re.S)
FA = re.compile(r"[\u0600-\u06FF]")
DECL = re.compile(r"[A-Za-z_][A-Za-z0-9_]*Src\s*=")
OPEN = {"{": "}", "[": "]", "(": ")"}

UNESCAPE = {
    "\\n": "\n", "\\t": "\t", "\\'": "'", '\\"': '"',
    "\\\\": "\\", "\\$": "$",
}


def unescape(s: str) -> str:
    out, i = [], 0
    while i < len(s):
        if s[i] == "\\" and i + 1 < len(s):
            pair = s[i:i + 2]
            if pair in UNESCAPE:
                out.append(UNESCAPE[pair])
                i += 2
                continue
            if pair == "\\u":
                m = re.match(r"\\u\{([0-9a-fA-F]+)\}|\\u([0-9a-fA-F]{4})", s[i:])
                if m:
                    out.append(chr(int((m.group(1) or m.group(2)), 16)))
                    i += m.end()
                    continue
        out.append(s[i])
        i += 1
    return "".join(out)


def _read_adjacent(src: str, start: int):
    """literal (به‌همراهِ literalهای مجاور، که Dart در کامپایل می‌چسبانَد)."""
    m = STR.match(src, start)
    if not m:
        return None, start
    parts = []
    while m:
        raw = m.group(1) if m.group(1) is not None else m.group(2)
        parts.append(raw if src[m.start()] == "r" else unescape(raw))
        end = m.end()
        k = end
        while k < len(src) and src[k] in " \t\n\r":
            k += 1
        nxt = STR.match(src, k) if k < len(src) else None
        if nxt:
            m = nxt
        else:
            return "".join(parts), end
    return "".join(parts), start


def tr_literals(src: str):
    for m in re.finditer(r"(?<![A-Za-z0-9_.$])tr\(", src):
        j = m.end()
        while j < len(src) and src[j] in " \t\n\r":
            j += 1
        val, _ = _read_adjacent(src, j)
        yield val, m.start()


def block_after(src: str, start: int) -> str:
    i, depth = start, 0
    while i < len(src):
        c = src[i]
        if c in "'\"":
            m = STR.match(src, i)
            if m:
                i = m.end()
                continue
        if c in OPEN:
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c == ";" and depth <= 0:
            return src[start:i]
        i += 1
    return src[start:]


def src_map_literals(body: str):
    i = 0
    while i < len(body):
        if body[i] not in "'\"" and not (
            body[i] == "r" and i + 1 < len(body) and body[i + 1] in "'\""
        ):
            i += 1
            continue
        val, end = _read_adjacent(body, i)
        if val is None:
            i += 1
            continue
        yield val
        i = end


def main():
    counts, dynamic = Counter(), []
    for dirpath, _dirs, files in os.walk(ROOT):
        for f in sorted(files):
            if not f.endswith(".dart"):
                continue
            p = os.path.join(dirpath, f)
            rel = os.path.relpath(p, ROOT)
            src = open(p, encoding="utf-8").read()
            for val, pos in tr_literals(src):
                if val is None:
                    dynamic.append(f"{rel}:{src.count(chr(10), 0, pos) + 1}")
                else:
                    counts[val] += 1
            for m in DECL.finditer(src):
                for val in src_map_literals(block_after(src, m.end())):
                    if FA.search(val) and val not in counts:
                        counts[val] = 1

    strings = sorted(counts, key=lambda s: (-counts[s], s))
    os.makedirs(BUILD, exist_ok=True)
    json.dump({"strings": strings, "counts": dict(counts)},
              open(os.path.join(BUILD, "sources.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print(f"distinct={len(strings)} calls={sum(counts.values())} "
          f"dynamic-args={len(dynamic)}")


if __name__ == "__main__":
    sys.exit(main())

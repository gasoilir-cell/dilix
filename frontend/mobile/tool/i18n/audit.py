#!/usr/bin/env python3
"""ممیزیِ نشتِ i18n: رشته‌های فارسیِ کاربر-محور که از `tr()` نمی‌گذرند.

«سیم‌کشی‌شده» ≠ «بی‌نشت» — یک صفحه می‌تواند `tr()` داشته باشد و هم‌زمان ده‌ها
توست/placeholder/tooltipِ فارسیِ هاردکد. این اسکریپت همان‌ها را پیدا می‌کند.

کامنت‌ها نادیده گرفته می‌شوند. رشته‌های داخلِ `tr(...)` و داخلِ اعلان‌های
`...Src` (که در زمانِ اجرا با `tr(v)` ترجمه می‌شوند) نشت حساب نمی‌شوند.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from extract import DECL, STR, block_after, unescape  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, "..", "..", "lib"))
FA = re.compile(r"[\u0600-\u06FF]")

# نشت‌های عمدی و درست:
#  - جدولِ ترجمهٔ تولیدشده و جدولِ جداگانهٔ آنبوردینگ
#  - نامِ بومیِ زبان‌ها (endonym) که هرگز نباید ترجمه شود
IGNORE_FILES = {
    "l10n/translations.dart",
    "features/onboarding/onboarding_strings.dart",
}
# پیامِ assert برای توسعه‌دهنده است، نه کاربر
DEV_ASSERT = re.compile(r"assert\(")


def strip_comments(src: str) -> str:
    """کامنت‌ها را با فاصله جایگزین می‌کند تا موقعیتِ کاراکترها حفظ شود."""
    out = list(src)
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c in "'\"":
            m = STR.match(src, i)
            if m:
                i = m.end()
                continue
        if c == "/" and i + 1 < n and src[i + 1] in "/*":
            if src[i + 1] == "/":
                j = src.find("\n", i)
                j = n if j < 0 else j
            else:
                j = src.find("*/", i)
                j = n if j < 0 else j + 2
            for k in range(i, j):
                if out[k] != "\n":
                    out[k] = " "
            i = j
            continue
        i += 1
    return "".join(out)


def covered_spans(src: str):
    """بازه‌هایی که literalِ فارسی در آن‌ها مجاز است."""
    spans = []
    for m in re.finditer(r"(?<![A-Za-z0-9_.$])tr\(", src):
        depth, i = 1, m.end()
        while i < len(src) and depth:
            c = src[i]
            if c in "'\"":
                sm = STR.match(src, i)
                if sm:
                    i = sm.end()
                    continue
            depth += (c == "(") - (c == ")")
            i += 1
        spans.append((m.end(), i))
    for m in DECL.finditer(src):
        body = block_after(src, m.end())
        spans.append((m.end(), m.end() + len(body)))
    return spans


def main():
    leaks = []
    for dirpath, _dirs, files in os.walk(ROOT):
        for f in sorted(files):
            if not f.endswith(".dart"):
                continue
            p = os.path.join(dirpath, f)
            rel = os.path.relpath(p, ROOT).replace(os.sep, "/")
            if rel in IGNORE_FILES:
                continue
            src = strip_comments(open(p, encoding="utf-8").read())
            spans = covered_spans(src)
            for sm in STR.finditer(src):
                raw = sm.group(1) if sm.group(1) is not None else sm.group(2)
                s = unescape(raw)
                if not FA.search(s):
                    continue
                pos = sm.start()
                if any(a <= pos < b for a, b in spans):
                    continue
                line = src.count("\n", 0, pos) + 1
                line_start = src.rfind("\n", 0, pos) + 1
                if DEV_ASSERT.search(src[max(0, line_start - 200):pos]):
                    continue
                leaks.append({"file": rel, "line": line, "text": s})

    json.dump(leaks, open(os.path.join(HERE, "data", "leaks.json"), "w",
                          encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"leaks={len(leaks)}")
    per = {}
    for l in leaks:
        per[l["file"]] = per.get(l["file"], 0) + 1
    for f, c in sorted(per.items(), key=lambda kv: -kv[1]):
        print(f"  {c:4d}  {f}")
    return 1 if leaks else 0


if __name__ == "__main__":
    sys.exit(main())

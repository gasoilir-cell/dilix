#!/usr/bin/env python3
"""ممیزیِ خودکارِ کیفیتِ جدولِ ترجمه.

به‌جای نمونه‌برداریِ دستی، الگوهای مشکوک را سیستماتیک پیدا می‌کند:

  latin-in-nonlatin  خروجیِ زبانِ غیرِ لاتین که واژهٔ لاتین دارد → معمولاً
                     بخشی ترجمه‌نشده مانده (نامِ برند استثناست).
  persian-residue    خروجیِ غیرِ فارسی که هنوز حروفِ فارسیِ خاص دارد (پ چ ژ گ)
                     → ترجمه نگرفته است.
  length-blowup      خروجیِ خیلی بلندتر از مبدأ → مترجم توضیح اضافه کرده.
  empty/ident        خروجیِ خالی یا برابرِ مبدأ.
  placeholder        `{0}` جابه‌جا یا گم‌شده.
  newline-lost       شمارشِ `\\n` با مبدأ نمی‌خوانَد → متنِ چندسطری یک‌سطری شده.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from curated import ALL as LANGS, BRANDS  # noqa: E402

DART = os.path.normpath(os.path.join(HERE, "..", "..", "lib", "l10n",
                                     "translations.dart"))
LATIN = re.compile(r"[A-Za-z]{3,}")
# حروفِ ویژهٔ فارسی/اردو که در عربیِ استاندارد نیستند
PERSIAN_ONLY = re.compile(r"[پچژگ]")
PLACEHOLDER = re.compile(r"\{(\d+)\}")
NON_LATIN_LANGS = {"ru", "zh", "hi", "ar", "ur", "ps"}
# واژه‌های لاتینی که عمداً ترجمه نمی‌شوند
ALLOW_LATIN = re.compile(
    r"\b(Dilix|Earth|ID|Snapp|Bar|QR|SMS|OTP|KYC|KYB|API|PSP|IRR|USD|EUR|AED|"
    r"TRY|RUB|CNY|INR|GBP|SAR|CAD|AUD|E2EE|WebRTC|eSIM|SVG|PDF|GPS|UI|URL|"
    r"Toman|Tomans|tomans|Google|Apple|Microsoft|Facebook|Stripe|PayPal)\b")


def parse_tables(path: str):
    src = open(path, encoding="utf-8").read()
    tables = {}
    for lang in LANGS:
        m = re.search(r"  '%s': <String, String>\{\n(.*?)\n  \},\n" % lang,
                      src, re.S)
        if not m:
            continue
        d = {}
        for line in m.group(1).split("\n"):
            mm = re.match(r"    '((?:\\.|[^'\\])*)': '((?:\\.|[^'\\])*)',$",
                          line)
            if mm:
                d[unescape(mm.group(1))] = unescape(mm.group(2))
        tables[lang] = d
    return tables


def unescape(s: str) -> str:
    return (s.replace("\\\\", "\x00").replace("\\'", "'").replace("\\$", "$")
             .replace("\\n", "\n").replace("\\r", "\r").replace("\\t", "\t")
             .replace("\x00", "\\"))


def main():
    tables = parse_tables(DART)
    brand_values = {v for row in BRANDS.values() for v in row.values()}
    findings = []

    for lang, table in tables.items():
        for src, val in table.items():
            if not val.strip():
                findings.append(("empty", lang, src, val))
                continue
            if val == src:
                findings.append(("identical", lang, src, val))
            if set(PLACEHOLDER.findall(src)) != set(PLACEHOLDER.findall(val)):
                findings.append(("placeholder", lang, src, val))
            if lang in NON_LATIN_LANGS and val not in brand_values:
                stripped = ALLOW_LATIN.sub("", val)
                if LATIN.search(stripped):
                    findings.append(("latin-in-nonlatin", lang, src, val))
            if lang not in ("fa",) and lang not in ("ur", "ps"):
                if PERSIAN_ONLY.search(val):
                    findings.append(("persian-residue", lang, src, val))
            if len(val) > max(60, len(src) * 3.5):
                findings.append(("length-blowup", lang, src, val))
            if val.count("\n") != src.count("\n"):
                # مترجم خطِ جدید را بی‌سروصدا حذف می‌کند و متنِ دوسطری
                # یک‌سطری می‌شود؛ چیدمانِ «حالتِ خالی» به هم می‌ریزد.
                findings.append(("newline-lost", lang, src, val))

    by_kind = {}
    for kind, lang, src, val in findings:
        by_kind.setdefault(kind, []).append((lang, src, val))

    print(f"entries={sum(len(t) for t in tables.values())} "
          f"findings={len(findings)}")
    for kind, items in sorted(by_kind.items(), key=lambda kv: -len(kv[1])):
        print(f"\n── {kind}: {len(items)}")
        for lang, src, val in items[:12]:
            print(f"   [{lang}] {src[:44]!r}\n        → {val[:64]!r}")

    json.dump([{"kind": k, "lang": l, "src": s, "val": v}
               for k, l, s, v in findings],
              open(os.path.join(HERE, "data", "sanity.json"), "w",
                   encoding="utf-8"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()

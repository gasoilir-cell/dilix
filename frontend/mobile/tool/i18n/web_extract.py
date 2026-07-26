#!/usr/bin/env python3
"""بیرون‌کشیدنِ `DICT` از i18nِ اپِ وب به JSON — حافظهٔ ترجمهٔ حرفه‌ای.

اپِ وب چند صد کلید را با ترجمهٔ انسانی دارد؛ همان‌ها بهترین منبع برای موبایل‌اند
و کیفیتشان از ترجمهٔ ماشینی بالاتر است. این مرحله قبلاً دستی بود، پس خروجی‌اش
با پاک‌شدنِ پوشهٔ موقت از بین می‌رفت؛ حالا مرحلهٔ رسمیِ خط‌لوله است و نتیجه
(`data/web_dict.json`) در مخزن نگه داشته می‌شود تا بازتولید به فایلِ بیرونی
وابسته نباشد.

TS را کامل تجزیه نمی‌کنیم ولی رشته‌ها را کاراکتربه‌کاراکتر می‌خوانیم؛ چند زوجِ
`lang: "…"` در یک خط و `\\"` یا `,` داخلِ متن نباید تجزیه را بشکند.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "data")
DEFAULT_SRC = os.path.normpath(
    os.path.join(HERE, "..", "..", "..", "..", ".noqte", "work", "i18n.ts"))

IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
ESCAPES = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "\\": "\\", "'": "'"}


def read_string(s: str, i: int):
    """رشتهٔ دونقل‌قولی را از موقعیتِ `i` می‌خوانَد و مقدار و موقعیتِ بعد را می‌دهد."""
    assert s[i] == '"'
    i += 1
    buf = []
    while s[i] != '"':
        if s[i] == "\\":
            buf.append(ESCAPES.get(s[i + 1], s[i + 1]))
            i += 2
        else:
            buf.append(s[i])
            i += 1
    return "".join(buf), i + 1


def skip(s: str, i: int, chars: str = " \t\r\n,"):
    """فاصله/کاما و کامنت‌های TS را رد می‌کند (دیکشنری بخش‌بندیِ کامنت‌دار دارد)."""
    while i < len(s):
        if s[i] in chars:
            i += 1
        elif s.startswith("//", i):
            i = s.find("\n", i)
            if i < 0:
                return len(s)
        elif s.startswith("/*", i):
            end = s.find("*/", i)
            i = len(s) if end < 0 else end + 2
        else:
            break
    return i


def parse(s: str, i: int):
    """بدنهٔ `DICT` را از بعدِ `{` تا `}`ِ متناظر می‌خوانَد."""
    out = {}
    while True:
        i = skip(s, i)
        if s[i] == "}":
            return out, i + 1
        if s[i] != '"':  # کلیدِ بی‌نقل‌قول یا ساختارِ ناشناخته → رد شو
            return out, i
        key, i = read_string(s, i)
        i = skip(s, i, " \t\r\n:")
        if s[i] != "{":
            return out, i
        i += 1
        row = {}
        while True:
            i = skip(s, i)
            if s[i] == "}":
                i += 1
                break
            m = IDENT.match(s, i)
            if not m:
                return out, i
            lang = m.group(0)
            i = skip(s, m.end(), " \t\r\n:")
            if s[i] != '"':
                return out, i
            row[lang], i = read_string(s, i)
        if row:
            out[key] = row


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_SRC
    if not os.path.exists(src):
        raise SystemExit(f"i18nِ وب پیدا نشد: {src}")
    text = open(src, encoding="utf-8").read()
    m = re.search(r"DICT[^=]*=\s*\{", text)
    if not m:
        raise SystemExit("تعریفِ DICT در فایل نیست")

    out, _ = parse(text, m.end())
    os.makedirs(DATA, exist_ok=True)
    json.dump(out, open(os.path.join(DATA, "web_dict.json"), "w",
                        encoding="utf-8"), ensure_ascii=False)
    full = sum(1 for r in out.values() if len(r) >= 10)
    print(f"keys={len(out)} ten-language={full}  ← {src}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""تطبیقِ رشته‌های موبایل با دیکشنریِ ۱۰زبانهٔ اپِ وب (حافظهٔ ترجمهٔ حرفه‌ای).

تطبیق **فقط املایی** است، نه معنایی: نیم‌فاصله، کسرهٔ اضافه، همزهٔ روی «ه»،
فاصله و نقطه‌گذاریِ پایانی نادیده گرفته می‌شوند، ولی **دنبالهٔ حروف باید عیناً
یکی باشد**. تطبیقِ تقریبی عمداً کنار گذاشته شد: «ثبت‌نشده» و «ثبت‌شده» ۹۳٪
شبیه‌اند و قبولشان یعنی وارونه‌کردنِ معنا.

ورودی: `build/web_dict.json` (خروجیِ JSONِ `DICT` اپِ وب)
خروجی: `build/web_hits.json` = {source: {lang: value}}
"""
import json
import os
import re
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
BUILD = os.path.join(HERE, "data")

WEB_LANGS = ["en", "ar", "tr", "ru", "zh", "hi", "es", "fr", "de"]
DIACRITICS = re.compile(r"[\u064B-\u0652\u0654\u0670\u0640]")
ZWNJ = "\u200c"


def norm(s: str) -> str:
    s = unicodedata.normalize("NFC", s)
    s = s.replace(ZWNJ, " ").replace("\u200f", "").replace("\u200e", "")
    s = s.replace("ي", "ی").replace("ك", "ک").replace("ۀ", "ه").replace("ة", "ه")
    s = s.replace("أ", "ا").replace("إ", "ا").replace("آ", "ا").replace("ٱ", "ا")
    s = s.replace("ؤ", "و").replace("ئ", "ی")
    s = DIACRITICS.sub("", s).replace("\u00a0", " ")
    s = s.replace("٫", ".").replace("،", ",").replace("؛", ";").replace("؟", "?")
    return re.sub(r"\s+", " ", s).strip(" .:,;!?\u2026").lower()


def variants(s: str):
    """صورت‌های املاییِ هم‌ارز — همه با دنبالهٔ حروفِ یکسان."""
    base = norm(s)
    return {base, base.replace(" ", "")}


def main():
    web = json.load(open(os.path.join(BUILD, "web_dict.json"), encoding="utf-8"))
    sources = json.load(open(os.path.join(BUILD, "sources.json"),
                             encoding="utf-8"))["strings"]

    tm = {}
    for row in web.values():
        fa = row.get("fa")
        if not fa or not all(row.get(l) for l in WEB_LANGS):
            continue
        for v in variants(fa):
            if not v:
                continue
            prev = tm.get(v)
            # کوتاه‌ترین مبدأ برنده است: کلیدِ عمومی‌تر، نه جملهٔ خاص
            if prev is None or len(fa) < len(prev["fa"]):
                tm[v] = row

    hits = {}
    for s in sources:
        for v in variants(s):
            if v and v in tm:
                hits[s] = {l: tm[v][l] for l in WEB_LANGS}
                break

    json.dump(hits, open(os.path.join(BUILD, "web_hits.json"), "w",
                         encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"sources={len(sources)} professional-hits={len(hits)} "
          f"needs-mt={len(sources) - len(hits)}")


if __name__ == "__main__":
    main()

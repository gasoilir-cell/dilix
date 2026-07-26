#!/usr/bin/env python3
"""ساختِ فایل‌های کارِ ترجمه: چه رشته‌ای با کدام حالت ترجمه شود.

- رشته‌هایی که دیکشنریِ حرفه‌ایِ وب پوشش داده، فقط برای `ur`/`ps` کار می‌خواهند
  (وب این دو را ندارد).
- برچسبِ کوتاه (≤۴ واژه، بدونِ نقطه‌گذاریِ پایانی) → حالتِ زمینه‌دار.
- بقیه → حالتِ ساده.
- رشتهٔ بدونِ حرف (فقط نقطه‌گذاری/عدد) اصلاً ترجمه نمی‌شود؛ در `curated.py`
  دستی نگاشت شده، چون فاصلهٔ انتهایی‌اش معنادار است.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from curated import ALL as LANGS  # noqa: E402

BUILD = os.path.join(HERE, "data")
WEB_LANGS = {"en", "ar", "tr", "ru", "zh", "hi", "es", "fr", "de"}
LETTER = re.compile(r"[^\W\d_]", re.UNICODE)
ENDS = (".", "!", "؟", "?", "…", ":")


def is_short_label(s: str) -> bool:
    return (len(re.findall(r"\S+", s)) <= 4
            and not s.rstrip().endswith(ENDS)
            and "\n" not in s)


def main():
    sources = json.load(open(os.path.join(BUILD, "sources.json"),
                             encoding="utf-8"))["strings"]
    hits = json.load(open(os.path.join(BUILD, "web_hits.json"),
                          encoding="utf-8"))

    plain, primed = {}, {}
    for lang in LANGS:
        needed = [s for s in sources
                  if LETTER.search(s) and (lang not in WEB_LANGS
                                           or s not in hits)]
        primed[lang] = [s for s in needed if is_short_label(s)]
        plain[lang] = [s for s in needed if not is_short_label(s)]

    json.dump(plain, open(os.path.join(BUILD, "jobs_plain.json"), "w",
                          encoding="utf-8"), ensure_ascii=False)
    json.dump(primed, open(os.path.join(BUILD, "jobs_primed.json"), "w",
                           encoding="utf-8"), ensure_ascii=False)
    print("plain segments :", sum(len(v) for v in plain.values()))
    print("primed segments:", sum(len(v) for v in primed.values()))


if __name__ == "__main__":
    main()

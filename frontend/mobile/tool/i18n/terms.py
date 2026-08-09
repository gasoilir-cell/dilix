#!/usr/bin/env python3
"""ساختِ کارِ ترجمهٔ رشته‌های پوشانده‌شده (`MASKED` در curated.py).

فقط متنی که واژهٔ واقعی دارد به مترجم می‌رود؛ رشته‌ای مثلِ `{0} · {9}` چیزی
برای ترجمه ندارد و `generate.py` مستقیم جای‌گذاری‌اش می‌کند.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from curated import ALL as LANGS, MASKED, MASKED_AUTO  # noqa: E402

BUILD = os.path.join(HERE, "data")
LETTER = re.compile(r"[^\W\d_]", re.UNICODE)


def main():
    all_masked = {**MASKED, **MASKED_AUTO}
    needed = sorted({m for m, _ in all_masked.values()
                     if LETTER.search(m.replace("{9}", ""))})
    jobs = {lang: needed for lang in LANGS}
    os.makedirs(BUILD, exist_ok=True)
    json.dump(jobs, open(os.path.join(BUILD, "jobs_terms.json"), "w",
                         encoding="utf-8"), ensure_ascii=False)
    print(f"masked={len(MASKED)}+{len(MASKED_AUTO)} auto  need-mt={len(needed)} "
          f"segments={len(needed) * len(LANGS)}")


if __name__ == "__main__":
    main()

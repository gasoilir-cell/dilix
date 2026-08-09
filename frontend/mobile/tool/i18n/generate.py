#!/usr/bin/env python3
"""تولیدِ `lib/l10n/translations.dart` از چهار منبع، با اولویتِ نزولی.

 1. نگاشتِ دستی (`curated.py`) — نقطه‌گذاری/برند/اصطلاحِ قطعاً غلط، و
    رشته‌های پوشانده‌شده که واژهٔ دامنه‌ای‌شان پس از ترجمه جای‌گذاری می‌شود.
 2. دیکشنریِ حرفه‌ایِ اپِ وب — ترجمهٔ انسانیِ همین محصول (۹ زبان).
 3. ترجمهٔ ماشینیِ زمینه‌دار — برچسب‌های کوتاه (`translate.py --primed`).
 4. ترجمهٔ ماشینیِ ساده — جمله‌های بلند که خودشان زمینه دارند.

سپس پس‌پردازشِ حرفِ بزرگِ آغازِ برچسب. مقداری که با مبدأ یکسان شود حذف می‌شود؛
`tr()` خودش به متنِ مبدأ برمی‌گردد، پس جدول را بی‌دلیل بزرگ نمی‌کنیم.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from curated import (ALL as LANGS, CURATED, MASKED_AUTO,  # noqa: E402
                     sentence_case, unmask)

BUILD = os.path.join(HERE, "data")
OUT = os.path.normpath(os.path.join(HERE, "..", "..", "lib", "l10n",
                                    "translations.dart"))
WEB_LANGS = {"en", "ar", "tr", "ru", "zh", "hi", "es", "fr", "de"}
PLACEHOLDER = re.compile(r"\{(\d+)\}")


def dart_str(s: str) -> str:
    """literalِ Dart تک‌کوتیشن. `$` هم باید escape شود (درج‌سازیِ رشته)."""
    s = (s.replace("\\", "\\\\").replace("'", "\\'").replace("$", "\\$")
          .replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t"))
    return f"'{s}'"


def load(name, default=None):
    p = os.path.join(BUILD, name)
    if not os.path.exists(p):
        if default is None:
            raise SystemExit(f"missing {p} — مرحلهٔ قبلِ خط‌لوله را اجرا کن")
        return default
    return json.load(open(p, encoding="utf-8"))


def main():
    sources = load("sources.json")["strings"]
    hits = load("web_hits.json", {})
    mt = load("mt_plain.json", {})
    primed = load("mt_primed.json", {})
    terms_mt = load("mt_terms.json", {})

    tables = {l: {} for l in LANGS}
    stats = {l: dict(curated=0, web=0, primed=0, mt=0, same=0, missing=0)
             for l in LANGS}
    dropped = []

    for src in sources:
        for lang in LANGS:
            val, origin = None, None
            row = CURATED.get(src)
            if row and row.get(lang):
                val, origin = row[lang], "curated"
            if val is None:
                masked = unmask(lang, src, terms_mt)
                if masked:
                    val, origin = masked, "curated"
            if val is None and lang in WEB_LANGS and src in hits:
                val, origin = hits[src].get(lang), "web"
            if not val:
                # نقابِ خودکارِ برند — بعد از دیکشنریِ وب، چون آن‌جا ترجمهٔ
                # انسانی است و نامِ محصول را درست می‌نویسد. این‌جا جای خالی
                # پر می‌شود تا «دیلیکس» ماشینی به «Deluxe» تبدیل نشود.
                masked = unmask(lang, src, terms_mt, MASKED_AUTO)
                if masked:
                    val, origin = masked, "curated"
            if not val and primed.get(lang, {}).get(src):
                val, origin = primed[lang][src], "primed"
            if not val and mt.get(lang, {}).get(src):
                val, origin = mt[lang][src], "mt"
            if not val:
                stats[lang]["missing"] += 1
                continue

            # فاصلهٔ ابتدا/انتهای مبدأ معنادار است؛ فقط وقتی مبدأ تمیز است trim کن
            if src.strip() == src:
                val = val.strip()
            val = sentence_case(lang, src, val)

            if set(PLACEHOLDER.findall(src)) != set(PLACEHOLDER.findall(val)):
                # جای‌نگهدارِ گم‌شده یعنی پارامتر در UI ناپدید می‌شود؛
                # متنِ فارسیِ درست بهتر از ترجمهٔ شکسته است.
                dropped.append((lang, src, val))
                stats[lang]["missing"] += 1
                continue
            if val == src:
                stats[lang]["same"] += 1
                continue
            tables[lang][src] = val
            stats[lang][origin] += 1

    lines = [
        "/// نگاشتِ ترجمه: کدِ زبان → (متنِ مبدأ فارسی → متنِ ترجمه‌شده).",
        "///",
        "/// این فایل **تولیدشده** است؛ دستی ویرایش نکنید.",
        "/// بازتولید: `python3 tool/i18n/generate.py` (راهنما: tool/i18n/README.md)",
        "///",
        "/// منابع به‌ترتیبِ اولویت: نگاشتِ دستیِ نقطه‌گذاری/برند ← دیکشنریِ",
        "/// حرفه‌ایِ اپِ وب ← ترجمهٔ ماشینیِ زمینه‌دارِ برچسب‌های کوتاه ←",
        "/// ترجمهٔ ماشینیِ جمله‌های بلند.",
        "///",
        "/// `fa` جدول ندارد: زبانِ مبدأ است و `tr()` خودِ کلید را برمی‌گردانَد.",
        "library;",
        "",
        "const Map<String, Map<String, String>> kTranslations = {",
    ]
    for lang in LANGS:
        lines.append(f"  '{lang}': <String, String>{{")
        for src in sources:
            if src in tables[lang]:
                lines.append(f"    {dart_str(src)}: {dart_str(tables[lang][src])},")
        lines.append("  },")
    lines += ["};", ""]
    open(OUT, "w", encoding="utf-8").write("\n".join(lines))

    print(f"sources={len(sources)}  →  {os.path.relpath(OUT, HERE)}")
    for l in LANGS:
        s = stats[l]
        print(f"  {l}: entries={len(tables[l]):4d}  curated={s['curated']:2d} "
              f"web={s['web']:3d} primed={s['primed']:3d} mt={s['mt']:3d} "
              f"identical={s['same']:3d} missing={s['missing']:2d}")
    if dropped:
        print(f"placeholder-mismatch dropped={len(dropped)}")


if __name__ == "__main__":
    main()

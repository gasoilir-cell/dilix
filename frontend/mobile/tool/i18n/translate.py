#!/usr/bin/env python3
"""مترجمِ دسته‌ایِ رشته‌های UI — **روی سرور** اجرا می‌شود (شبکه لازم دارد).

دو حالت:
  `--plain`   ترجمهٔ مستقیم؛ برای جمله‌های بلند که خودشان زمینه دارند.
  `--primed`  ترجمه با «آمادهٔ زمینه»؛ برای برچسب‌های کوتاه.

چرا حالتِ زمینه‌دار لازم است: مترجمِ ماشینی برای برچسبِ تک‌واژه‌ای زمینه ندارد و
«انصراف» را «opt out» می‌دهد نه «Cancel»، «ذخیره» را در آلمانی «sparen»
(پول‌اندوزی) می‌دهد نه «Speichern». با پیشوندِ فارسیِ «دکمهٔ برنامه: » مترجم
می‌فهمد برچسبِ رابطِ کاربری است؛ بعد پیشوندِ ترجمه‌شده تا **نخستین** دونقطه
بریده می‌شود. اگر الگو نگرفت، نتیجه رد می‌شود تا حالتِ ساده سرِ جایش بمانَد.

ورودی : jobs.json = {"lang": [source, ...]}
خروجی : خروجیِ داده‌شده = {"lang": {source: translated}}
"""
import argparse
import json
import os
import re
import time
import urllib.parse
import urllib.request

URL = "https://translate.googleapis.com/translate_a/single"
PREFIX = "دکمهٔ برنامه: "
PLACEHOLDER = re.compile(r"\{(\d+)\}")
# دونقطهٔ لاتین، تمام‌عرض (چینی) و عربی
COLON = re.compile(r"[:：\uFE55\u0703]")
MAX_LINES = 18
MAX_CHARS = 1400


def call(text: str, tl: str) -> str:
    params = [("client", "gtx"), ("sl", "fa"), ("tl", tl), ("dt", "t"),
              ("q", text)]
    url = URL + "?" + urllib.parse.urlencode(params)
    last = None
    for attempt in range(5):
        try:
            req = urllib.request.Request(
                url, headers={"User-Agent": "Mozilla/5.0 dilix-i18n"})
            raw = urllib.request.urlopen(req, timeout=30).read().decode("utf-8")
            segs = json.loads(raw)[0] or []
            return "".join(s[0] for s in segs if s and s[0])
        except Exception as e:  # noqa: BLE001
            last = e
            time.sleep(1.5 * (attempt + 1))
    raise RuntimeError(f"translate failed tl={tl}: {last}")


def ok_placeholders(src: str, dst: str) -> bool:
    return set(PLACEHOLDER.findall(src)) == set(PLACEHOLDER.findall(dst))


def accept_plain(src: str, out: str):
    out = out.strip()
    return out if out and ok_placeholders(src, out) else None


def accept_primed(src: str, out: str):
    m = COLON.search(out)
    if not m:
        return None
    body = out[m.end():].strip(" \u00a0\u202f\t")
    return body if body and ok_placeholders(src, body) else None


def translate_multiline(src: str, lang: str, prefix: str, accept):
    """رشتهٔ چندخطی را **خط‌به‌خط** ترجمه می‌کند.

    مترجم خطِ جدید را در پاسخ نگه نمی‌دارد و دو خط را به هم می‌چسباند؛ متنِ
    «حالتِ خالی» که باید دو سطر باشد یک‌سطری می‌شود. پس هر خط جداگانه ترجمه و
    دوباره با `\\n` به‌هم دوخته می‌شود. اگر یک خط رد شود کلِ رشته رد می‌شود تا
    نیمه‌ترجمه ذخیره نشود.
    """
    out = []
    for line in src.split("\n"):
        if not line.strip():
            out.append(line)
            continue
        got = call(prefix + line, lang).replace("\n", " ")
        val = accept(line, got)
        if not val:
            return None
        out.append(val)
    return "\n".join(out)


def batches(items, extra: int):
    cur, size = [], 0
    for s in items:
        if cur and (size + len(s) + extra + 1 > MAX_CHARS
                    or len(cur) >= MAX_LINES):
            yield cur
            cur, size = [], 0
        cur.append(s)
        size += len(s) + extra + 1
    if cur:
        yield cur


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--jobs", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--primed", action="store_true")
    args = ap.parse_args()

    prefix = PREFIX if args.primed else ""
    accept = accept_primed if args.primed else accept_plain

    jobs = json.load(open(args.jobs, encoding="utf-8"))
    out = (json.load(open(args.out, encoding="utf-8"))
           if os.path.exists(args.out) else {})
    rejected = []

    for lang, sources in jobs.items():
        done = out.setdefault(lang, {})
        todo = [s for s in sources if s not in done]
        print(f"[{lang}] todo={len(todo)}", flush=True)
        for s in [x for x in todo if "\n" in x]:
            try:
                v = translate_multiline(s, lang, prefix, accept)
            except RuntimeError as e:
                print("  !", e, flush=True)
                continue
            if v:
                done[s] = v
            else:
                rejected.append([lang, s, ""])
        todo = [x for x in todo if "\n" not in x]
        for batch in batches(todo, len(prefix)):
            joined = "\n".join(prefix + s for s in batch)
            try:
                res = call(joined, lang)
            except RuntimeError as e:
                print("  !", e, flush=True)
                continue
            lines = res.split("\n")
            if len(lines) != len(batch):
                # شمارشِ خط نخواند یعنی نگاشت جابه‌جا می‌شود → تک‌تک
                for s in batch:
                    try:
                        one = call(prefix + s, lang).replace("\n", " ")
                    except RuntimeError as e:
                        print("  !", e, flush=True)
                        continue
                    v = accept(s, one)
                    if v:
                        done[s] = v
                    else:
                        rejected.append([lang, s, one])
            else:
                for s, line in zip(batch, lines):
                    v = accept(s, line)
                    if v:
                        done[s] = v
                    else:
                        rejected.append([lang, s, line])
            time.sleep(0.25)
        json.dump(out, open(args.out, "w", encoding="utf-8"),
                  ensure_ascii=False)
        print(f"[{lang}] kept={len(done)}/{len(sources)}", flush=True)

    json.dump(rejected, open(args.out + ".rejected", "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print(f"rejected={len(rejected)}")


if __name__ == "__main__":
    main()

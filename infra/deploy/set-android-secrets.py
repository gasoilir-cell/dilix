#!/usr/bin/env python3
"""ثبتِ سه رازِ امضای اندروید در GitHub Actions.

چرا اسکریپت و نه کپی‌ودستیِ داخلِ UI؟ چون `ANDROID_KEYSTORE_B64` حدودِ ۶ کیلوبایت
Base64 یک‌خطی است؛ کپیِ دستی مستعدِ افتادنِ کاراکتر و newlineِ ناخواسته است و
خطایش هم *بی‌صدا*ست: بیلد سبز می‌ماند و فقط APK با کلیدِ اشتباه امضا می‌شود.

مقادیر از `/opt/dilix-keys/` روی سرور خوانده می‌شوند (خارج از گیت، ۰۷۰۰) و هرگز
روی دیسکِ کانتینر یا در لاگ نوشته نمی‌شوند.

    GH_TOKEN=ghp_xxx python3 infra/deploy/set-android-secrets.py

توکن باید scopeِ `repo` داشته باشد (رازهای Actions زیرِ همان مجوزند) و کاربر باید
admin مخزن باشد. اسکریپت idempotent است: اجرای دوباره فقط مقدار را بازنویسی
می‌کند.
"""

from __future__ import annotations

import base64
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

REPO = os.environ.get("DILIX_REPO", "gasoilir-cell/dilix")
SERVER = os.environ.get("DILIX_SERVER", "root@185.55.226.250")
KEYDIR = "/opt/dilix-keys"
API = "https://api.github.com"


def fail(msg: str) -> "None":
    print(f"ERROR: {msg}", file=sys.stderr)
    raise SystemExit(1)


def gh(path: str, token: str, method: str = "GET", body: dict | None = None) -> dict:
    req = urllib.request.Request(
        f"{API}{path}",
        method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "Content-Type": "application/json",
            "User-Agent": "dilix-deploy",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")[:300]
        if e.code in (401, 403):
            fail(
                f"GitHub اجازه نداد ({e.code}). توکن باید scopeِ `repo` داشته باشد و "
                f"حسابش adminِ {REPO} باشد. پاسخ: {detail}"
            )
        if e.code == 404:
            fail(f"مسیر پیدا نشد ({path}) — معمولاً یعنی توکن به این مخزن دسترسی ندارد.")
        fail(f"GitHub {e.code} روی {path}: {detail}")


def read_remote(path: str) -> str:
    """خواندنِ یک فایلِ راز از سرور بدونِ نوشتنش روی دیسکِ محلی."""
    out = subprocess.run(
        ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15", SERVER, f"cat {path}"],
        capture_output=True,
    )
    if out.returncode != 0:
        fail(f"خواندنِ {path} از سرور نشد: {out.stderr.decode(errors='replace')[:200]}")
    return out.stdout.decode().strip()


def main() -> None:
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if not token:
        fail("متغیرِ GH_TOKEN تنظیم نشده است.")

    from nacl import encoding, public  # PyNaCl

    password = read_remote(f"{KEYDIR}/store.pass")
    keystore_b64 = read_remote(f"{KEYDIR}/keystore.b64").replace("\n", "")
    if not password or not keystore_b64:
        fail("مقدارِ خالی از سرور برگشت.")
    # اعتبارسنجیِ محلی پیش از ارسال: اگر Base64 خراب باشد CI با «bad base64» در
    # گامِ نصبِ کیستور می‌افتد و ردیابی‌اش سخت است.
    try:
        raw = base64.b64decode(keystore_b64, validate=True)
    except Exception as exc:  # noqa: BLE001
        fail(f"keystore.b64 معتبر نیست: {exc}")
    if not raw.startswith(b"\x30\x82"):
        fail("محتوای رمزگشایی‌شده ساختارِ DER/PKCS12 ندارد.")
    print(f"کیستور: {len(raw)} بایت، Base64 سالم.")

    key = gh(f"/repos/{REPO}/actions/secrets/public-key", token)
    sealed = public.SealedBox(
        public.PublicKey(key["key"].encode(), encoding.Base64Encoder())
    )

    secrets = {
        "ANDROID_KEYSTORE_ALIAS": os.environ.get("DILIX_KEY_ALIAS", "dilix"),
        "ANDROID_KEYSTORE_PASSWORD": password,
        "ANDROID_KEYSTORE_B64": keystore_b64,
    }
    for name, value in secrets.items():
        gh(
            f"/repos/{REPO}/actions/secrets/{name}",
            token,
            method="PUT",
            body={
                "encrypted_value": base64.b64encode(
                    sealed.encrypt(value.encode())
                ).decode(),
                "key_id": key["key_id"],
            },
        )
        print(f"✓ {name} ثبت شد ({len(value)} کاراکتر)")

    have = {s["name"] for s in gh(f"/repos/{REPO}/actions/secrets", token)["secrets"]}
    missing = set(secrets) - have
    if missing:
        fail(f"این رازها پس از ثبت دیده نشدند: {sorted(missing)}")
    print("\nهر سه راز روی مخزن تأیید شد. بیلدِ بعدی APK را با کلیدِ پایدار امضا می‌کند.")
    print(
        "⚠ اولین APKِ امضاشده با کلیدِ تازه روی نصبِ فعلی به‌روزرسانی نمی‌شود؛ "
        "کاربر باید نسخهٔ قبلی را حذف کند."
    )


if __name__ == "__main__":
    main()

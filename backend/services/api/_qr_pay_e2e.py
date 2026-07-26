"""E2E: پرداختِ QR (ساختِ کد + resolve + انتقال + قفلِ هم‌زمانی).

روی سرور اجرا می‌شود:  cd /var/www/dilix-api && venv/bin/python _qr_pay_e2e.py
مبالغِ آزمایشی بین دو حسابِ تست جابه‌جا و در پایان برگردانده می‌شوند.
"""
import asyncio

import httpx
from sqlalchemy import select

from app.core.database import AsyncSessionLocal, engine
from app.core.security import create_access_token
from app.models.user import User
from app.models.wallet import Wallet

BASE = "http://127.0.0.1:8000/api/v1"
A_EID = "DLX-OO39V4SY"
B_EID = "DLX-CSV157XM"

passed = 0
failed = 0


def check(cond, label):
    global passed, failed
    if cond:
        passed += 1
        print(f"  PASS  {label}")
    else:
        failed += 1
        print(f"  FAIL  {label}")


async def _balance(user_id):
    async with AsyncSessionLocal() as db:
        w = (await db.execute(select(Wallet).where(Wallet.user_id == user_id))).scalar_one_or_none()
        return w.balance_available if w else 0


async def main():
    async with AsyncSessionLocal() as db:
        A = (await db.execute(select(User).where(User.earth_id == A_EID))).scalar_one()
        B = (await db.execute(select(User).where(User.earth_id == B_EID))).scalar_one()
        # موجودیِ کافی برای آزمون، بدونِ دست‌زدن به رقمِ واقعی در پایان
        wa = (await db.execute(select(Wallet).where(Wallet.user_id == A.id))).scalar_one_or_none()
        if wa is None:
            wa = Wallet(user_id=A.id, currency="IRR")
            db.add(wa)
        seed_before = wa.balance_available
        wa.balance_available = seed_before + 1_000_000
        await db.commit()

    ha = {"Authorization": f"Bearer {create_access_token({'sub': str(A.id)})}"}
    hb = {"Authorization": f"Bearer {create_access_token({'sub': str(B.id)})}"}

    a0 = await _balance(A.id)
    b0 = await _balance(B.id)

    async with httpx.AsyncClient(timeout=20) as c:
        # ── ساختِ کدِ دریافت ────────────────────────────────────────────────
        r = await c.get(f"{BASE}/wallet/qr/payload", headers=hb)
        check(r.status_code == 200, f"payload 200 ({r.status_code})")
        payload = r.json()["payload"]
        check(payload == f"https://dilix.ir/pay/{B_EID}", f"payload = {payload}")

        r = await c.get(f"{BASE}/wallet/qr/payload", params={"amount": 25000, "note": "قهوه"}, headers=hb)
        payload_amt = r.json()["payload"]
        check("a=25000" in payload_amt and "n=" in payload_amt, f"payload با مبلغ/یادداشت: {payload_amt}")

        r = await c.get(f"{BASE}/wallet/qr", params={"amount": 25000}, headers=hb)
        check(r.status_code == 200 and r.headers["content-type"].startswith("image/svg"), "SVG 200")
        check(b"<svg" in r.content, "بدنه SVG است")
        check(r.headers.get("cache-control") == "no-store", "کشِ عمومی خاموش (مبلغ داخلِ کد است)")

        # ── resolve ────────────────────────────────────────────────────────
        r = await c.post(f"{BASE}/wallet/qr/resolve", json={"payload": payload_amt}, headers=ha)
        check(r.status_code == 200, f"resolve 200 ({r.status_code})")
        res = r.json()
        check(res["earth_id"] == B_EID, "گیرنده درست است")
        check(res["amount"] == 25000, "مبلغ از کد خوانده شد")
        check(res["note"] == "قهوه", "یادداشت از کد خوانده شد")
        check(res["is_self"] is False, "is_self=False")

        r = await c.post(f"{BASE}/wallet/qr/resolve", json={"payload": payload}, headers=hb)
        check(r.json()["is_self"] is True, "اسکنِ کدِ خودم → is_self=True")

        # QRِ پروفایل هم باید کار کند (کاربر ممکن است همان را اسکن کند)
        r = await c.post(f"{BASE}/wallet/qr/resolve",
                         json={"payload": f"https://dilix.ir/u/{B_EID}"}, headers=ha)
        check(r.status_code == 200 and r.json()["amount"] is None, "QRِ پروفایل → resolve بدونِ مبلغ")

        # شناسه‌ی خام
        r = await c.post(f"{BASE}/wallet/qr/resolve", json={"payload": B_EID}, headers=ha)
        check(r.status_code == 200, "شناسه‌ی خام هم پذیرفته می‌شود")

        # ── ورودی‌های نامعتبر ──────────────────────────────────────────────
        for bad, label in [
            (f"https://example.com/pay/{B_EID}", "دامنه‌ی فیشینگ با شناسه‌ی معتبر"),
            ("https://dilix.ir/pay/NOT-AN-ID", "شناسه‌ی بدشکل"),
            ("سلام", "متنِ بی‌ربط"),
            ("https://dilix.ir/pay/DLX-AAAA?a=-5", "مبلغِ منفی"),
            ("https://dilix.ir/pay/DLX-AAAA?a=abc", "مبلغِ غیرعددی"),
        ]:
            r = await c.post(f"{BASE}/wallet/qr/resolve", json={"payload": bad}, headers=ha)
            check(r.status_code in (400, 404), f"{label} رد شد ({r.status_code})")

        r = await c.post(f"{BASE}/wallet/qr/resolve",
                         json={"payload": "https://dilix.ir/pay/DLX-ZZZZZZZZ"}, headers=ha)
        check(r.status_code == 404, f"کاربرِ ناموجود 404 ({r.status_code})")

        # ── پرداخت ─────────────────────────────────────────────────────────
        r = await c.post(f"{BASE}/wallet/transfer",
                         json={"to_earth_id": B_EID, "amount": 25000, "description": "پرداخت با QR"},
                         headers=ha)
        check(r.status_code == 200, f"transfer 200 ({r.status_code})")
        check(await _balance(A.id) == a0 - 25000, "موجودیِ پرداخت‌کننده کم شد")
        check(await _balance(B.id) == b0 + 25000, "موجودیِ گیرنده زیاد شد")

        r = await c.post(f"{BASE}/wallet/transfer",
                         json={"to_earth_id": A_EID, "amount": 10**12}, headers=ha)
        check(r.status_code == 400, f"موجودیِ ناکافی 400 ({r.status_code})")

        r = await c.post(f"{BASE}/wallet/transfer",
                         json={"to_earth_id": A_EID, "amount": 1000}, headers=ha)
        check(r.status_code == 400, f"پرداخت به خود 400 ({r.status_code})")

        # ── هم‌زمانی: ۱۰ پرداختِ موازی نباید خرجِ دوباره بسازد ──────────────
        a1 = await _balance(A.id)
        b1 = await _balance(B.id)
        results = await asyncio.gather(*[
            c.post(f"{BASE}/wallet/transfer", json={"to_earth_id": B_EID, "amount": 1000}, headers=ha)
            for _ in range(10)
        ], return_exceptions=True)
        ok = sum(1 for r in results if not isinstance(r, Exception) and r.status_code == 200)
        check(ok == 10, f"۱۰ پرداختِ موازی همه موفق ({ok}/10)")
        check(await _balance(A.id) == a1 - 10_000, "جمعِ کسر دقیقاً ۱۰×۱۰۰۰")
        check(await _balance(B.id) == b1 + 10_000, "جمعِ واریز دقیقاً ۱۰×۱۰۰۰")

    # ── برگرداندنِ موجودی‌ها به حالتِ اول ──────────────────────────────────
    async with AsyncSessionLocal() as db:
        wa = (await db.execute(select(Wallet).where(Wallet.user_id == A.id))).scalar_one()
        wb = (await db.execute(select(Wallet).where(Wallet.user_id == B.id))).scalar_one()
        wa.balance_available = seed_before
        wb.balance_available = b0
        await db.commit()
    check(await _balance(A.id) == seed_before, "موجودیِ آزمایشی پاک شد")

    await engine.dispose()
    print(f"\n== {passed} passed, {failed} failed ==")


asyncio.run(main())

"""
audit_50users.py — رگرسیونِ سرتاسریِ APIِ زنده با ۵۰ کاربرِ واقعی.

چرا اسکریپت و نه تستِ واحد؟ چیزی که کاربر گزارش کرده «صفحه بارگذاری نشد» است،
یعنی خطا در *ترکیبِ* مسیر/توکن/داده روی سرورِ واقعی رخ می‌دهد، نه در منطقِ تابع.
پس همان چیزی را می‌زنیم که اپ می‌زند: HTTPِ واقعی روی 127.0.0.1:8000 با توکنِ
واقعیِ ۵۰ کاربرِ تازه‌ساخته.

اجرا (روی سرور):  venv/bin/python audit_50users.py
"""
import asyncio
import json
import os
import random
import sys
import time
from collections import defaultdict

import httpx

BASE = os.environ.get("AUDIT_BASE", "http://127.0.0.1:8000")
N_USERS = int(os.environ.get("AUDIT_USERS", "50"))
RUN = int(time.time())

# کدهایی که «خطا» نیستند: قاعدهٔ کسب‌وکار درست کار کرده است.
OK_BUSINESS = {400, 402, 403, 404, 409, 422}

failures: list[tuple[str, str, int, str]] = []
stats: dict[str, list[int]] = defaultdict(list)


def note(method: str, path: str, status: int, body: str, expect_ok: bool) -> None:
    stats[f"{method} {path}"].append(status)
    if status >= 500 or (expect_ok and status >= 400):
        failures.append((method, path, status, body[:300]))


async def call(c, method, path, *, token=None, json_body=None, expect_ok=True):
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    try:
        r = await c.request(method, BASE + path, headers=headers, json=json_body)
    except Exception as e:                       # خطای شبکه/تایم‌اوت هم شکست است
        note(method, path, 599, repr(e), expect_ok)
        return None
    note(method, path, r.status_code, r.text, expect_ok)
    if r.status_code >= 400:
        return None
    try:
        return r.json()
    except Exception:
        return r.text


async def make_users(n):
    """کاربرها مستقیم از سرویسِ احراز ساخته می‌شوند، نه از `/auth/register`.

    مسیرِ HTTP سقفِ ضدِ سوءاستفاده دارد (۵ ثبت‌نام در ساعت به‌ازای IP) و از
    ۱۲۷.۰.۰.۱ همهٔ ۵۰ کاربر یک IP دیده می‌شوند. سقف را دور نمی‌زنیم و کم هم
    نمی‌کنیم — فقط ساختِ کاربر را از لایهٔ سرویس انجام می‌دهیم؛ بقیهٔ ممیزی
    دقیقاً همان HTTPِ واقعیِ اپ است.
    """
    from app.core.database import AsyncSessionLocal
    from app.services.auth_service import AuthService

    out = []
    async with AsyncSessionLocal() as db:
        svc = AuthService(db)
        for i in range(n):
            ident = f"audit{RUN}u{i:03d}@dilix.test"
            user, _ = await svc.register_email(ident, "AuditPass!2026", f"کاربر آزمون {i}")
            tokens = await svc.create_tokens(user)
            out.append({"token": tokens["access_token"],
                        "earth_id": user.earth_id, "ident": ident})
        await db.commit()
    return out


# ── مسیرهای فقط-خواندنیِ هر کاربر (همان‌هایی که صفحه‌های اپ لود می‌کنند) ────────
READ_PATHS = [
    "/api/v1/auth/me",
    "/api/v1/auth/me/kyc",
    "/api/v1/wallet",
    "/api/v1/wallet/transactions",
    "/api/v1/holdings",
    "/api/v1/membership",
    "/api/v1/membership/plans",
    "/api/v1/investment/funds",
    "/api/v1/investment/positions",
    "/api/v1/investment/nav?fund_code=DILIX_GROWTH",
    "/api/v1/growth/revenue-share",
    "/api/v1/marketplace/listings",
    "/api/v1/marketplace/orders",
    "/api/v1/telecom/top-ups",
    "/api/v1/telecom/esims",
    "/api/v1/payments/escrow",
    "/api/v1/gamification/me",
    "/api/v1/gamification/badges",
    "/api/v1/gamification/history?limit=20",
    "/api/v1/gamification/leaderboard?period=all&limit=20",
    "/api/v1/referral/stats",
    "/api/v1/referral/network",
    "/api/v1/referral/commissions",
    "/api/v1/notifications",
    "/api/v1/providers/types",
    "/api/v1/providers/catalog/products",
    "/api/v1/providers/catalog/products?provider_type=bank",
    "/api/v1/providers/catalog/products?provider_type=psp",
    "/api/v1/providers/catalog/products?provider_type=broker",
    "/api/v1/providers/catalog/products?provider_type=other",
    "/api/v1/providers/agreement",
    "/api/v1/providers/me",
    "/api/v1/earth/users",
    "/api/v1/posts/feed",
    "/api/v1/stories/feed",
    "/api/v1/reels/feed",
    "/api/v1/messages/rooms",
    "/api/v1/messages/blocks",
    "/api/v1/shop/products",
    "/api/v1/bills",
    "/api/v1/bills/types",
    "/api/v1/bills/saved",
    "/api/v1/stickers/market",
    "/api/v1/stickers/packs/installed",
    "/api/v1/stickers/packs/mine",
    "/api/v1/stickers/packs/public",
    "/api/v1/stickers/starred",
    "/api/v1/stickers/purchases",
    "/api/v1/miniapps",
    "/api/v1/fx/rates",
    "/api/v1/i18n/catalog",
    "/api/v1/i18n/preferences",
]


async def read_sweep(c, u):
    for p in READ_PATHS:
        await call(c, "GET", p, token=u["token"])
    # اعتبار به earth_id نیاز دارد
    if u["earth_id"]:
        await call(c, "GET", f"/api/v1/reputation/scores/{u['earth_id']}", token=u["token"])
        await call(c, "GET", f"/api/v1/reputation/reviews/{u['earth_id']}", token=u["token"])


# ── جریان‌های نوشتنی ──────────────────────────────────────────────────────────
async def write_flows(c, users):
    seller, buyer = users[0], users[1]

    # ۱) بازارگاه: آگهی → سفارش (بدونِ موجودی باید ۴۰۰ بدهد، نه ۵۰۰)
    listing = await call(c, "POST", "/api/v1/marketplace/listings", token=seller["token"],
                         json_body={"title": "خدمتِ آزمونِ ممیزی", "description": "تست",
                                    "category": "dev", "base_price_minor": 1000,
                                    "currency": "IRR", "delivery_days": 3})
    if listing:
        await call(c, "POST", "/api/v1/marketplace/orders", token=buyer["token"],
                   json_body={"listing_id": listing["id"], "agreed_price_minor": 1000,
                              "currency": "IRR"}, expect_ok=False)
        # سفارش روی آگهیِ خودم باید ۴۰۰ بدهد
        await call(c, "POST", "/api/v1/marketplace/orders", token=seller["token"],
                   json_body={"listing_id": listing["id"], "agreed_price_minor": 1000,
                              "currency": "IRR"}, expect_ok=False)

    # ۲) عضویت: ارتقا بدونِ موجودی → ۴۰۰؛ بازگشت به رایگان → ۲۰۰
    await call(c, "POST", "/api/v1/membership/upgrade", token=buyer["token"],
               json_body={"plan": "premium", "months": 1}, expect_ok=False)
    await call(c, "POST", "/api/v1/membership/upgrade", token=buyer["token"],
               json_body={"plan": "free", "months": 1})
    await call(c, "POST", "/api/v1/membership/cancel", token=buyer["token"])

    # ۳) سرمایه‌گذاری: خریدِ بدونِ موجودی → ۴۰۰
    await call(c, "POST", "/api/v1/investment/buy", token=buyer["token"],
               json_body={"fund_code": "DILIX_GROWTH", "amount_minor": 1_000_000},
               expect_ok=False)

    # ۴) مخابرات: شارژِ بدونِ موجودی → ۴۰۰؛ شمارهٔ بد → ۴۲۲
    await call(c, "POST", "/api/v1/telecom/top-up", token=buyer["token"],
               json_body={"msisdn": "+989121234567", "amount_minor": 50_000,
                          "product_code": "MCI-50"}, expect_ok=False)
    await call(c, "POST", "/api/v1/telecom/top-up", token=buyer["token"],
               json_body={"msisdn": "بد", "amount_minor": 50_000,
                          "product_code": "MCI-50"}, expect_ok=False)

    # ۵) امانی: ساختِ سفارشِ پرداخت بدونِ موجودی → ۴۰۰
    await call(c, "POST", "/api/v1/payments/escrow", token=buyer["token"],
               json_body={"payee_earth_id": seller["earth_id"], "amount_minor": 1000,
                          "currency": "IRR"}, expect_ok=False)

    # ۶) اعتبار: نظرِ متقابل + تکرارِ همان نظر (باید ۴۰۹ بدهد نه ۵۰۰)
    body = {"reviewee_earth_id": seller["earth_id"], "domain": "trust", "rating": 5,
            "comment": "آزمونِ ممیزی", "transaction_ref": f"audit-{RUN}"}
    await call(c, "POST", "/api/v1/reputation/reviews", token=buyer["token"], json_body=body)
    await call(c, "POST", "/api/v1/reputation/reviews", token=buyer["token"],
               json_body=body, expect_ok=False)
    await call(c, "GET", f"/api/v1/reputation/scores/{seller['earth_id']}", token=buyer["token"])

    # ۷) گیمیفیکیشن: ورودِ روزانه + همگام‌سازیِ نشان (باید idempotent باشد)
    await call(c, "POST", "/api/v1/gamification/check-in", token=buyer["token"], json_body={})
    await call(c, "POST", "/api/v1/gamification/check-in", token=buyer["token"], json_body={})
    await call(c, "POST", "/api/v1/gamification/sync", token=buyer["token"], json_body={})

    # ۸) ارائه‌دهنده: ثبت‌نامِ بانک و بررسیِ اینکه کاتالوگِ بانکی می‌گیرد
    prov = await call(c, "POST", "/api/v1/providers/register", token=seller["token"],
                      json_body={"legal_name": f"بانکِ آزمون {RUN}", "provider_type": "bank",
                                 "license_no": "AUD-1", "products": ["loan", "card_issue"]},
                      expect_ok=False)
    if prov:
        await call(c, "GET", f"/api/v1/providers/{prov['id']}", token=seller["token"])
        await call(c, "GET", "/api/v1/providers/me", token=seller["token"])


async def fund(earth_id: str, amount: int) -> None:
    """شارژِ مستقیمِ کیفِ کاربرِ آزمون — تنها راهِ رسیدن به مسیرهای «پول‌دار»."""
    from sqlalchemy import select

    from app.core.database import AsyncSessionLocal
    from app.models.user import User
    from app.models.wallet import Wallet
    from app.services.wallet_ops import get_or_create_wallet

    async with AsyncSessionLocal() as db:
        u = (await db.execute(select(User).where(User.earth_id == earth_id))).scalar_one()
        await get_or_create_wallet(db, u.id)
        w = (await db.execute(select(Wallet).where(Wallet.user_id == u.id))).scalar_one()
        w.balance_available += amount
        await db.commit()


async def balance(c, token) -> tuple[int, int]:
    w = await call(c, "GET", "/api/v1/wallet", token=token)
    return int(w.get("balance_available", 0)), int(w.get("balance_escrow", 0))


async def money_flows(c, users):
    """مسیرهایی که واقعاً پول جابه‌جا می‌کنند — جایی که باگ گران تمام می‌شود."""
    seller, buyer = users[2], users[3]
    PRICE = 1_000_000
    await fund(buyer["earth_id"], 50_000_000)
    await fund(seller["earth_id"], 10_000_000)

    b0, l0 = await balance(c, buyer["token"])
    s0, _ = await balance(c, seller["token"])

    # ── بازارگاه با پولِ واقعی: بلوکه → پذیرش → تحویل → تکمیل ──
    listing = await call(c, "POST", "/api/v1/marketplace/listings", token=seller["token"],
                         json_body={"title": "خدمتِ پولیِ آزمون", "description": "تست",
                                    "category": "dev", "base_price_minor": PRICE,
                                    "currency": "IRR", "delivery_days": 2})
    order = await call(c, "POST", "/api/v1/marketplace/orders", token=buyer["token"],
                       json_body={"listing_id": listing["id"],
                                  "agreed_price_minor": PRICE, "currency": "IRR"})
    b1, l1 = await balance(c, buyer["token"])
    check("بلوکهٔ سفارش از موجودیِ در دسترس کم شد", b1 == b0 - PRICE)
    check("بلوکهٔ سفارش به موجودیِ قفل‌شده اضافه شد", l1 == l0 + PRICE)

    oid = order["id"]
    # نقشِ اشتباه باید رد شود، وگرنه خریدار می‌توانست کارِ نکرده را تحویل‌شده کند
    await call(c, "POST", f"/api/v1/marketplace/orders/{oid}/deliver",
               token=buyer["token"], expect_ok=False)
    await call(c, "POST", f"/api/v1/marketplace/orders/{oid}/accept", token=seller["token"])
    await call(c, "POST", f"/api/v1/marketplace/orders/{oid}/deliver", token=seller["token"])
    await call(c, "POST", f"/api/v1/marketplace/orders/{oid}/complete", token=buyer["token"])
    # تکمیلِ دوباره نباید دوباره پول آزاد کند (خلقِ پول)
    r2 = await call(c, "POST", f"/api/v1/marketplace/orders/{oid}/complete",
                    token=buyer["token"], expect_ok=False)
    check("تکمیلِ تکراریِ سفارش رد شد", r2 is None)

    b2, l2 = await balance(c, buyer["token"])
    s2, _ = await balance(c, seller["token"])
    fee = PRICE * 5 // 100
    check("قفلِ خریدار پس از تکمیل آزاد شد", l2 == l0)
    check("موجودیِ در دسترسِ خریدار تغییرِ اضافه نکرد", b2 == b1)
    check("فروشنده مبلغ منهای کارمزد را گرفت", s2 == s0 + PRICE - fee)

    # ── لغو باید وجه را برگرداند ──
    o2 = await call(c, "POST", "/api/v1/marketplace/orders", token=buyer["token"],
                    json_body={"listing_id": listing["id"],
                               "agreed_price_minor": PRICE, "currency": "IRR"})
    await call(c, "POST", f"/api/v1/marketplace/orders/{o2['id']}/cancel", token=buyer["token"])
    b3, l3 = await balance(c, buyer["token"])
    check("لغوِ سفارش وجه را کامل برگرداند", b3 == b2 and l3 == l0)

    # ── عضویت: ارتقا واقعاً پول کم می‌کند و تمدید تاریخ را جلو می‌برد ──
    before, _ = await balance(c, buyer["token"])
    m1 = await call(c, "POST", "/api/v1/membership/upgrade", token=buyer["token"],
                    json_body={"plan": "standard", "months": 2})
    after, _ = await balance(c, buyer["token"])
    check("ارتقای عضویت از کیف کسر شد", after == before - 1_900_000 * 2)
    check("کش‌بکِ طرحِ استاندارد اعمال شد", (m1 or {}).get("cashback_bps") == 100)
    m2 = await call(c, "POST", "/api/v1/membership/upgrade", token=buyer["token"],
                    json_body={"plan": "standard", "months": 1})
    check("تمدید انقضا را جلو برد",
          (m2 or {}).get("expires_at", "") > (m1 or {}).get("expires_at", ""))

    # ── سرمایه‌گذاری: خرید و فروشِ کامل باید موجودی را برگرداند ──
    before, _ = await balance(c, buyer["token"])
    pos = await call(c, "POST", "/api/v1/investment/buy", token=buyer["token"],
                     json_body={"fund_code": "DILIX_GROWTH", "amount_minor": 5_000_000})
    mid, _ = await balance(c, buyer["token"])
    check("خریدِ صندوق از کیف کسر شد", mid == before - 5_000_000)
    positions = await call(c, "GET", "/api/v1/investment/positions", token=buyer["token"])
    check("موقعیتِ صندوق در فهرست آمد",
          any(p["fund_code"] == "DILIX_GROWTH" for p in (positions or [])))
    await call(c, "POST", "/api/v1/investment/sell", token=buyer["token"],
               json_body={"fund_code": "DILIX_GROWTH", "units": (pos or {})["units"]})
    end, _ = await balance(c, buyer["token"])
    check("فروشِ کاملِ همان روز موجودی را برگرداند (±۱ ریالِ گِردکردن)",
          abs(end - before) <= 1)

    # ── مخابرات: شارژ پول کم می‌کند ──
    before, _ = await balance(c, buyer["token"])
    await call(c, "POST", "/api/v1/telecom/top-up", token=buyer["token"],
               json_body={"msisdn": "+989121234567", "amount_minor": 200_000,
                          "product_code": "MCI-200"})
    after, _ = await balance(c, buyer["token"])
    check("شارژِ مخابراتی از کیف کسر شد", after == before - 200_000)

    # ── پرداختِ امانی: بلوکه → capture ──
    b_before, _ = await balance(c, buyer["token"])
    s_before, _ = await balance(c, seller["token"])
    pay = await call(c, "POST", "/api/v1/payments/escrow", token=buyer["token"],
                     json_body={"payee_earth_id": seller["earth_id"],
                                "amount_minor": 300_000, "currency": "IRR"})
    await call(c, "POST", f"/api/v1/payments/{pay['id']}/capture", token=seller["token"])
    b_after, _ = await balance(c, buyer["token"])
    s_after, _ = await balance(c, seller["token"])
    check("پرداختِ امانی از خریدار کم شد", b_after == b_before - 300_000)
    check("پرداختِ امانی به فروشنده رسید", s_after > s_before)


CHECKS: list[tuple[str, bool]] = []


def check(label: str, ok: bool) -> None:
    CHECKS.append((label, bool(ok)))


async def main():
    limits = httpx.Limits(max_connections=20)
    async with httpx.AsyncClient(timeout=30, limits=limits) as c:
        print(f"→ ساختِ {N_USERS} کاربر …", flush=True)
        users = await make_users(N_USERS)
        print(f"  {len(users)} کاربر ساخته شد", flush=True)
        if len(users) < 2:
            print("✗ کاربرِ کافی ساخته نشد؛ ادامه ممکن نیست")
            return 1

        print("→ پویشِ خواندنیِ همهٔ صفحه‌ها برای هر کاربر …", flush=True)
        for batch in range(0, len(users), 10):
            await asyncio.gather(*[read_sweep(c, u) for u in users[batch:batch + 10]])

        print("→ جریان‌های نوشتنی …", flush=True)
        await write_flows(c, users)

        print("→ جریان‌های پولی (بلوکه/آزادسازی/کارمزد) …", flush=True)
        await money_flows(c, users)

        # همزمانی: ۱۰ کاربر هم‌زمان عضویتِ رایگان می‌گیرند (تلهٔ رقابتِ ردیفِ یکتا)
        print("→ آزمونِ رقابتِ هم‌زمان روی /membership …", flush=True)
        await asyncio.gather(*[
            call(c, "GET", "/api/v1/membership", token=u["token"]) for u in users[:10]
        ])

    print("\n" + "=" * 72)
    print(f"مجموعِ فراخوانی: {sum(len(v) for v in stats.values())}   شکست: {len(failures)}")
    if failures:
        seen = set()
        for m, p, s, b in failures:
            key = (m, p.split("?")[0], s)
            if key in seen:
                continue
            seen.add(key)
            print(f"  ✗ {s}  {m} {p}\n      {b}")
    else:
        print("  ✓ هیچ خطای ۵xx یا خطای غیرمنتظره‌ای دیده نشد")

    bad = [c for c in CHECKS if not c[1]]
    print(f"\nصحتِ مانده‌ها: {len(CHECKS) - len(bad)}/{len(CHECKS)}")
    for label, ok in CHECKS:
        print(f"  {'✓' if ok else '✗'} {label}")
    print("=" * 72)
    return 1 if (failures or bad) else 0


sys.exit(asyncio.run(main()))

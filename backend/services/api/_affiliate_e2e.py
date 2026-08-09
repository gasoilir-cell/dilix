"""E2E: کمیسیونِ رفرال روی **فروش** + قیفِ بازدید→عضویتِ لینکِ دعوت.

روی سرور اجرا می‌شود:  cd /var/www/dilix-api && venv/bin/python _affiliate_e2e.py

چهار کاربرِ یک‌بارمصرف می‌سازد (L2 → L1 → خریدار، به‌علاوهٔ فروشنده)، یک خریدِ
واقعی را تا تسویه می‌بَرد و در پایان همه را پاک می‌کند. روی حسابِ واقعی کار
نمی‌کند چون `referred_by` یک‌بار در عمرِ حساب قابلِ ثبت است و آزمون نباید
شبکهٔ واقعیِ کسی را دست‌کاری کند.

ناوردای اصلیِ این آزمون: **پلتفرم روی سفارشِ معرف‌دار ضرر نمی‌کند** —
کارمزدِ ۲٪ باید از جمعِ کمیسیون‌های پرداختی بیشتر بماند.
"""
import asyncio
import uuid as _uuid

import httpx
from sqlalchemy import delete, select, text

from app.core.database import AsyncSessionLocal, engine
from app.core.security import create_access_token
from app.models.user import User
from app.models.wallet import Wallet
from app.models.mlm import MlmCommission
from app.models.messages import Message, MessageRoom, RoomMember
from app.services.mlm import SHOP_LEVEL_RATES_BPS
from app.api.v1.shop.router import ShopOrder, ShopOrderItem, ShopProduct, COMMISSION_PCT
from app.api.v1.referral.router import ReferralClick

BASE = "http://127.0.0.1:8000/api/v1"
PRICE = 1_000_000          # ۱ میلیون ریال
SEED = 5_000_000

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


def _tag() -> str:
    return _uuid.uuid4().hex[:6].upper()


async def _mk_user(db, name: str, tag: str, referred_by=None) -> User:
    u = User(
        earth_id=f"DLX-T{tag}{name.upper()}",
        full_name=f"آزمون {name}",
        status="active", currency="IRR", referred_by=referred_by,
    )
    db.add(u)
    await db.flush()
    return u


async def _balance(user_id) -> int:
    async with AsyncSessionLocal() as db:
        w = (await db.execute(select(Wallet).where(Wallet.user_id == user_id))).scalar_one_or_none()
        return int(w.balance_available) if w else 0


async def main():
    tag = _tag()
    async with AsyncSessionLocal() as db:
        l2 = await _mk_user(db, "L2", tag)
        l1 = await _mk_user(db, "L1", tag, referred_by=l2.id)
        buyer = await _mk_user(db, "Buyer", tag, referred_by=l1.id)
        seller = await _mk_user(db, "Seller", tag)

        db.add(Wallet(user_id=buyer.id, currency="IRR", balance_available=SEED))
        prod = ShopProduct(
            owner_id=seller.id, title=f"کالای آزمون {tag}", price=PRICE,
            currency="IRR", stock=10, is_active=True,
        )
        db.add(prod)
        await db.commit()
        ids = dict(l2=l2.id, l1=l1.id, buyer=buyer.id, seller=seller.id, prod=prod.id)
        buyer_eid, l1_eid = buyer.earth_id, l1.earth_id

    hb = {"Authorization": f"Bearer {create_access_token({'sub': str(ids['buyer'])})}"}
    hs = {"Authorization": f"Bearer {create_access_token({'sub': str(ids['seller'])})}"}
    h1 = {"Authorization": f"Bearer {create_access_token({'sub': str(ids['l1'])})}"}

    order_ref = None
    try:
        async with httpx.AsyncClient(timeout=20) as c:
            # ── ۱) خرید تا تسویه ───────────────────────────────────────────
            r = await c.post(f"{BASE}/shop/orders",
                             json={"product_id": str(ids["prod"]), "qty": 1}, headers=hb)
            check(r.status_code == 201, f"ثبتِ سفارش 201 ({r.status_code} {r.text[:120]})")
            order = r.json()
            order_ref = order["ref"]
            # مسیرهای تغییرِ وضعیت فقط `id` را می‌پذیرند (فقط GET با `ref` هم کار می‌کند)
            order_id = order["id"]
            check(await _balance(ids["buyer"]) == SEED - PRICE, "وجه از موجودیِ در‌دسترسِ خریدار بلوکه شد")

            r = await c.post(f"{BASE}/shop/orders/{order_id}/accept", headers=hs)
            check(r.status_code == 200, f"پذیرشِ فروشنده 200 ({r.status_code})")
            r = await c.post(f"{BASE}/shop/orders/{order_id}/ship", headers=hs)
            check(r.status_code == 200, f"ثبتِ ارسال 200 ({r.status_code})")
            r = await c.post(f"{BASE}/shop/orders/{order_id}/complete", headers=hb)
            check(r.status_code == 200, f"تأییدِ دریافت 200 ({r.status_code})")

            # ── ۲) کمیسیونِ دو سطح ─────────────────────────────────────────
            exp_l1 = PRICE * SHOP_LEVEL_RATES_BPS[0] // 10000
            exp_l2 = PRICE * SHOP_LEVEL_RATES_BPS[1] // 10000
            async with AsyncSessionLocal() as db:
                rows = (await db.execute(
                    select(MlmCommission).where(MlmCommission.reference_id == order_ref)
                )).scalars().all()
            got = {r_.level: r_ for r_ in rows}
            check(len(rows) == 2, f"دقیقاً دو سطح کمیسیون گرفتند ({len(rows)})")
            check(1 in got and got[1].amount == exp_l1 and got[1].earner_id == ids["l1"],
                  f"L1 = {exp_l1} به معرفِ مستقیم")
            check(2 in got and got[2].amount == exp_l2 and got[2].earner_id == ids["l2"],
                  f"L2 = {exp_l2} به معرفِ سطحِ دو")
            check(all(r_.source_type == "shop" for r_ in rows), "source_type=shop")
            check(await _balance(ids["l1"]) == exp_l1, "کمیسیونِ L1 واقعاً به کیفِ او نشست")
            check(await _balance(ids["l2"]) == exp_l2, "کمیسیونِ L2 واقعاً به کیفِ او نشست")

            # ── ۳) ناوردای حسابداری: پلتفرم ضرر نمی‌کند ────────────────────
            fee = PRICE * COMMISSION_PCT // 100
            paid = sum(int(r_.amount) for r_ in rows)
            check(paid < fee, f"جمعِ کمیسیون ({paid}) < کارمزدِ پلتفرم ({fee})")
            check(sum(SHOP_LEVEL_RATES_BPS) < COMMISSION_PCT * 100,
                  f"ناوردای نرخ: {sum(SHOP_LEVEL_RATES_BPS)}bps < {COMMISSION_PCT*100}bps")
            check(await _balance(ids["seller"]) == PRICE - fee, "فروشنده مبلغ منهای کارمزد گرفت")

            # پولی از هیچ ساخته نشده: کاهشِ خریدار = فروشنده + کارمزد
            spent = SEED - await _balance(ids["buyer"])
            check(spent == PRICE, "کلِ کسر از خریدار دقیقاً مبلغِ سفارش است")

            # ── ۴) تسویهٔ دوباره نباید کمیسیونِ دوباره بسازد ────────────────
            r = await c.post(f"{BASE}/shop/orders/{order_id}/complete", headers=hb)
            async with AsyncSessionLocal() as db:
                n = (await db.execute(
                    select(MlmCommission).where(MlmCommission.reference_id == order_ref)
                )).scalars().all()
            check(len(n) == 2, f"تسویهٔ تکراری کمیسیونِ جدید نساخت ({len(n)})")

            # ── ۵) قیفِ بازدید ─────────────────────────────────────────────
            r = await c.post(f"{BASE}/referral/track", json={"ref": l1_eid})
            check(r.status_code == 204, f"track بدونِ احراز 204 ({r.status_code})")
            r = await c.post(f"{BASE}/referral/track", json={"ref": l1_eid})
            check(r.status_code == 204, "بازدیدِ دوم هم 204")

            r = await c.post(f"{BASE}/referral/track", json={"ref": "DLX-NOSUCHXX"})
            check(r.status_code == 204, f"کدِ ناموجود هم 204 (اوراکل نیست) ({r.status_code})")

            r = await c.get(f"{BASE}/referral/funnel", headers=h1)
            check(r.status_code == 200, f"funnel 200 ({r.status_code})")
            f = r.json()
            check(f["clicks"] == 1, f"دو بازدیدِ یکسان در یک روز = ۱ کلیک ({f['clicks']})")
            check(f["signups"] == 0, f"هنوز عضویتی از این لینک ثبت نشده ({f['signups']})")
            check(f["conversion_pct"] == 0.0, f"نرخِ تبدیل صفر ({f['conversion_pct']})")

            # ── ۶) تبدیل: /apply باید signup ثبت کند ───────────────────────
            async with AsyncSessionLocal() as db:
                fresh = await _mk_user(db, "New", tag)
                await db.commit()
                fresh_id = fresh.id
            hn = {"Authorization": f"Bearer {create_access_token({'sub': str(fresh_id)})}"}
            r = await c.post(f"{BASE}/referral/apply", json={"ref_code": l1_eid}, headers=hn)
            check(r.status_code == 200, f"apply 200 ({r.status_code} {r.text[:100]})")

            r = await c.get(f"{BASE}/referral/funnel", headers=h1)
            f = r.json()
            check(f["signups"] == 1, f"عضویت در قیف ثبت شد ({f['signups']})")
            check(f["conversion_pct"] == 100.0, f"نرخِ تبدیل ۱۰۰٪ ({f['conversion_pct']})")
            check(len(f["daily"]) == 1, "روزِ امروز یک ردیفِ تجمیعی دارد")

            r = await c.post(f"{BASE}/referral/apply", json={"ref_code": l1_eid}, headers=hn)
            check(r.status_code == 400, f"ثبتِ دوبارهٔ معرف رد شد ({r.status_code})")
            r = await c.get(f"{BASE}/referral/funnel", headers=h1)
            check(r.json()["signups"] == 1, "apply تکراری قیف را باد نکرد")

            # ── ۷) نرخِ فروشگاه در stats دیده می‌شود ────────────────────────
            r = await c.get(f"{BASE}/referral/stats", headers=h1)
            s = r.json()
            check(s.get("shop_rates_bps") == SHOP_LEVEL_RATES_BPS, "stats نرخِ فروشگاه را می‌دهد")
            check(s["earned"].get("IRR") == exp_l1, "درآمدِ IRR در stats برابرِ کمیسیونِ فروش است")
            ids["fresh"] = fresh_id

            # ── ۸) کارتِ کالا در گفتگو ──────────────────────────────────────
            async with AsyncSessionLocal() as db:
                room = MessageRoom(type="direct")
                db.add(room)
                await db.flush()
                db.add(RoomMember(room_id=room.id, user_id=ids["seller"]))
                db.add(RoomMember(room_id=room.id, user_id=ids["buyer"]))
                await db.commit()
                room_id = room.id

            r = await c.post(f"{BASE}/shop/products/{ids['prod']}/share",
                             json={"room_id": str(room_id)}, headers=hs)
            check(r.status_code == 201, f"اشتراکِ کالا 201 ({r.status_code} {r.text[:120]})")
            async with AsyncSessionLocal() as db:
                m = (await db.execute(
                    select(Message).where(Message.room_id == room_id,
                                          Message.media_type == "product")
                )).scalars().all()
            check(len(m) == 1 and m[0].media_name == str(ids["prod"]),
                  "پیامِ product با idِ کالا ساخته شد")

            # غریبه نباید بتواند به این اتاق پیام تزریق کند
            r = await c.post(f"{BASE}/shop/products/{ids['prod']}/share",
                             json={"room_id": str(room_id)}, headers=h1)
            check(r.status_code == 403, f"غیرعضو رد شد ({r.status_code})")

            r = await c.post(f"{BASE}/shop/products/{_uuid.uuid4()}/share",
                             json={"room_id": str(room_id)}, headers=hs)
            check(r.status_code == 404, f"کالای ناموجود 404 ({r.status_code})")
            ids["room"] = room_id
    finally:
        # ── پاک‌سازی ────────────────────────────────────────────────────────
        uids = [v for k, v in ids.items() if k not in ("prod", "room")]
        async with AsyncSessionLocal() as db:
            if "room" in ids:
                await db.execute(delete(Message).where(Message.room_id == ids["room"]))
                await db.execute(delete(RoomMember).where(RoomMember.room_id == ids["room"]))
                await db.execute(delete(MessageRoom).where(MessageRoom.id == ids["room"]))
            await db.execute(delete(MlmCommission).where(MlmCommission.earner_id.in_(uids)))
            await db.execute(delete(ReferralClick).where(ReferralClick.ref_user_id.in_(uids)))
            await db.execute(delete(ShopOrderItem).where(ShopOrderItem.product_id == ids["prod"]))
            await db.execute(delete(ShopOrder).where(ShopOrder.buyer_id.in_(uids)))
            await db.execute(delete(ShopProduct).where(ShopProduct.id == ids["prod"]))
            await db.execute(text(
                "DELETE FROM wallet_transactions WHERE wallet_id IN "
                "(SELECT id FROM wallets WHERE user_id = ANY(:u))"
            ), {"u": uids})
            await db.execute(delete(Wallet).where(Wallet.user_id.in_(uids)))
            await db.execute(text("DELETE FROM users WHERE id = ANY(:u)"), {"u": uids})
            await db.commit()
        async with AsyncSessionLocal() as db:
            left = (await db.execute(
                select(User).where(User.earth_id.like(f"DLX-T{tag}%"))
            )).scalars().all()
        check(not left, f"کاربرانِ آزمایشی پاک شدند ({len(left)} مانده)")

    await engine.dispose()
    print(f"\n== {passed} passed, {failed} failed ==")
    return 1 if failed else 0


raise SystemExit(asyncio.run(main()))

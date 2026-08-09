"""E2E: موجِ B فروشگاه — گونه/چندتصویری، کدِ تخفیف، نظر، سبدِ چندفروشنده.

روی سرور اجرا می‌شود:  cd /var/www/dilix-api && venv/bin/python _shop_v2_e2e.py

سه فروشنده و یک خریدار می‌سازد (یک‌بارمصرف، تگِ تصادفی)، هیچ حسابِ واقعی را
دست نمی‌زند و در پایان همه‌چیز را پاک می‌کند.
"""
import asyncio
import uuid as _uuid

import httpx
from sqlalchemy import delete, select, text

from app.core.database import AsyncSessionLocal, engine
from app.core.security import create_access_token
from app.models.user import User
from app.models.wallet import Wallet
from app.api.v1.shop.router import (
    ShopCoupon, ShopOrder, ShopOrderItem, ShopProduct, ShopProductVariant,
    ShopReview,
)

BASE = "http://127.0.0.1:8000/api/v1"
PRICE = 1_000_000
SEED = 20_000_000

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


async def _mk_user(db, name: str, tag: str) -> User:
    u = User(earth_id=f"DLX-T{tag}{name.upper()}", full_name=f"آزمون {name}",
              status="active", currency="IRR")
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
        buyer = await _mk_user(db, "Buyer", tag)
        s1 = await _mk_user(db, "S1", tag)
        s2 = await _mk_user(db, "S2", tag)
        db.add(Wallet(user_id=buyer.id, currency="IRR", balance_available=SEED))

        p1 = ShopProduct(owner_id=s1.id, title=f"کالای رنگی {tag}", price=PRICE,
                          currency="IRR", stock=-1, is_active=True,
                          images=["https://x/a.jpg", "https://x/b.jpg"])
        p2 = ShopProduct(owner_id=s2.id, title=f"کالای ساده {tag}", price=PRICE,
                          currency="IRR", stock=-1, is_active=True)
        db.add_all([p1, p2])
        await db.commit()
        ids = dict(buyer=buyer.id, s1=s1.id, s2=s2.id, p1=p1.id, p2=p2.id)

    hb = {"Authorization": f"Bearer {create_access_token({'sub': str(ids['buyer'])})}"}
    h1 = {"Authorization": f"Bearer {create_access_token({'sub': str(ids['s1'])})}"}
    h2 = {"Authorization": f"Bearer {create_access_token({'sub': str(ids['s2'])})}"}

    order_ids_to_clean = []
    try:
        async with httpx.AsyncClient(timeout=20) as c:
            # ── ۱) چندتصویری ────────────────────────────────────────────────
            r = await c.get(f"{BASE}/shop/products/{ids['p1']}", headers=hb)
            check(r.status_code == 200 and r.json()["images"] == ["https://x/a.jpg", "https://x/b.jpg"],
                  f"images روی کالا برمی‌گردد ({r.json().get('images')})")

            # ── ۲) گونه‌ها ───────────────────────────────────────────────────
            r = await c.post(f"{BASE}/shop/products/{ids['p1']}/variants",
                             json={"name": "قرمز", "stock": 1}, headers=h1)
            check(r.status_code == 201, f"افزودنِ گونهٔ قرمز 201 ({r.status_code})")
            v_red = r.json()["id"]
            r = await c.post(f"{BASE}/shop/products/{ids['p1']}/variants",
                             json={"name": "آبی", "stock": 0}, headers=h1)
            check(r.status_code == 201, "افزودنِ گونهٔ آبی 201")
            v_blue = r.json()["id"]

            r = await c.get(f"{BASE}/shop/products/{ids['p1']}", headers=hb)
            check(r.json()["has_variants"] is True, "has_variants=true پس از افزودنِ گونه")

            r = await c.post(f"{BASE}/shop/orders",
                             json={"product_id": str(ids["p1"]), "qty": 1}, headers=hb)
            check(r.status_code == 400, f"خریدِ بدونِ انتخابِ گونه رد شد ({r.status_code})")

            r = await c.post(f"{BASE}/shop/orders",
                             json={"product_id": str(ids["p1"]), "variant_id": v_blue, "qty": 1},
                             headers=hb)
            check(r.status_code == 409, f"گونهٔ بی‌موجودی رد شد ({r.status_code})")

            r = await c.post(f"{BASE}/shop/orders",
                             json={"product_id": str(ids["p1"]), "variant_id": v_red, "qty": 1},
                             headers=hb)
            check(r.status_code == 201, f"خریدِ گونهٔ قرمز 201 ({r.status_code} {r.text[:120]})")
            variant_order = r.json()
            order_ids_to_clean.append(variant_order["id"])
            check(variant_order["items"][0]["variant_id"] == v_red, "ردیفِ سفارش variant_id درست دارد")

            r = await c.get(f"{BASE}/shop/products/{ids['p1']}/variants", headers=hb)
            reds = [v for v in r.json() if v["id"] == v_red]
            check(reds and reds[0]["stock"] == 0, "موجودیِ گونهٔ قرمز اتمیک کم شد")

            # لغو → بازگشتِ موجودیِ همان گونه
            r = await c.post(f"{BASE}/shop/orders/{variant_order['id']}/cancel", headers=hb)
            check(r.status_code == 200, f"لغوِ سفارشِ گونه‌دار 200 ({r.status_code})")
            r = await c.get(f"{BASE}/shop/products/{ids['p1']}/variants", headers=hb)
            reds = [v for v in r.json() if v["id"] == v_red]
            check(reds and reds[0]["stock"] == 1, "لغو موجودیِ گونه را برگرداند")

            # ── ۳) کدِ تخفیف روی خریدِ تکی ──────────────────────────────────
            r = await c.post(f"{BASE}/shop/coupons",
                             json={"code": f"OFF{tag}", "discount_type": "fixed",
                                   "discount_value": 100_000, "product_id": str(ids["p2"]),
                                   "max_uses": 1}, headers=h2)
            check(r.status_code == 201, f"ساختِ کدِ تخفیف 201 ({r.status_code} {r.text[:120]})")
            coupon_code = r.json()["code"]

            bal_before = await _balance(ids["buyer"])
            r = await c.post(f"{BASE}/shop/orders",
                             json={"product_id": str(ids["p2"]), "qty": 1, "coupon_code": coupon_code},
                             headers=hb)
            check(r.status_code == 201, f"خریدِ کدِتخفیف‌دار 201 ({r.status_code} {r.text[:120]})")
            disc_order = r.json()
            order_ids_to_clean.append(disc_order["id"])
            check(disc_order["discount"] == 100_000, f"تخفیف اعمال شد ({disc_order['discount']})")
            check(disc_order["total"] == PRICE - 100_000, f"total پس از تخفیف ({disc_order['total']})")
            check(bal_before - await _balance(ids["buyer"]) == PRICE - 100_000,
                  "دقیقاً همان مبلغِ تخفیف‌خورده از خریدار کم شد")

            # مصرفِ دوباره باید رد شود (max_uses=1)
            r = await c.post(f"{BASE}/shop/orders",
                             json={"product_id": str(ids["p2"]), "qty": 1, "coupon_code": coupon_code},
                             headers=hb)
            check(r.status_code == 409, f"کدِ تمام‌شده رد شد ({r.status_code})")

            # ── ۴) نظر — فقط پس از تکمیل ────────────────────────────────────
            r = await c.post(f"{BASE}/shop/orders/{disc_order['id']}/review",
                             json={"product_id": str(ids["p2"]), "rating": 5}, headers=hb)
            check(r.status_code == 400, f"نظر پیش از تکمیل رد شد ({r.status_code})")

            r = await c.post(f"{BASE}/shop/orders/{disc_order['id']}/accept", headers=h2)
            check(r.status_code == 200, "پذیرشِ فروشنده")
            r = await c.post(f"{BASE}/shop/orders/{disc_order['id']}/ship", headers=h2)
            check(r.status_code == 200, "ارسال")
            r = await c.post(f"{BASE}/shop/orders/{disc_order['id']}/complete", headers=hb)
            check(r.status_code == 200, "تکمیل")

            r = await c.post(f"{BASE}/shop/orders/{disc_order['id']}/review",
                             json={"product_id": str(ids["p1"]), "rating": 5}, headers=hb)
            check(r.status_code == 400, f"نظر برای کالای بیرون از سفارش رد شد ({r.status_code})")

            r = await c.post(f"{BASE}/shop/orders/{disc_order['id']}/review",
                             json={"product_id": str(ids["p2"]), "rating": 4, "comment": "خوب بود"},
                             headers=hb)
            check(r.status_code == 201, f"ثبتِ نظر 201 ({r.status_code} {r.text[:120]})")

            r = await c.post(f"{BASE}/shop/orders/{disc_order['id']}/review",
                             json={"product_id": str(ids["p2"]), "rating": 3}, headers=hb)
            check(r.status_code == 409, f"نظرِ تکراری رد شد ({r.status_code})")

            r = await c.get(f"{BASE}/shop/products/{ids['p2']}/reviews", headers=hb)
            check(r.status_code == 200 and len(r.json()) == 1 and r.json()[0]["rating"] == 4,
                  "لیستِ نظرات درست است")

            r = await c.get(f"{BASE}/shop/products/{ids['p2']}", headers=hb)
            pr = r.json()
            check(pr["rating_avg"] == 4.0 and pr["rating_count"] == 1,
                  f"میانگینِ امتیاز روی کالا ({pr['rating_avg']}, {pr['rating_count']})")

            # ── ۵) سبدِ چندفروشنده در یک تراکنش ─────────────────────────────
            bal_before = await _balance(ids["buyer"])
            r = await c.post(f"{BASE}/shop/cart/checkout", json={"items": [
                {"product_id": str(ids["p1"]), "variant_id": v_red, "qty": 1},
                {"product_id": str(ids["p2"]), "qty": 2},
            ]}, headers=hb)
            check(r.status_code == 201, f"چک‌اوتِ سبد 201 ({r.status_code} {r.text[:160]})")
            cart_orders = r.json()
            for o in cart_orders:
                order_ids_to_clean.append(o["id"])
            check(len(cart_orders) == 2, f"دو سفارشِ جدا برای دو فروشنده ({len(cart_orders)})")
            sellers = {o["seller_earth_id"] for o in cart_orders}
            check(len(sellers) == 2, "هر سفارش فروشندهٔ خودش را دارد")
            by_seller = {o["seller_earth_id"]: o for o in cart_orders}
            o1 = next(o for o in cart_orders if o["product_id"] == str(ids["p1"]))
            o2 = next(o for o in cart_orders if o["product_id"] == str(ids["p2"]))
            check(o1["total"] == PRICE, f"سفارشِ فروشندهٔ ۱ = {PRICE} ({o1['total']})")
            check(o2["total"] == PRICE * 2, f"سفارشِ فروشندهٔ ۲ = {PRICE*2} ({o2['total']})")
            check(bal_before - await _balance(ids["buyer"]) == PRICE * 3,
                  "جمعِ برداشت از خریدار = جمعِ دو سفارش")

            r = await c.get(f"{BASE}/shop/products/{ids['p1']}/variants", headers=hb)
            reds = [v for v in r.json() if v["id"] == v_red]
            check(reds and reds[0]["stock"] == 0, "موجودیِ گونه از سبد هم اتمیک کم شد")

            # خریدِ کالای خودتان در سبد باید رد شود
            r = await c.post(f"{BASE}/shop/cart/checkout",
                             json={"items": [{"product_id": str(ids["p2"]), "qty": 1}]}, headers=h2)
            check(r.status_code == 400, f"خریدِ کالای خودتان در سبد رد شد ({r.status_code})")

            # کمبودِ موجودی در یک ردیف کلِ سبد را برمی‌گرداند (اتمیک)
            r = await c.post(f"{BASE}/shop/products/{ids['p1']}/variants",
                             json={"name": "سبز", "stock": 1}, headers=h1)
            v_green = r.json()["id"]
            bal_before = await _balance(ids["buyer"])
            r = await c.post(f"{BASE}/shop/cart/checkout", json={"items": [
                {"product_id": str(ids["p1"]), "variant_id": v_green, "qty": 1},
                {"product_id": str(ids["p1"]), "variant_id": v_green, "qty": 5},  # قطعاً بیشتر از موجودی
            ]}, headers=hb)
            check(r.status_code >= 400, f"سبدِ ناتمام رد شد ({r.status_code})")
            r = await c.get(f"{BASE}/shop/products/{ids['p1']}/variants", headers=hb)
            greens = [v for v in r.json() if v["id"] == v_green]
            check(greens and greens[0]["stock"] == 1,
                  "شکستِ یک ردیف موجودیِ ردیفِ دیگر را هم برگرداند (rollback)")
            check(await _balance(ids["buyer"]) == bal_before, "پولِ خریدار بابتِ سبدِ شکست‌خورده دست‌نخورده ماند")

    finally:
        uids = [ids["buyer"], ids["s1"], ids["s2"]]
        pids = [ids["p1"], ids["p2"]]
        async with AsyncSessionLocal() as db:
            if order_ids_to_clean:
                await db.execute(delete(ShopReview).where(ShopReview.order_id.in_(order_ids_to_clean)))
                await db.execute(delete(ShopOrderItem).where(ShopOrderItem.order_id.in_(order_ids_to_clean)))
            await db.execute(delete(ShopOrder).where(ShopOrder.buyer_id.in_(uids)))
            await db.execute(delete(ShopCoupon).where(ShopCoupon.owner_id.in_(uids)))
            await db.execute(delete(ShopProductVariant).where(ShopProductVariant.product_id.in_(pids)))
            await db.execute(delete(ShopProduct).where(ShopProduct.id.in_(pids)))
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

"""
Dilix — MLM commission engine (موتورِ کمیسیونِ بازاریابیِ چندسطحی).

`distribute_commission` زنجیرهٔ بالادستِ معرف (`User.referred_by`) را تا `MAX_LEVEL`
بالا می‌رود و به هر سطح، درصدی از مبلغِ فعالیتِ زیرمجموعه را به‌عنوانِ درآمدِ رفرال
پرداخت می‌کند. درآمد به کیف‌پولِ پایه (`WalletTransaction type=bonus`) یا — اگر ارز با
ارزِ پایهٔ بالادست فرق کند — به جیبِ ارزیِ او ([[wallet_holdings]]) واریز می‌شود، پس
درآمدِ بازاریاب می‌تواند دلاری/یورویی هم باشد. هر پرداخت در `mlm_commissions` ثبت می‌شود.

فراخوان باید در همان تراکنش commit کند (این سرویس commit نمی‌کند).
"""
from typing import List, Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User
from app.models.wallet import Wallet, WalletTransaction
from app.models.holdings import WalletHolding
from app.models.mlm import MlmCommission

# نرخِ هر سطح به basis-point (۱۰۰۰۰=۱۰۰٪). پاداشِ رفرالِ پلتفرم‌محور، قابلِ تنظیم.
LEVEL_RATES_BPS = [800, 300, 100]   # L1 ۸٪ · L2 ۳٪ · L3 ۱٪
MAX_LEVEL = len(LEVEL_RATES_BPS)


async def _get_or_create_wallet(db: AsyncSession, user_id, default_cur: str = "IRR") -> Wallet:
    res = await db.execute(select(Wallet).where(Wallet.user_id == user_id))
    w = res.scalar_one_or_none()
    if w is None:
        w = Wallet(user_id=user_id, currency=default_cur)
        db.add(w)
        await db.flush()
    return w


async def _get_or_create_holding(db: AsyncSession, user_id, cur: str) -> WalletHolding:
    res = await db.execute(
        select(WalletHolding).where(
            WalletHolding.user_id == user_id, WalletHolding.currency == cur
        )
    )
    h = res.scalar_one_or_none()
    if h is None:
        h = WalletHolding(user_id=user_id, currency=cur, balance=0)
        db.add(h)
        await db.flush()
    return h


async def distribute_commission(
    db: AsyncSession,
    source_user_id,
    base_amount: int,
    currency: str,
    source_type: str = "topup",
    reference_id: Optional[str] = None,
) -> List[dict]:
    """کمیسیونِ چندسطحی را بالادستِ زنجیرهٔ معرف توزیع می‌کند و لیستِ پرداخت‌ها را برمی‌گرداند."""
    cur = (currency or "IRR").upper()
    payouts: List[dict] = []
    if not base_amount or base_amount <= 0:
        return payouts

    res = await db.execute(select(User).where(User.id == source_user_id))
    node = res.scalar_one_or_none()
    if node is None:
        return payouts

    visited = {source_user_id}
    level = 1
    while node is not None and node.referred_by is not None and level <= MAX_LEVEL:
        up_id = node.referred_by
        if up_id in visited:          # حلقه → توقف
            break
        visited.add(up_id)
        res = await db.execute(select(User).where(User.id == up_id))
        upline = res.scalar_one_or_none()
        if upline is None:
            break

        rate = LEVEL_RATES_BPS[level - 1]
        comm = (base_amount * rate) // 10000
        if comm > 0:
            up_wallet = await _get_or_create_wallet(
                db, upline.id, (getattr(upline, "currency", None) or "IRR")
            )
            base_cur = (up_wallet.currency or "IRR").upper()
            if cur == base_cur:
                before = up_wallet.balance_available
                up_wallet.balance_available = before + comm
                db.add(WalletTransaction(
                    wallet_id=up_wallet.id, type="bonus", status="completed",
                    amount=comm, balance_before=before, balance_after=up_wallet.balance_available,
                    description=f"پاداشِ رفرال (سطح {level})", reference_id=reference_id,
                    metadata_={"kind": "mlm_commission", "level": level, "rate_bps": rate,
                               "source_type": source_type, "source_user_id": str(source_user_id),
                               "currency": cur},
                ))
            else:
                h = await _get_or_create_holding(db, upline.id, cur)
                h.balance += comm
            db.add(MlmCommission(
                earner_id=upline.id, source_user_id=source_user_id, level=level,
                rate_bps=rate, amount=comm, currency=cur, source_type=source_type,
                reference_id=reference_id,
            ))
            payouts.append({"earner_id": str(upline.id), "level": level,
                            "amount": comm, "currency": cur, "rate_bps": rate})

        node = upline
        level += 1

    return payouts

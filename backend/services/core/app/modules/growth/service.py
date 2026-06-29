"""سرویس Growth — تجمیعِ خواندنی روی referral / membership / investment.

revenue-share (Vanguard-style): نرخِ سهمِ عضو از درآمدِ کارمزدِ پلتفرم بر پایه‌ی
طرحِ عضویت و موقعیتِ سرمایه‌گذاری محاسبه می‌شود — نه پاداشِ عضوگیری.
"""
from __future__ import annotations

import uuid

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.modules.growth.schemas import (
    ReferralLinkOut,
    RevenueShareOut,
    RewardBalance,
    RewardWalletOut,
)
from app.modules.investment.models import InvestmentPosition
from app.modules.membership.models import (
    PLAN_FREE,
    PLAN_PREMIUM,
    PLAN_STANDARD,
    STATUS_ACTIVE,
    MembershipSubscription,
)
from app.modules.referral.models import (
    STATUS_PENDING,
    STATUS_REWARDED,
    Referral,
)

# نرخِ پایه‌ی سهم از درآمدِ کارمزد برحسبِ basis points، بر اساسِ طرحِ عضویت
_PLAN_REVENUE_SHARE_BPS: dict[str, int] = {
    PLAN_FREE: 0,
    PLAN_STANDARD: 50,    # ۰.۵٪
    PLAN_PREMIUM: 150,    # ۱.۵٪
}
# سقفِ افزایشِ سهم به‌ازای داشتنِ موقعیتِ سرمایه‌گذاری (Vanguard-style)
_INVESTOR_BONUS_BPS = 100


def _invite_code(earth_id: uuid.UUID) -> str:
    """کدِ دعوتِ قطعی و کوتاه از روی earth_id."""
    return earth_id.hex[:10]


async def referral_link(db: AsyncSession, earth_id: uuid.UUID) -> ReferralLinkOut:
    code = _invite_code(earth_id)
    count = await db.scalar(
        select(func.count())
        .select_from(Referral)
        .where(Referral.referrer_earth_id == earth_id)
    )
    base = get_settings().public_app_url.rstrip("/")
    return ReferralLinkOut(
        code=code,
        url=f"{base}/invite/{code}",
        total_referred=int(count or 0),
    )


async def reward_wallet(db: AsyncSession, earth_id: uuid.UUID) -> RewardWalletOut:
    # فقط پاداش‌هایِ gated به reward_event واقعی (status=rewarded و reward_minor موجود)
    rows = await db.execute(
        select(
            Referral.currency,
            func.coalesce(func.sum(Referral.reward_minor), 0),
            func.count(),
        )
        .where(
            Referral.referrer_earth_id == earth_id,
            Referral.status == STATUS_REWARDED,
            Referral.reward_minor.isnot(None),
        )
        .group_by(Referral.currency)
    )
    balances = [
        RewardBalance(currency=cur, amount_minor=int(total), reward_count=int(cnt))
        for cur, total, cnt in rows.all()
    ]
    pending = await db.scalar(
        select(func.count())
        .select_from(Referral)
        .where(
            Referral.referrer_earth_id == earth_id,
            Referral.status == STATUS_PENDING,
        )
    )
    return RewardWalletOut(balances=balances, pending_count=int(pending or 0))


async def revenue_share(db: AsyncSession, earth_id: uuid.UUID) -> RevenueShareOut:
    sub = await db.scalar(
        select(MembershipSubscription).where(
            MembershipSubscription.earth_id == earth_id,
            MembershipSubscription.status == STATUS_ACTIVE,
        )
    )
    plan = sub.plan if sub else PLAN_FREE

    units = await db.scalar(
        select(func.coalesce(func.sum(InvestmentPosition.units), 0.0)).where(
            InvestmentPosition.earth_id == earth_id,
            InvestmentPosition.status == "active",
        )
    )
    units = float(units or 0.0)

    bps = _PLAN_REVENUE_SHARE_BPS.get(plan, 0)
    if units > 0:
        bps += _INVESTOR_BONUS_BPS

    eligible = bps > 0
    if not eligible:
        note = "برای دریافتِ سهم از درآمد، عضویت را ارتقا دهید یا در صندوقِ مجاز سرمایه‌گذاری کنید."
    else:
        note = "سهم از درآمدِ خالصِ کارمزدِ پلتفرم؛ تسویه دوره‌ای از طریقِ کیفِ پاداش."

    return RevenueShareOut(
        eligible=eligible,
        plan=plan,
        entitlement_bps=bps,
        investment_units=units,
        note=note,
    )

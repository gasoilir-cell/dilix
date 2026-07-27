"""
Dilix — سهم از درآمد (Revenue Share)

    GET /api/v1/growth/revenue-share   نرخِ سهمِ من از درآمدِ کارمزدِ پلتفرم

این ماژول **جدولِ خودش را ندارد** و کاملاً خواندنی است: نرخ از طرحِ عضویت و
موقعیتِ سرمایه‌گذاریِ واقعیِ کاربر مشتق می‌شود. اگر عدد را جدا ذخیره می‌کردیم،
با لغوِ عضویت یا فروشِ واحدها بی‌صدا کهنه می‌شد و کاربر سهمی می‌دید که دیگر
مستحقش نبود.

مدل (Vanguard-style): سهم پاداشِ عضوگیری نیست؛ حقِ کسی است که یا مشترکِ پولیِ
پلتفرم است یا در صندوق‌های آن سرمایه گذاشته.
"""
from typing import Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.api.v1.investment.router import STATUS_ACTIVE, InvestmentPosition
from app.api.v1.membership.router import (
    PLAN_FREE, PLAN_PREMIUM, PLAN_STANDARD, Membership, _apply_expiry,
)
from app.core.database import get_db
from app.models.user import User

router = APIRouter(prefix="/growth", tags=["Growth"])

# نرخِ پایهٔ سهم برحسبِ basis point، بر اساسِ طرحِ عضویت
PLAN_SHARE_BPS: dict[str, int] = {
    PLAN_FREE: 0,
    PLAN_STANDARD: 50,    # ۰.۵٪
    PLAN_PREMIUM: 150,    # ۱.۵٪
}
# افزایشِ سهم برای کسی که موقعیتِ سرمایه‌گذاریِ فعال دارد
INVESTOR_BONUS_BPS = 100


class RevenueShareOut(BaseModel):
    eligible:         bool
    plan:             str
    entitlement_bps:  int
    investment_units: int
    note:             str


@router.get("/revenue-share", response_model=RevenueShareOut)
async def revenue_share(
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    m: Optional[Membership] = (await db.execute(
        select(Membership).where(Membership.user_id == me.id)
    )).scalar_one_or_none()
    plan = PLAN_FREE
    if m is not None:
        # همان قاعدهٔ انقضای ماژولِ عضویت؛ طرحِ سررسیدشده نباید سهم بدهد.
        plan = _apply_expiry(m).plan

    units = float((await db.scalar(
        select(func.coalesce(func.sum(InvestmentPosition.units), 0.0)).where(
            InvestmentPosition.user_id == me.id,
            InvestmentPosition.status == STATUS_ACTIVE,
        )
    )) or 0.0)

    bps = PLAN_SHARE_BPS.get(plan, 0)
    if units > 0:
        bps += INVESTOR_BONUS_BPS

    if bps > 0:
        note = (
            f"سهمِ شما {bps / 100:.2f}٪ از درآمدِ کارمزدِ پلتفرم است "
            f"و ماهانه به کیفِ پول واریز می‌شود."
        )
    else:
        note = (
            "با ارتقای عضویت یا خریدِ واحدِ صندوق، از درآمدِ کارمزدِ پلتفرم "
            "سهم می‌برید."
        )

    return RevenueShareOut(
        eligible=bps > 0, plan=plan, entitlement_bps=bps,
        investment_units=int(units), note=note,
    )

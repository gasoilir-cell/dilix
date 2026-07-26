"""
Dilix — FX Router (نرخِ ارز + تبدیل). لایهٔ جهانیِ پول.

GET  /api/v1/fx/rates    نرخِ همهٔ ارزها (پایه USD)
POST /api/v1/fx/quote    تبدیلِ مبلغ بینِ دو ارز (واحدِ خرد)
POST /api/v1/fx/refresh  به‌روزرسانیِ نرخِ IRR از فیدِ زنده (مدیر)
"""
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.models.fx import FxRate
from app.services.fx import get_rate_map, convert_minor, unit_rate, minor_scale
from app.services.fx_feed import refresh_irr_from_feed

router = APIRouter(prefix="/fx", tags=["fx"])

ADMIN_ROLES = {"admin", "super_admin"}


class QuoteIn(BaseModel):
    amount: int = Field(gt=0, description="مبلغ در واحدِ خردِ ارزِ مبدأ")
    from_currency: str = Field(min_length=3, max_length=3)
    to_currency: str = Field(min_length=3, max_length=3)


@router.get("/rates")
async def list_rates(db: AsyncSession = Depends(get_db)):
    res = await db.execute(select(FxRate).order_by(FxRate.currency))
    rows = res.scalars().all()
    return {
        "base": "USD",
        "rates": {r.currency.upper(): r.usd_per_unit for r in rows},
        "updated_at": max((r.updated_at for r in rows), default=datetime.now(timezone.utc)).isoformat()
            if rows else None,
    }


@router.post("/quote")
async def quote(body: QuoteIn, db: AsyncSession = Depends(get_db)):
    frm, to = body.from_currency.upper(), body.to_currency.upper()
    rates = await get_rate_map(db)
    try:
        converted = convert_minor(body.amount, frm, to, rates)
        rate = unit_rate(frm, to, rates)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    return {
        "from_currency": frm,
        "to_currency": to,
        "amount": body.amount,
        "converted": converted,
        "rate": rate,
        "from_scale": minor_scale(frm),
        "to_scale": minor_scale(to),
    }


@router.post("/refresh")
async def refresh_rates(
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """به‌روزرسانیِ دستیِ نرخِ IRR از فیدِ زندهٔ tgju (فقط مدیر).

    حلقهٔ دوره‌ای هم در پس‌زمینه همین کار را می‌کند؛ این اندپوینت برای trigger فوری است.
    """
    if getattr(me, "role", None) not in ADMIN_ROLES:
        raise HTTPException(status_code=403, detail="دسترسیِ مدیر لازم است")
    return await refresh_irr_from_feed(db)

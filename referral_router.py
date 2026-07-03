"""
Dilix — Referral Router
GET  /api/v1/referral/stats  → آمار رفرال‌های من
POST /api/v1/referral/register-ref  → ثبت رفرال‌کد هنگام ورود اول
"""
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import Column, func, select, text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.api.deps import get_current_user
from app.models.user import User

router = APIRouter(prefix="/referral", tags=["Referral"])

SITE_URL = "https://dilix.ir"


class ApplyRefRequest(BaseModel):
    ref_code: str = Field(..., description="earth_id رفرر")


# ─── GET /referral/stats ─────────────────────────────────────────────────────
@router.get("/stats")
async def referral_stats(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    # تعداد کاربرانی که این کاربر آن‌ها را معرفی کرده
    q = await db.execute(
        select(func.count()).select_from(User).where(User.referred_by == current_user.id)
    )
    total_referred = q.scalar() or 0

    # پاداش رفرال از تراکنش‌های کیف‌پول (اگر وجود داشت)
    # فعلاً هر معرفی = ۵۰۰۰۰ تومان پاداش فرضی (در آینده از wallet tx محاسبه می‌شود)
    REWARD_PER_REFERRAL = 50_000
    total_reward = total_referred * REWARD_PER_REFERRAL

    ref_link = f"{SITE_URL}/join?ref={current_user.earth_id}"

    return {
        "code": current_user.earth_id,
        "link": ref_link,
        "total_referred": total_referred,
        "total_reward_toman": total_reward,
        "reward_per_referral": REWARD_PER_REFERRAL,
    }


# ─── POST /referral/apply ────────────────────────────────────────────────────
@router.post("/apply")
async def apply_referral(
    body: ApplyRefRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """یک‌بار بعد از ثبت‌نام، کد رفرال رفرر را ثبت می‌کند"""

    if current_user.referred_by is not None:
        raise HTTPException(400, "کد رفرال قبلاً ثبت شده")

    # پیدا کردن رفرر با earth_id
    q = await db.execute(
        select(User).where(User.earth_id == body.ref_code.upper())
    )
    referrer = q.scalar_one_or_none()

    if not referrer:
        raise HTTPException(404, "کد رفرال معتبر نیست")

    if referrer.id == current_user.id:
        raise HTTPException(400, "نمی‌توانی کد خودت را وارد کنی")

    # ثبت referred_by
    current_user.referred_by = referrer.id
    await db.commit()

    return {"ok": True, "referred_by": referrer.full_name or referrer.earth_id}

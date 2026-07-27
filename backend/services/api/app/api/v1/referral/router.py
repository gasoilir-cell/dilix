"""
Dilix — Referral / MLM Router (بازاریابیِ شبکه‌ایِ چندسطحی)
GET  /api/v1/referral/stats        → آمار: کد/لینک، مستقیم، کلِ شبکه، درآمدِ کسب‌شده
POST /api/v1/referral/apply        → ثبتِ معرف (earth_id) با محافظت در برابرِ حلقه
GET  /api/v1/referral/network      → شمارِ زیرمجموعه به تفکیکِ سطح + فهرستِ مستقیم‌ها
GET  /api/v1/referral/commissions  → لِجِرِ کمیسیون‌های من + جمعِ درآمد به تفکیکِ ارز
GET  /api/v1/referral/qr           → QRِ دعوت (SVG) که به /join?ref=… می‌رسد

زنجیرهٔ معرف روی `User.referred_by` است؛ کمیسیونِ چندسطحی توسطِ
`app/services/mlm.py::distribute_commission` هنگامِ فعالیتِ زیرمجموعه (مثلِ شارژِ کیف)
توزیع می‌شود. نرخ‌های سطح: L1 ۸٪ · L2 ۳٪ · L3 ۱٪.
"""
import io as _io
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel, Field
from sqlalchemy import func, select

from app.core.database import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.models.mlm import MlmCommission
from app.services.mlm import LEVEL_RATES_BPS, MAX_LEVEL

from sqlalchemy.ext.asyncio import AsyncSession

router = APIRouter(prefix="/referral", tags=["Referral"])

SITE_URL = "https://dilix.ir"


class ApplyRefRequest(BaseModel):
    ref_code: str = Field(..., description="earth_id رفرر")


async def _earned_by_currency(db: AsyncSession, user_id) -> dict:
    res = await db.execute(
        select(MlmCommission.currency, func.sum(MlmCommission.amount))
        .where(MlmCommission.earner_id == user_id)
        .group_by(MlmCommission.currency)
    )
    return {cur: int(s or 0) for cur, s in res.all()}


async def _network_counts(db: AsyncSession, root_id) -> tuple:
    """شمارِ زیرمجموعه به تفکیکِ سطح (۱..MAX_LEVEL) + کاربرانِ سطحِ ۱."""
    levels: List[dict] = []
    direct_users: List[User] = []
    frontier = [root_id]
    total = 0
    for lvl in range(1, MAX_LEVEL + 1):
        if not frontier:
            levels.append({"level": lvl, "count": 0, "rate_bps": LEVEL_RATES_BPS[lvl - 1]})
            continue
        res = await db.execute(select(User).where(User.referred_by.in_(frontier)))
        users = res.scalars().all()
        if lvl == 1:
            direct_users = users
        ids = [u.id for u in users]
        levels.append({"level": lvl, "count": len(ids), "rate_bps": LEVEL_RATES_BPS[lvl - 1]})
        total += len(ids)
        frontier = ids
    return levels, total, direct_users


# ─── GET /referral/stats ─────────────────────────────────────────────────────
@router.get("/stats")
async def referral_stats(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    q = await db.execute(
        select(func.count()).select_from(User).where(User.referred_by == current_user.id)
    )
    total_referred = q.scalar() or 0

    _, total_network, _ = await _network_counts(db, current_user.id)
    earned = await _earned_by_currency(db, current_user.id)

    # سازگاریِ عقب‌رو: فیلدِ قدیمیِ پاداشِ فرضی حفظ می‌شود
    REWARD_PER_REFERRAL = 50_000
    ref_link = f"{SITE_URL}/join?ref={current_user.earth_id}"

    return {
        "code": current_user.earth_id,
        "link": ref_link,
        "total_referred": total_referred,
        "total_network": total_network,
        "earned": earned,                       # {ارز: مبلغِ واحدِ خرد}
        "level_rates_bps": LEVEL_RATES_BPS,
        "total_reward_toman": total_referred * REWARD_PER_REFERRAL,
        "reward_per_referral": REWARD_PER_REFERRAL,
    }


# ─── POST /referral/apply ────────────────────────────────────────────────────
@router.post("/apply")
async def apply_referral(
    body: ApplyRefRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """یک‌بار بعد از ثبت‌نام، معرفِ کاربر را (با earth_id) ثبت می‌کند."""
    if current_user.referred_by is not None:
        raise HTTPException(400, "کد رفرال قبلاً ثبت شده")

    q = await db.execute(select(User).where(User.earth_id == body.ref_code.upper()))
    referrer = q.scalar_one_or_none()
    if not referrer:
        raise HTTPException(404, "کد رفرال معتبر نیست")
    if referrer.id == current_user.id:
        raise HTTPException(400, "نمی‌توانی کد خودت را وارد کنی")

    # محافظت در برابرِ حلقه: current_user نباید بالادستِ referrer باشد
    cursor: Optional[User] = referrer
    hops = 0
    while cursor is not None and cursor.referred_by is not None and hops < 100:
        if cursor.referred_by == current_user.id:
            raise HTTPException(400, "این کد باعثِ حلقه در شبکه می‌شود")
        r = await db.execute(select(User).where(User.id == cursor.referred_by))
        cursor = r.scalar_one_or_none()
        hops += 1

    current_user.referred_by = referrer.id
    await db.commit()
    return {"ok": True, "referred_by": referrer.full_name or referrer.earth_id}


# ─── GET /referral/network ───────────────────────────────────────────────────
@router.get("/network")
async def referral_network(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    levels, total, direct = await _network_counts(db, current_user.id)
    return {
        "levels": levels,
        "total_network": total,
        "direct": [
            {
                "earth_id": u.earth_id,
                "name": u.full_name or u.username or u.earth_id,
                "joined_at": u.created_at.isoformat() if getattr(u, "created_at", None) else None,
            }
            for u in direct
        ],
    }


# ─── GET /referral/commissions ───────────────────────────────────────────────
@router.get("/commissions")
async def referral_commissions(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    res = await db.execute(
        select(MlmCommission)
        .where(MlmCommission.earner_id == current_user.id)
        .order_by(MlmCommission.created_at.desc())
        .limit(100)
    )
    rows = res.scalars().all()
    items = [
        {
            "id": str(r.id), "level": r.level, "amount": r.amount, "currency": r.currency,
            "rate_bps": r.rate_bps, "source_type": r.source_type,
            "created_at": r.created_at.isoformat() if r.created_at else None,
        }
        for r in rows
    ]
    totals = await _earned_by_currency(db, current_user.id)
    return {"commissions": items, "totals": totals}


# ─── GET /referral/qr ────────────────────────────────────────────────────────
@router.get("/qr")
async def referral_qr(current_user: User = Depends(get_current_user)):
    """QRِ دعوت — لینکِ `/join?ref=…` را کد می‌کند، نه لینکِ پروفایل را.

    QRِ پروفایل (`/social/qr/{earth_id}`) بیننده را به صفحهٔ کاربر می‌بَرد و
    زنجیرهٔ معرف را از دست می‌دهد؛ این یکی همان اسکن را به یک عضویتِ منتسب
    تبدیل می‌کند. کدِ معرف راز نیست، پس QR هم رازی حمل نمی‌کند.
    """
    import segno
    url = f"{SITE_URL}/join?ref={current_user.earth_id}"
    buf = _io.BytesIO()
    segno.make(url, error="m").save(
        buf, kind="svg", scale=7, border=3, dark="#0A0A0A", light="#FFFFFF"
    )
    return Response(
        content=buf.getvalue(),
        media_type="image/svg+xml",
        headers={"Cache-Control": "private, max-age=3600"},
    )

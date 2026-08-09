"""
Dilix — Referral / MLM Router (بازاریابیِ شبکه‌ایِ چندسطحی)
GET  /api/v1/referral/stats        → آمار: کد/لینک، مستقیم، کلِ شبکه، درآمدِ کسب‌شده
POST /api/v1/referral/apply        → ثبتِ معرف (earth_id) با محافظت در برابرِ حلقه
GET  /api/v1/referral/network      → شمارِ زیرمجموعه به تفکیکِ سطح + فهرستِ مستقیم‌ها
GET  /api/v1/referral/commissions  → لِجِرِ کمیسیون‌های من + جمعِ درآمد به تفکیکِ ارز
GET  /api/v1/referral/qr           → QRِ دعوت (SVG یا ?format=png) که به /join?ref=… می‌رسد
POST /api/v1/referral/track       → ثبتِ بازدیدِ لینکِ دعوت (عمومی، بدونِ احراز)
GET  /api/v1/referral/funnel      → قیفِ بازدید→عضویت و نرخِ تبدیل

زنجیرهٔ معرف روی `User.referred_by` است؛ کمیسیونِ چندسطحی توسطِ
`app/services/mlm.py::distribute_commission` هنگامِ فعالیتِ زیرمجموعه (مثلِ شارژِ کیف)
توزیع می‌شود. نرخ‌های سطح: L1 ۸٪ · L2 ۳٪ · L3 ۱٪.
"""
import hashlib
import hmac
import io as _io
import uuid as _uuid
from datetime import datetime, timedelta, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from pydantic import BaseModel, Field
from sqlalchemy import (
    Column, Date, DateTime, ForeignKey, Index, String, func, select,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.exc import IntegrityError

from app.core.config import settings
from app.core.database import Base, get_db
from app.core.netutil import get_client_ip
from app.api.deps import get_current_user
from app.models.user import User
from app.models.mlm import MlmCommission
from app.services.mlm import LEVEL_RATES_BPS, MAX_LEVEL, SHOP_LEVEL_RATES_BPS

from sqlalchemy.ext.asyncio import AsyncSession

router = APIRouter(prefix="/referral", tags=["Referral"])

SITE_URL = "https://dilix.ir"

# ─── قیفِ بازدید→عضویت ────────────────────────────────────────────────────────
# بدونِ این، «همکاری در فروش» قابلِ اندازه‌گیری نیست: معرف فقط تعدادِ عضوِ نهایی
# را می‌بیند و نمی‌داند از هر صد بازدید چند نفر ثبت‌نام کرده‌اند، پس نمی‌تواند
# بفهمد کدام کانال کار می‌کند.
FUNNEL_WINDOW_DAYS = 30


class ReferralClick(Base):
    """یک رویدادِ قیف: بازدیدِ لینکِ دعوت یا عضویتِ حاصل از آن.

    `visitor_key` هویتِ بازدیدکننده نیست، فقط یک **کلیدِ یکتاسازی** است:
    HMACِ (IP + User-Agent) با کلیدِ سرور. IP خام ذخیره نمی‌شود (داده‌ی شخصی
    است و برای شمارش لازم نیست) و بدونِ کلیدِ سرور از بیرون بازسازی نمی‌شود.

    یکتاییِ `(ref_user_id, visitor_key, kind, day)` همان الگویی است که در
    `ad_events` تورمِ نمایش را می‌گیرد: رفرشِ حلقه‌ای روی صفحهٔ دعوت آمار را
    باد نمی‌کند، ولی بازدیدِ فردای همان شخص دوباره شمرده می‌شود.
    """
    __tablename__ = "referral_clicks"

    id           = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    ref_user_id  = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"),
                          nullable=False, index=True)
    visitor_key  = Column(String(32), nullable=False)
    kind         = Column(String(10), nullable=False, default="click")   # click | signup
    day          = Column(Date, nullable=False)
    created_at   = Column(DateTime(timezone=True), server_default=func.now())

    __table_args__ = (
        Index("uq_ref_click", "ref_user_id", "visitor_key", "kind", "day", unique=True),
        Index("ix_ref_click_day", "ref_user_id", "day"),
    )


def _visitor_key(request: Request) -> str:
    """کلیدِ یکتاسازیِ بازدیدکننده — نه قابلِ ردیابی، نه قابلِ جعل از بیرون."""
    ip = get_client_ip(request) or "0.0.0.0"
    ua = (request.headers.get("user-agent") or "")[:200]
    mac = hmac.new(settings.JWT_SECRET.encode(), f"{ip}|{ua}".encode(), hashlib.sha256)
    return mac.hexdigest()[:32]


async def _record_funnel(db: AsyncSession, ref_user_id, visitor_key: str, kind: str) -> bool:
    """ثبتِ رویدادِ قیف. برخوردِ کلیدِ یکتا یعنی «قبلاً امروز شمرده شده».

    برخورد داخلِ SAVEPOINT گرفته می‌شود تا تراکنشِ بیرونی (مثلاً ثبتِ معرف در
    `apply`) به‌خاطرِ یک شمارشِ تکراری زمین نخورد.
    """
    try:
        async with db.begin_nested():
            db.add(ReferralClick(
                ref_user_id=ref_user_id, visitor_key=visitor_key, kind=kind,
                day=datetime.now(timezone.utc).date(),
            ))
        return True
    except IntegrityError:
        return False


class ApplyRefRequest(BaseModel):
    ref_code: str = Field(..., description="earth_id رفرر")


class TrackRequest(BaseModel):
    ref: str = Field(..., max_length=32, description="earth_id روی لینکِ دعوت")


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
        # نرخِ فروشگاه جداست و بسیار کمتر؛ اگر UI فقط نرخِ شارژ را نشان دهد،
        # کاربر از کمیسیونِ فروش انتظارِ ۸٪ دارد و رقمِ واقعی را تخلف می‌بیند.
        "shop_rates_bps": SHOP_LEVEL_RATES_BPS,
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

    # سمتِ «تبدیل»ِ قیف. کلید اینجا شناسهٔ خودِ کاربرِ تازه است، نه HMACِ IP:
    # ثبتِ معرف در عمرِ هر حساب فقط یک‌بار ممکن است (گاردِ بالای همین تابع)،
    # پس این ردیف ذاتاً یکتاست و به IP یا مرورگرِ لحظهٔ کلیک وابسته نیست —
    # کسی که روی موبایل کلیک کند و روی دسکتاپ ثبت‌نام کند هم شمرده می‌شود.
    await _record_funnel(db, referrer.id, str(current_user.id).replace("-", "")[:32], "signup")

    await db.commit()
    return {"ok": True, "referred_by": referrer.full_name or referrer.earth_id}


# ─── POST /referral/track ────────────────────────────────────────────────────
@router.post("/track", status_code=204)
async def referral_track(
    body: TrackRequest,
    request: Request,
    db: AsyncSession = Depends(get_db),
):
    """ثبتِ بازدیدِ لینکِ دعوت — عمومی و بی‌احراز، چون بازدیدکننده هنوز عضو نیست.

    همیشه ۲۰۴ برمی‌گرداند، حتی وقتی کد وجود ندارد. اگر برای کدِ ناموجود ۴۰۴
    می‌داد، این مسیرِ بی‌احراز به یک اوراکل تبدیل می‌شد که با آن می‌شد فهرستِ
    earth_idهای واقعی را استخراج کرد.
    """
    code = (body.ref or "").strip().upper()
    if code:
        q = await db.execute(select(User.id).where(User.earth_id == code))
        ref_id = q.scalar_one_or_none()
        if ref_id is not None:
            await _record_funnel(db, ref_id, _visitor_key(request), "click")
            await db.commit()
    return Response(status_code=204)


# ─── GET /referral/funnel ────────────────────────────────────────────────────
@router.get("/funnel")
async def referral_funnel(
    days: int = FUNNEL_WINDOW_DAYS,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """قیفِ «بازدید → عضویت»ِ لینکِ دعوتِ من، روزبه‌روز."""
    days = max(1, min(days, 365))
    since = (datetime.now(timezone.utc) - timedelta(days=days - 1)).date()

    res = await db.execute(
        select(ReferralClick.day, ReferralClick.kind, func.count())
        .where(ReferralClick.ref_user_id == current_user.id, ReferralClick.day >= since)
        .group_by(ReferralClick.day, ReferralClick.kind)
        .order_by(ReferralClick.day)
    )
    by_day: dict = {}
    clicks = signups = 0
    for day, kind, n in res.all():
        n = int(n or 0)
        slot = by_day.setdefault(day.isoformat(), {"day": day.isoformat(), "clicks": 0, "signups": 0})
        if kind == "signup":
            slot["signups"] = n
            signups += n
        else:
            slot["clicks"] = n
            clicks += n

    return {
        "window_days": days,
        "clicks": clicks,
        "signups": signups,
        # نرخِ تبدیل به درصد، گِرد‌شده به دو رقم. مخرجِ صفر یعنی «هنوز داده‌ای نیست»
        # نه «نرخِ صفر»، پس None برمی‌گردد تا UI بین این دو فرق بگذارد.
        "conversion_pct": round(signups * 100 / clicks, 2) if clicks else None,
        "daily": list(by_day.values()),
    }


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
async def referral_qr(
    format: str = "svg",
    current_user: User = Depends(get_current_user),
):
    """QRِ دعوت — لینکِ `/join?ref=…` را کد می‌کند، نه لینکِ پروفایل را.

    QRِ پروفایل (`/social/qr/{earth_id}`) بیننده را به صفحهٔ کاربر می‌بَرد و
    زنجیرهٔ معرف را از دست می‌دهد؛ این یکی همان اسکن را به یک عضویتِ منتسب
    تبدیل می‌کند. کدِ معرف راز نیست، پس QR هم رازی حمل نمی‌کند.

    `format=png` برای موبایل است: Flutter بدونِ پکیجِ اضافه SVG را رندر نمی‌کند،
    ولی `Image.memory` هر PNGی را نشان می‌دهد. نوشتنِ PNG در خودِ segno است و
    وابستگیِ تازه‌ای (Pillow) نمی‌خواهد، پس هر دو نسخه از یک منبع می‌آیند و
    نمی‌توانند از هم واگرا شوند.
    """
    import segno
    url = f"{SITE_URL}/join?ref={current_user.earth_id}"
    png = format.lower() == "png"
    buf = _io.BytesIO()
    segno.make(url, error="m").save(
        buf,
        kind="png" if png else "svg",
        scale=10 if png else 7,
        border=3,
        dark="#0A0A0A",
        light="#FFFFFF",
    )
    return Response(
        content=buf.getvalue(),
        media_type="image/png" if png else "image/svg+xml",
        headers={"Cache-Control": "private, max-age=3600"},
    )

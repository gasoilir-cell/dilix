"""
Dilix — تبلیغاتِ خودخدمت (Ads) — فاز ۴ (اکوسیستم)

    GET    /api/v1/ads/campaigns              کمپین‌های من
    POST   /api/v1/ads/campaigns              ساختِ کمپین (پیش‌نویس)
    GET    /api/v1/ads/campaigns/{id}         جزئیات
    PATCH  /api/v1/ads/campaigns/{id}         ویرایش (فقط پیش‌نویس/متوقف)
    POST   /api/v1/ads/campaigns/{id}/activate  تأمینِ بودجه از کیف + فعال‌سازی
    POST   /api/v1/ads/campaigns/{id}/pause     توقف + بازگشتِ بودجهٔ خرج‌نشده
    POST   /api/v1/ads/campaigns/{id}/stop      پایان + بازگشتِ بودجهٔ خرج‌نشده
    POST   /api/v1/ads/campaigns/{id}/reject    ردِ مدیر (توقف + بازگشتِ وجه)
    GET    /api/v1/ads/campaigns/{id}/stats     آمار + سریِ ۱۴روزه
    GET    /api/v1/ads/serve                  دریافتِ تبلیغ برای یک جایگاه
    POST   /api/v1/ads/{id}/click             ثبتِ کلیک + برداشتِ هزینه

چهار تصمیمی که ساختار را تعیین کرد:

۱) **سقفِ بودجه در `WHERE` است، نه در پایتون.** برداشتِ هزینه با
   `UPDATE … WHERE spent + cost <= budget_total` انجام می‌شود؛ اگر شرط در کد
   بررسی می‌شد، دو کلیکِ هم‌زمان هر دو همان `spent` را می‌خواندند و پلتفرم
   تبلیغی را تحویل می‌داد که پولش را نمی‌تواند بگیرد.

۲) **بودجه پیش از نمایش بلوکه می‌شود.** فعال‌سازی، بودجه را از
   `balance_available` به `balance_escrow` می‌برد. بدونِ آن، تبلیغ‌دهنده
   می‌توانست بلافاصله پس از فعال‌سازی همان پول را جای دیگری خرج کند و
   نمایش‌های انجام‌شده بی‌پشتوانه بمانند.

۳) **هر کاربر در هر روز فقط یک‌بار برای هر کمپین شمرده/هزینه می‌شود.**
   ایندکسِ یکتای `(campaign, user, kind, day)` هم کلیکِ تکراری (که می‌توانست
   بودجهٔ رقیب را عمداً بسوزاند) را بی‌اثر می‌کند و هم «نمایش» را به
   *دسترسیِ یکتای روزانه* تبدیل می‌کند — عددی که با اسکرول باد نمی‌کند و
   نرخِ کلیک را بی‌معنا نمی‌سازد.

۴) **رتبه‌بندی با ارزشِ انتظاری، نه با پیشنهادِ خام.** امتیاز
   `bid × CTRِ هموارشده` است؛ با رتبه‌بندیِ صرفِ قیمت، پولدارترین تبلیغ‌دهنده
   کلِ موجودی را می‌خرید و کاربر جز تبلیغِ بی‌ربط نمی‌دید.
"""
import uuid as _uuid
from datetime import datetime, timedelta, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy import (
    BigInteger, Column, DateTime, ForeignKey, Index, Integer, String, Text,
    UniqueConstraint, and_, func, or_, select, update,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import Base, get_db
from app.models.user import User
from app.services.wallet_ops import lock_escrow, refund_escrow, spend_escrow

router = APIRouter(prefix="/ads", tags=["Ads"])

PLACEMENTS = ("feed", "explore", "story", "search")

BID_MIN = 1_000               # ۱۰۰ تومان برای هر کلیک
BID_MAX = 5_000_000
BUDGET_MIN = 100_000          # ۱۰٬۰۰۰ تومان
BUDGET_MAX = 10_000_000_000

# هموارسازیِ نرخِ کلیک: کمپینِ تازه با صفر نمایش نباید CTR صفر بگیرد و هرگز
# فرصتِ نمایش پیدا نکند؛ این «قبلِ بیزی» به آن چند نمایشِ آزمایشی می‌دهد.
CTR_PRIOR_CLICKS = 1
CTR_PRIOR_IMPRESSIONS = 20

STATUS_LABEL = {
    "draft": "پیش‌نویس",
    "active": "در حالِ نمایش",
    "paused": "متوقف",
    "completed": "پایان‌یافته",
    "rejected": "ردشده",
}


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _today() -> str:
    return _now().strftime("%Y-%m-%d")


# ── مدل‌ها ────────────────────────────────────────────────────────────────────
class AdCampaign(Base):
    """یک کمپینِ تبلیغاتی (مدلِ هزینه: پرداخت به‌ازای کلیک).

    `escrow_locked` بودجهٔ بلوکه‌شدهٔ *همین لحظه* است. ناوردای کل:
    `spent + escrow_locked <= budget_total` — و تا وقتی کمپین فعال است،
    هر ریالِ خرج‌شده دقیقاً یک ریال از بلوکه کم می‌کند.
    """
    __tablename__ = "ad_campaigns"

    id = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    advertiser_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    title = Column(String(120), nullable=False)
    body = Column(String(300), nullable=True)
    image_url = Column(String(500), nullable=True)
    target_url = Column(String(500), nullable=False)
    cta = Column(String(40), nullable=True)
    placement = Column(String(16), nullable=False, default="feed")

    bid_cpc = Column(BigInteger, nullable=False)
    budget_total = Column(BigInteger, nullable=False)
    spent = Column(BigInteger, nullable=False, default=0)
    escrow_locked = Column(BigInteger, nullable=False, default=0)

    impressions = Column(Integer, nullable=False, default=0)
    clicks = Column(Integer, nullable=False, default=0)

    target_countries = Column(String(200), nullable=True)   # ISO3، با کاما
    target_locales = Column(String(200), nullable=True)

    status = Column(String(16), nullable=False, default="draft")
    review_note = Column(Text, nullable=True)
    starts_at = Column(DateTime(timezone=True), nullable=True)
    ends_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)

    __table_args__ = (
        Index("ix_ad_campaign_advertiser", "advertiser_id", "created_at"),
        Index("ix_ad_campaign_serve", "status", "placement"),
    )


class AdEvent(Base):
    """رویدادِ نمایش/کلیک.

    یکتاییِ `(campaign, user, kind, day)` هستهٔ ضدِتقلب است: کلیکِ دوم در همان
    روز نه شمرده می‌شود نه هزینه دارد.
    """
    __tablename__ = "ad_events"

    id = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    campaign_id = Column(UUID(as_uuid=True), ForeignKey("ad_campaigns.id"), nullable=False)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    kind = Column(String(12), nullable=False)          # impression | click
    cost = Column(BigInteger, nullable=False, default=0)
    day = Column(String(10), nullable=False)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)

    __table_args__ = (
        UniqueConstraint("campaign_id", "user_id", "kind", "day",
                         name="uq_ad_event_daily"),
        Index("ix_ad_event_campaign_day", "campaign_id", "day"),
    )


# ── طرح‌ها ────────────────────────────────────────────────────────────────────
class CampaignIn(BaseModel):
    title: str = Field(..., min_length=2, max_length=120)
    target_url: str = Field(..., min_length=4, max_length=500)
    body: Optional[str] = Field(None, max_length=300)
    image_url: Optional[str] = Field(None, max_length=500)
    cta: Optional[str] = Field(None, max_length=40)
    placement: str = Field("feed", max_length=16)
    bid_cpc: int = Field(..., ge=BID_MIN, le=BID_MAX)
    budget_total: int = Field(..., ge=BUDGET_MIN, le=BUDGET_MAX)
    target_countries: Optional[List[str]] = None
    target_locales: Optional[List[str]] = None
    ends_at: Optional[datetime] = None


class CampaignPatch(BaseModel):
    title: Optional[str] = Field(None, min_length=2, max_length=120)
    target_url: Optional[str] = Field(None, min_length=4, max_length=500)
    body: Optional[str] = Field(None, max_length=300)
    image_url: Optional[str] = Field(None, max_length=500)
    cta: Optional[str] = Field(None, max_length=40)
    placement: Optional[str] = Field(None, max_length=16)
    bid_cpc: Optional[int] = Field(None, ge=BID_MIN, le=BID_MAX)
    budget_total: Optional[int] = Field(None, ge=BUDGET_MIN, le=BUDGET_MAX)
    target_countries: Optional[List[str]] = None
    target_locales: Optional[List[str]] = None
    ends_at: Optional[datetime] = None


class CampaignOut(BaseModel):
    id: str
    title: str
    body: Optional[str] = None
    image_url: Optional[str] = None
    target_url: str
    cta: Optional[str] = None
    placement: str
    bid_cpc: int
    budget_total: int
    spent: int
    escrow_locked: int
    remaining: int
    impressions: int
    clicks: int
    ctr: float
    status: str
    status_label: str
    review_note: Optional[str] = None
    target_countries: List[str] = Field(default_factory=list)
    target_locales: List[str] = Field(default_factory=list)
    ends_at: Optional[datetime] = None
    created_at: datetime
    can_activate: bool = False
    can_pause: bool = False
    can_edit: bool = False


class AdOut(BaseModel):
    """آنچه به کاربرِ بیننده داده می‌شود — بدونِ بودجه و پیشنهادِ قیمت."""
    id: str
    title: str
    body: Optional[str] = None
    image_url: Optional[str] = None
    cta: Optional[str] = None
    placement: str
    advertiser_earth_id: str
    advertiser_name: Optional[str] = None


class ClickOut(BaseModel):
    charged: bool
    cost: int
    target_url: str


class StatPoint(BaseModel):
    day: str
    impressions: int
    clicks: int
    spent: int


class StatsOut(BaseModel):
    impressions: int
    clicks: int
    ctr: float
    spent: int
    remaining: int
    avg_cpc: int
    series: List[StatPoint]


# ── کمکی‌ها ──────────────────────────────────────────────────────────────────
def _split(s: Optional[str]) -> List[str]:
    return [x for x in (s or "").split(",") if x]


def _join(items: Optional[List[str]]) -> Optional[str]:
    if items is None:
        return None
    vals = [str(x).strip().upper() for x in items if str(x).strip()]
    return ",".join(sorted(set(vals))) or None


def _ctr(c: AdCampaign) -> float:
    if not c.impressions:
        return 0.0
    return round(int(c.clicks) * 100.0 / int(c.impressions), 2)


def _campaign_out(c: AdCampaign) -> CampaignOut:
    remaining = max(0, int(c.budget_total) - int(c.spent))
    return CampaignOut(
        id=str(c.id), title=c.title, body=c.body, image_url=c.image_url,
        target_url=c.target_url, cta=c.cta, placement=c.placement,
        bid_cpc=int(c.bid_cpc), budget_total=int(c.budget_total),
        spent=int(c.spent), escrow_locked=int(c.escrow_locked),
        remaining=remaining, impressions=int(c.impressions),
        clicks=int(c.clicks), ctr=_ctr(c),
        status=c.status, status_label=STATUS_LABEL.get(c.status, c.status),
        review_note=c.review_note,
        target_countries=_split(c.target_countries),
        target_locales=_split(c.target_locales),
        ends_at=c.ends_at, created_at=c.created_at,
        can_activate=(c.status in ("draft", "paused") and remaining >= int(c.bid_cpc)),
        can_pause=(c.status == "active"),
        # ویرایشِ کمپینِ در حالِ نمایش ممنوع است: متنِ تبلیغ نباید پس از
        # شروعِ نمایش زیرِ پای آمارِ همان کمپین عوض شود.
        can_edit=(c.status in ("draft", "paused")),
    )


async def _my_campaign(db: AsyncSession, cid: str, me: User,
                       lock: bool = False) -> AdCampaign:
    try:
        uid = _uuid.UUID(cid)
    except ValueError:
        raise HTTPException(status_code=404, detail="کمپین پیدا نشد")
    stmt = select(AdCampaign).where(AdCampaign.id == uid)
    if lock:
        stmt = stmt.with_for_update()
    c = (await db.execute(stmt)).scalar_one_or_none()
    if c is None or c.advertiser_id != me.id:
        raise HTTPException(status_code=404, detail="کمپین پیدا نشد")
    return c


def _matches(c: AdCampaign, u: User) -> bool:
    """هدف‌گیری: فهرستِ خالی یعنی «همه». کاربرِ بی‌کشور از کمپینِ کشورمحور
    کنار می‌رود، وگرنه تبلیغ‌دهنده بابتِ مخاطبی که نخواسته پول می‌داد."""
    countries = _split(c.target_countries)
    if countries and (u.country_code or "").upper() not in countries:
        return False
    locales = _split(c.target_locales)
    if locales and (u.locale or "").upper() not in locales:
        return False
    return True


def _score(c: AdCampaign) -> float:
    ctr = ((int(c.clicks) + CTR_PRIOR_CLICKS)
           / (int(c.impressions) + CTR_PRIOR_IMPRESSIONS))
    return int(c.bid_cpc) * ctr


# ── کمپین‌ها ─────────────────────────────────────────────────────────────────
@router.get("/campaigns", response_model=List[CampaignOut])
async def my_campaigns(
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    rows = (await db.execute(
        select(AdCampaign).where(AdCampaign.advertiser_id == me.id)
        .order_by(AdCampaign.created_at.desc())
    )).scalars().all()
    return [_campaign_out(c) for c in rows]


@router.post("/campaigns", response_model=CampaignOut, status_code=201)
async def create_campaign(
    body: CampaignIn,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """کمپین همیشه **پیش‌نویس** ساخته می‌شود؛ ساخت هیچ پولی برنمی‌دارد."""
    if body.placement not in PLACEMENTS:
        raise HTTPException(status_code=400, detail="جایگاهِ نامعتبر")
    if body.budget_total < body.bid_cpc:
        raise HTTPException(status_code=400, detail="بودجه از هزینهٔ هر کلیک کمتر است")
    c = AdCampaign(
        advertiser_id=me.id, title=body.title.strip(),
        target_url=body.target_url.strip(),
        body=(body.body or "").strip() or None,
        image_url=(body.image_url or "").strip() or None,
        cta=(body.cta or "").strip() or None,
        placement=body.placement, bid_cpc=body.bid_cpc,
        budget_total=body.budget_total,
        target_countries=_join(body.target_countries),
        target_locales=_join(body.target_locales),
        ends_at=body.ends_at, status="draft",
    )
    db.add(c)
    await db.commit()
    await db.refresh(c)
    return _campaign_out(c)


@router.get("/campaigns/{campaign_id}", response_model=CampaignOut)
async def get_campaign(
    campaign_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    return _campaign_out(await _my_campaign(db, campaign_id, me))


@router.patch("/campaigns/{campaign_id}", response_model=CampaignOut)
async def update_campaign(
    campaign_id: str,
    body: CampaignPatch,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    c = await _my_campaign(db, campaign_id, me)
    if c.status not in ("draft", "paused"):
        raise HTTPException(
            status_code=400,
            detail="کمپینِ در حالِ نمایش را نمی‌توان ویرایش کرد؛ ابتدا متوقفش کنید",
        )
    data = body.model_dump(exclude_unset=True)
    if data.get("placement") and data["placement"] not in PLACEMENTS:
        raise HTTPException(status_code=400, detail="جایگاهِ نامعتبر")
    if "target_countries" in data:
        c.target_countries = _join(data.pop("target_countries"))
    if "target_locales" in data:
        c.target_locales = _join(data.pop("target_locales"))
    for k in ("title", "target_url", "body", "image_url", "cta"):
        if k in data and data[k] is not None:
            data[k] = str(data[k]).strip() or None
    for k, v in data.items():
        if v is not None:
            setattr(c, k, v)
    if int(c.budget_total) < int(c.bid_cpc):
        raise HTTPException(status_code=400, detail="بودجه از هزینهٔ هر کلیک کمتر است")
    await db.commit()
    await db.refresh(c)
    return _campaign_out(c)


@router.post("/campaigns/{campaign_id}/activate", response_model=CampaignOut)
async def activate_campaign(
    campaign_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """بودجهٔ باقی‌مانده را از کیف بلوکه می‌کند و کمپین را روی هوا می‌برد."""
    c = await _my_campaign(db, campaign_id, me, lock=True)
    if c.status == "active":
        raise HTTPException(status_code=400, detail="کمپین از قبل فعال است")
    if c.status in ("completed", "rejected"):
        raise HTTPException(status_code=400, detail="این کمپین دیگر قابلِ فعال‌سازی نیست")

    need = int(c.budget_total) - int(c.spent) - int(c.escrow_locked)
    if int(c.budget_total) - int(c.spent) < int(c.bid_cpc):
        raise HTTPException(status_code=400, detail="بودجهٔ باقی‌مانده از هزینهٔ یک کلیک کمتر است")
    if need > 0:
        await lock_escrow(
            db, me.id, need,
            description=f"بلوکِ بودجهٔ کمپینِ «{c.title}»",
            reference_id=str(c.id),
        )
        c.escrow_locked = int(c.escrow_locked) + need

    c.status = "active"
    c.review_note = None
    if c.starts_at is None:
        c.starts_at = _now()
    await db.commit()
    await db.refresh(c)
    return _campaign_out(c)


async def _release_budget(db: AsyncSession, c: AdCampaign, reason: str) -> None:
    """بازگرداندنِ بودجهٔ خرج‌نشده. تا وقتی کمپین نمی‌تواند خرج کند، پولِ
    تبلیغ‌دهنده نباید بلوکه بماند."""
    left = int(c.escrow_locked)
    if left > 0:
        await refund_escrow(
            db, c.advertiser_id, left,
            description=f"{reason} — کمپینِ «{c.title}»",
            reference_id=str(c.id),
        )
        c.escrow_locked = 0


@router.post("/campaigns/{campaign_id}/pause", response_model=CampaignOut)
async def pause_campaign(
    campaign_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    c = await _my_campaign(db, campaign_id, me, lock=True)
    if c.status != "active":
        raise HTTPException(status_code=400, detail="کمپین فعال نیست")
    await _release_budget(db, c, "بازگشتِ بودجهٔ خرج‌نشده")
    c.status = "paused"
    await db.commit()
    await db.refresh(c)
    return _campaign_out(c)


@router.post("/campaigns/{campaign_id}/stop", response_model=CampaignOut)
async def stop_campaign(
    campaign_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    c = await _my_campaign(db, campaign_id, me, lock=True)
    if c.status in ("completed", "rejected"):
        raise HTTPException(status_code=400, detail="کمپین از قبل بسته شده است")
    await _release_budget(db, c, "بازگشتِ بودجهٔ خرج‌نشده")
    c.status = "completed"
    await db.commit()
    await db.refresh(c)
    return _campaign_out(c)


@router.post("/campaigns/{campaign_id}/reject", response_model=CampaignOut)
async def reject_campaign(
    campaign_id: str,
    note: Optional[str] = Query(None, max_length=300),
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """ردِ مدیر: نمایش قطع و بودجهٔ خرج‌نشده برمی‌گردد. بدونِ این، تنها راهِ
    برخورد با تبلیغِ متخلف، دست‌بردن در دیتابیس بود."""
    if me.role not in ("admin", "super_admin"):
        raise HTTPException(status_code=403, detail="دسترسی کافی ندارید")
    try:
        uid = _uuid.UUID(campaign_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="کمپین پیدا نشد")
    c = (await db.execute(
        select(AdCampaign).where(AdCampaign.id == uid).with_for_update()
    )).scalar_one_or_none()
    if c is None:
        raise HTTPException(status_code=404, detail="کمپین پیدا نشد")
    await _release_budget(db, c, "بازگشتِ بودجه پس از رد")
    c.status = "rejected"
    c.review_note = (note or "").strip() or "این تبلیغ با قوانینِ پلتفرم سازگار نبود"
    await db.commit()
    await db.refresh(c)
    return _campaign_out(c)


@router.get("/campaigns/{campaign_id}/stats", response_model=StatsOut)
async def campaign_stats(
    campaign_id: str,
    days: int = Query(14, ge=1, le=90),
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """سریِ روزانه با صفر پر می‌شود تا نبودِ داده در نمودار شبیهِ نبودِ روز
    نباشد و شیبِ رشد دروغ درنیاید."""
    c = await _my_campaign(db, campaign_id, me)
    since = (_now() - timedelta(days=days - 1)).strftime("%Y-%m-%d")
    rows = (await db.execute(
        select(
            AdEvent.day, AdEvent.kind,
            func.count().label("n"), func.coalesce(func.sum(AdEvent.cost), 0).label("cost"),
        ).where(AdEvent.campaign_id == c.id, AdEvent.day >= since)
        .group_by(AdEvent.day, AdEvent.kind)
    )).all()
    buckets: dict[str, dict] = {}
    for day, kind, n, cost in rows:
        b = buckets.setdefault(day, {"impressions": 0, "clicks": 0, "spent": 0})
        if kind == "click":
            b["clicks"] += int(n)
        else:
            b["impressions"] += int(n)
        b["spent"] += int(cost or 0)

    series = []
    for i in range(days - 1, -1, -1):
        d = (_now() - timedelta(days=i)).strftime("%Y-%m-%d")
        b = buckets.get(d, {"impressions": 0, "clicks": 0, "spent": 0})
        series.append(StatPoint(day=d, **b))

    clicks = int(c.clicks)
    return StatsOut(
        impressions=int(c.impressions), clicks=clicks, ctr=_ctr(c),
        spent=int(c.spent),
        remaining=max(0, int(c.budget_total) - int(c.spent)),
        avg_cpc=(int(c.spent) // clicks if clicks else 0),
        series=series,
    )


# ── نمایش و کلیک ─────────────────────────────────────────────────────────────
@router.get("/serve", response_model=List[AdOut])
async def serve_ads(
    placement: str = Query("feed", max_length=16),
    limit: int = Query(1, ge=1, le=5),
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """انتخابِ تبلیغ برای یک جایگاه + ثبتِ نمایش.

    نمایشِ تکراریِ همان کمپین به همان کاربر در همان روز **شمرده نمی‌شود**
    (ایندکسِ یکتا)، پس عدد «نمایش» یعنی دسترسیِ یکتای روزانه. اگر خامِ
    نمایش‌ها شمرده می‌شد، هر بار اسکرول عدد را باد می‌کرد و CTR بی‌معنا
    می‌شد.
    """
    if placement not in PLACEMENTS:
        raise HTTPException(status_code=400, detail="جایگاهِ نامعتبر")
    now = _now()
    rows = (await db.execute(
        select(AdCampaign).where(
            AdCampaign.status == "active",
            AdCampaign.placement == placement,
            AdCampaign.advertiser_id != me.id,     # تبلیغِ خودت را نمی‌بینی
            AdCampaign.spent + AdCampaign.bid_cpc <= AdCampaign.budget_total,
            or_(AdCampaign.starts_at.is_(None), AdCampaign.starts_at <= now),
            or_(AdCampaign.ends_at.is_(None), AdCampaign.ends_at > now),
        ).limit(60)
    )).scalars().all()

    picked = sorted([c for c in rows if _matches(c, me)],
                    key=_score, reverse=True)[:limit]
    if not picked:
        return []

    day = _today()
    for c in picked:
        # هر ثبت در SAVEPOINT خودش: برخوردِ یکتایی (نمایشِ تکراری یا مسابقهٔ
        # دو درخواستِ هم‌زمان) نباید کلِ تراکنش را زمین بزند.
        try:
            async with db.begin_nested():
                db.add(AdEvent(campaign_id=c.id, user_id=me.id,
                               kind="impression", cost=0, day=day))
        except IntegrityError:
            continue
        await db.execute(
            update(AdCampaign).where(AdCampaign.id == c.id)
            .values(impressions=AdCampaign.impressions + 1)
        )
    await db.commit()

    advertisers = {u.id: u for u in (await db.execute(
        select(User).where(User.id.in_([c.advertiser_id for c in picked]))
    )).scalars().all()}
    out = []
    for c in picked:
        u = advertisers.get(c.advertiser_id)
        out.append(AdOut(
            id=str(c.id), title=c.title, body=c.body, image_url=c.image_url,
            cta=c.cta, placement=c.placement,
            advertiser_earth_id=(u.earth_id if u else ""),
            advertiser_name=((u.full_name or u.username or u.earth_id) if u else None),
        ))
    return out


@router.post("/{campaign_id}/click", response_model=ClickOut)
async def click_ad(
    campaign_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """ثبتِ کلیک + برداشتِ هزینه.

    سه محافظ پشتِ سرِ هم: (۱) کلیکِ دومِ همان کاربر در همان روز رایگان است،
    (۲) برداشت فقط با `UPDATE … WHERE spent + bid <= budget_total` انجام
    می‌شود پس عبور از بودجه ساختاراً ناممکن است، (۳) هزینه از همان بودجهٔ
    از‌پیش‌بلوکه‌شده کم می‌شود، نه از موجودیِ در دسترس.
    """
    try:
        uid = _uuid.UUID(campaign_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="تبلیغ پیدا نشد")
    c = (await db.execute(
        select(AdCampaign).where(AdCampaign.id == uid)
    )).scalar_one_or_none()
    if c is None:
        raise HTTPException(status_code=404, detail="تبلیغ پیدا نشد")
    if c.advertiser_id == me.id:
        # کلیکِ خودِ تبلیغ‌دهنده هرگز هزینه ندارد.
        return ClickOut(charged=False, cost=0, target_url=c.target_url)

    day = _today()
    ev = AdEvent(campaign_id=c.id, user_id=me.id, kind="click", cost=0, day=day)
    try:
        async with db.begin_nested():
            db.add(ev)
    except IntegrityError:
        await db.commit()
        return ClickOut(charged=False, cost=0, target_url=c.target_url)

    bid = int(c.bid_cpc)
    res = await db.execute(
        update(AdCampaign)
        .where(
            AdCampaign.id == c.id,
            AdCampaign.status == "active",
            AdCampaign.spent + bid <= AdCampaign.budget_total,
            AdCampaign.escrow_locked >= bid,
        )
        .values(spent=AdCampaign.spent + bid, clicks=AdCampaign.clicks + 1,
                escrow_locked=AdCampaign.escrow_locked - bid)
    )
    charged = res.rowcount == 1
    if charged:
        await spend_escrow(
            db, c.advertiser_id, bid,
            description=f"هزینهٔ کلیکِ تبلیغِ «{c.title}»",
            reference_id=str(c.id),
        )
        ev.cost = bid

    await db.commit()

    if charged:
        # اگر بودجه دیگر کفافِ یک کلیکِ دیگر را نمی‌دهد، کمپین همین‌جا بسته
        # می‌شود تا در انتخابِ بعدی جای موجودی را اشغال نکند.
        await db.refresh(c)
        if int(c.budget_total) - int(c.spent) < bid:
            await _release_budget(db, c, "بازگشتِ باقی‌ماندهٔ بودجه")
            c.status = "completed"
            await db.commit()

    return ClickOut(charged=charged, cost=(bid if charged else 0),
                    target_url=c.target_url)


async def close_finished_campaigns(db: AsyncSession) -> int:
    """کمپین‌های سررسیدشده را می‌بندد و بودجهٔ خرج‌نشده را برمی‌گرداند.

    بدونِ این، پولِ تبلیغ‌دهنده پس از پایانِ بازهٔ زمانی هم بلوکه می‌ماند —
    کمپینی که دیگر هرگز خرج نمی‌کند.
    """
    now = _now()
    rows = (await db.execute(
        select(AdCampaign).where(
            AdCampaign.status == "active",
            or_(
                and_(AdCampaign.ends_at.is_not(None), AdCampaign.ends_at <= now),
                AdCampaign.spent + AdCampaign.bid_cpc > AdCampaign.budget_total,
            ),
        ).limit(200)
    )).scalars().all()
    done = 0
    for c in rows:
        try:
            await _release_budget(db, c, "بازگشتِ باقی‌ماندهٔ بودجه")
            c.status = "completed"
            await db.commit()
            done += 1
        except Exception:
            await db.rollback()
    return done

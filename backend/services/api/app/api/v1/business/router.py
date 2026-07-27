"""
Dilix — حساب‌های کسب‌وکار/سازنده + آمار (Insights)  — فاز ۴

    GET    /api/v1/business/categories        کاتالوگِ دسته‌بندی‌ها
    GET    /api/v1/business/me                حسابِ کسب‌وکارِ من
    POST   /api/v1/business/me                ارتقای حسابِ شخصی به کسب‌وکار/سازنده
    PATCH  /api/v1/business/me                ویرایش
    DELETE /api/v1/business/me                بازگشت به حسابِ شخصی
    GET    /api/v1/business/insights          آمارِ واقعیِ حسابِ من
    GET    /api/v1/business/{earth_id}        نمایهٔ عمومیِ کسب‌وکار
    POST   /api/v1/business/{earth_id}/view   ثبتِ یک بازدیدِ نمایه

چرا آمار «واقعی» است؟
    هیچ عددی ساختگی نیست: دنبال‌کننده از `follows`، تعاملِ محتوا از
    `posts.like_count/comment_count/save_count`، درآمد از `subscription_charges`
    و بازدید از جدولِ `profile_views` خوانده می‌شود. بازدید **در هر روز برای
    هر بیننده یک‌بار** شمرده می‌شود، وگرنه رفرشِ پیاپیِ یک صفحه آمار را باد
    می‌کرد و عددِ بی‌معنا می‌ساخت.
"""
import uuid as _uuid
from datetime import date, datetime, timedelta, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import (
    Boolean, Column, Date, DateTime, Float, ForeignKey, Index, String, Text,
    func, select,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import Base, get_db
from app.models.posts import Post
from app.models.social import Follow
from app.models.user import User

router = APIRouter(prefix="/business", tags=["Business"])


def _now() -> datetime:
    return datetime.now(timezone.utc)


# ── مدل‌ها ────────────────────────────────────────────────────────────────────
class BusinessProfile(Base):
    """نمایهٔ کسب‌وکار/سازنده. هر کاربر حداکثر **یک** حساب دارد؛ حسابِ کسب‌وکار
    لایه‌ای روی همان کاربر است، نه کاربرِ دوم — تا Earth ID، دنبال‌کننده‌ها و
    کیفِ پول یکی بمانند."""
    __tablename__ = "business_profiles"

    id           = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    user_id      = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"),
                          unique=True, nullable=False)
    kind         = Column(String(12), nullable=False, default="business")  # business | creator | official
    display_name = Column(String(120), nullable=False)
    category     = Column(String(24), nullable=False, default="other")
    about        = Column(Text, nullable=True)
    website      = Column(String(200), nullable=True)
    contact_phone = Column(String(32), nullable=True)
    contact_email = Column(String(200), nullable=True)
    address      = Column(String(240), nullable=True)
    lat          = Column(Float, nullable=True)
    lng          = Column(Float, nullable=True)
    # تأیید سِمَتِ تزئینی نیست: از سطحِ KYCِ همان کاربر می‌آید (پایین را ببین).
    verified     = Column(Boolean, nullable=False, default=False)
    created_at   = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at   = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)


class ProfileView(Base):
    """بازدیدِ نمایه — یک ردیف برای هر (نمایه، بیننده، روز).

    ایندکسِ یکتا عمداً روی `view_day` است تا شمارش «بازدیدکنندهٔ یکتا در روز»
    باشد نه «تعدادِ رفرش».
    """
    __tablename__ = "profile_views"

    id         = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    profile_user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    viewer_id  = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    view_day   = Column(Date, nullable=False)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)

    __table_args__ = (
        Index("uq_profile_view_day", "profile_user_id", "viewer_id", "view_day", unique=True),
        Index("ix_profile_view_owner", "profile_user_id", "view_day"),
    )


# ── کاتالوگ ──────────────────────────────────────────────────────────────────
CATEGORIES = [
    {"key": "shop",       "label": "فروشگاه",        "emoji": "🛍"},
    {"key": "food",       "label": "رستوران و کافه",  "emoji": "🍽"},
    {"key": "health",     "label": "سلامت",          "emoji": "🩺"},
    {"key": "education",  "label": "آموزش",          "emoji": "📚"},
    {"key": "tech",       "label": "فناوری",          "emoji": "💻"},
    {"key": "media",      "label": "رسانه",           "emoji": "🎬"},
    {"key": "art",        "label": "هنر",             "emoji": "🎨"},
    {"key": "sport",      "label": "ورزش",            "emoji": "🏋"},
    {"key": "travel",     "label": "سفر",             "emoji": "✈️"},
    {"key": "finance",    "label": "مالی",            "emoji": "💰"},
    {"key": "realestate", "label": "املاک",           "emoji": "🏠"},
    {"key": "auto",       "label": "خودرو",           "emoji": "🚗"},
    {"key": "beauty",     "label": "زیبایی",          "emoji": "💄"},
    {"key": "service",    "label": "خدمات",           "emoji": "🔧"},
    {"key": "ngo",        "label": "غیرانتفاعی",      "emoji": "🤝"},
    {"key": "other",      "label": "سایر",            "emoji": "📦"},
]
_CATEGORY_KEYS = {c["key"] for c in CATEGORIES}
_CATEGORY_BY_KEY = {c["key"]: c for c in CATEGORIES}

KINDS = {
    "business": {"label": "کسب‌وکار", "emoji": "🏢", "min_kyc": 0},
    "creator":  {"label": "سازنده",   "emoji": "🎨", "min_kyc": 0},
    # حسابِ «رسمی» ادعای هویتِ یک نهاد است، پس بالاترین سطحِ احراز را می‌خواهد.
    "official": {"label": "رسمی",     "emoji": "✅", "min_kyc": 3},
}

# نشانِ تأیید از سطحِ KYC می‌آید، نه از یک سوییچِ دستی.
VERIFIED_MIN_KYC = 2


# ── Schemas ──────────────────────────────────────────────────────────────────
class CategoryOut(BaseModel):
    key: str
    label: str
    emoji: str


class KindOut(BaseModel):
    key: str
    label: str
    emoji: str
    min_kyc: int


class BusinessIn(BaseModel):
    kind: str = "business"
    display_name: str = Field(..., min_length=2, max_length=120)
    category: str = "other"
    about: Optional[str] = Field(None, max_length=2000)
    website: Optional[str] = Field(None, max_length=200)
    contact_phone: Optional[str] = Field(None, max_length=32)
    contact_email: Optional[str] = Field(None, max_length=200)
    address: Optional[str] = Field(None, max_length=240)
    lat: Optional[float] = None
    lng: Optional[float] = None


class BusinessPatch(BaseModel):
    kind: Optional[str] = None
    display_name: Optional[str] = Field(None, min_length=2, max_length=120)
    category: Optional[str] = None
    about: Optional[str] = Field(None, max_length=2000)
    website: Optional[str] = Field(None, max_length=200)
    contact_phone: Optional[str] = Field(None, max_length=32)
    contact_email: Optional[str] = Field(None, max_length=200)
    address: Optional[str] = Field(None, max_length=240)
    lat: Optional[float] = None
    lng: Optional[float] = None


class BusinessOut(BaseModel):
    id: str
    earth_id: str
    username: Optional[str] = None
    avatar_url: Optional[str] = None
    kind: str
    kind_label: str
    kind_emoji: str
    display_name: str
    category: str
    category_label: str
    category_emoji: str
    about: Optional[str] = None
    website: Optional[str] = None
    contact_phone: Optional[str] = None
    contact_email: Optional[str] = None
    address: Optional[str] = None
    lat: Optional[float] = None
    lng: Optional[float] = None
    verified: bool
    follower_count: int = 0
    created_at: datetime


class DayPoint(BaseModel):
    day: date
    value: int


class TopPost(BaseModel):
    id: str
    media_url: str
    caption: Optional[str] = None
    like_count: int
    comment_count: int
    save_count: int
    engagement: int
    created_at: datetime


class InsightsOut(BaseModel):
    """همهٔ اعداد از جدول‌های واقعی می‌آیند؛ هیچ مقداری تخمینی نیست."""
    followers_total: int
    followers_7d: int
    followers_30d: int
    views_7d: int
    views_30d: int
    posts_total: int
    likes_total: int
    comments_total: int
    saves_total: int
    engagement_rate: float          # درصدِ تعامل به ازای هر دنبال‌کننده
    subscribers_active: int
    revenue_30d: int                # ریال
    views_series: List[DayPoint]    # ۳۰ روزِ گذشته
    followers_series: List[DayPoint]
    top_posts: List[TopPost]


# ── کمکی‌ها ──────────────────────────────────────────────────────────────────
def _out(p: BusinessProfile, u: User, follower_count: int = 0) -> BusinessOut:
    kind = KINDS.get(p.kind, KINDS["business"])
    cat = _CATEGORY_BY_KEY.get(p.category, _CATEGORY_BY_KEY["other"])
    return BusinessOut(
        id=str(p.id), earth_id=u.earth_id, username=u.username, avatar_url=u.avatar_url,
        kind=p.kind, kind_label=kind["label"], kind_emoji=kind["emoji"],
        display_name=p.display_name,
        category=p.category, category_label=cat["label"], category_emoji=cat["emoji"],
        about=p.about, website=p.website, contact_phone=p.contact_phone,
        contact_email=p.contact_email, address=p.address, lat=p.lat, lng=p.lng,
        verified=p.verified, follower_count=follower_count, created_at=p.created_at,
    )


def _check_kind(kind: str, me: User) -> str:
    spec = KINDS.get(kind)
    if spec is None:
        raise HTTPException(400, detail="نوعِ حساب نامعتبر است")
    if (me.kyc_level or 0) < spec["min_kyc"]:
        raise HTTPException(
            403,
            detail=f"برای حسابِ «{spec['label']}» احرازِ هویتِ سطحِ {spec['min_kyc']} لازم است",
        )
    return kind


def _check_category(cat: str) -> str:
    if cat not in _CATEGORY_KEYS:
        raise HTTPException(400, detail="دسته‌بندی نامعتبر است")
    return cat


async def _followers(db: AsyncSession, user_id) -> int:
    return int((await db.execute(
        select(func.count()).select_from(Follow).where(Follow.following_id == user_id)
    )).scalar() or 0)


async def _profile_of(db: AsyncSession, user_id) -> Optional[BusinessProfile]:
    return (await db.execute(
        select(BusinessProfile).where(BusinessProfile.user_id == user_id)
    )).scalar_one_or_none()


# ── Endpoints ────────────────────────────────────────────────────────────────
@router.get("/categories", response_model=List[CategoryOut])
async def categories():
    """کاتالوگِ دسته‌بندی‌ها (عمومی — برای پرکردنِ فرمِ ثبت‌نام)."""
    return [CategoryOut(**c) for c in CATEGORIES]


@router.get("/kinds", response_model=List[KindOut])
async def kinds():
    """انواعِ حساب و حداقلِ سطحِ احرازِ هویتِ لازم برای هرکدام."""
    return [KindOut(key=k, **v) for k, v in KINDS.items()]


@router.get("/me", response_model=BusinessOut)
async def my_business(
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    p = await _profile_of(db, me.id)
    if p is None:
        raise HTTPException(404, detail="حسابِ کسب‌وکار ندارید")
    return _out(p, me, await _followers(db, me.id))


@router.post("/me", response_model=BusinessOut, status_code=201)
async def create_business(
    payload: BusinessIn,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """ارتقای حسابِ شخصی به کسب‌وکار/سازنده."""
    if await _profile_of(db, me.id) is not None:
        raise HTTPException(409, detail="حسابِ کسب‌وکار از قبل دارید")

    kind = _check_kind(payload.kind, me)
    p = BusinessProfile(
        user_id=me.id, kind=kind,
        display_name=payload.display_name.strip(),
        category=_check_category(payload.category),
        about=payload.about, website=payload.website,
        contact_phone=payload.contact_phone, contact_email=payload.contact_email,
        address=payload.address, lat=payload.lat, lng=payload.lng,
        verified=(me.kyc_level or 0) >= VERIFIED_MIN_KYC,
    )
    db.add(p)
    # نقشِ کاربر هم عوض می‌شود تا بقیهٔ پلتفرم (مثلاً مجوزها) از آن باخبر باشد.
    if kind == "creator" and me.role == "user":
        me.role = "creator"
    await db.commit()
    await db.refresh(p)
    return _out(p, me, await _followers(db, me.id))


@router.patch("/me", response_model=BusinessOut)
async def update_business(
    payload: BusinessPatch,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    p = await _profile_of(db, me.id)
    if p is None:
        raise HTTPException(404, detail="حسابِ کسب‌وکار ندارید")

    data = payload.model_dump(exclude_unset=True)
    if "kind" in data and data["kind"] is not None:
        p.kind = _check_kind(data.pop("kind"), me)
    else:
        data.pop("kind", None)
    if "category" in data and data["category"] is not None:
        p.category = _check_category(data.pop("category"))
    else:
        data.pop("category", None)
    for field, value in data.items():
        setattr(p, field, value)

    # سطحِ KYC ممکن است از زمانِ ساخت بالا رفته باشد.
    p.verified = (me.kyc_level or 0) >= VERIFIED_MIN_KYC
    await db.commit()
    await db.refresh(p)
    return _out(p, me, await _followers(db, me.id))


@router.delete("/me", status_code=204)
async def delete_business(
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """بازگشت به حسابِ شخصی. محتوا و دنبال‌کننده‌ها دست‌نخورده می‌مانند چون
    حسابِ کسب‌وکار فقط لایه‌ای روی همان کاربر بود."""
    p = await _profile_of(db, me.id)
    if p is None:
        raise HTTPException(404, detail="حسابِ کسب‌وکار ندارید")
    await db.delete(p)
    if me.role == "creator":
        me.role = "user"
    await db.commit()


@router.get("/insights", response_model=InsightsOut)
async def insights(
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """آمارِ حسابِ من — همهٔ اعداد از داده‌های واقعی محاسبه می‌شوند."""
    p = await _profile_of(db, me.id)
    if p is None:
        raise HTTPException(404, detail="حسابِ کسب‌وکار ندارید")

    now = _now()
    d7, d30 = now - timedelta(days=7), now - timedelta(days=30)
    today = now.date()
    from_day = today - timedelta(days=29)

    followers_total = await _followers(db, me.id)
    followers_7d = int((await db.execute(
        select(func.count()).select_from(Follow)
        .where(Follow.following_id == me.id, Follow.created_at >= d7)
    )).scalar() or 0)
    followers_30d = int((await db.execute(
        select(func.count()).select_from(Follow)
        .where(Follow.following_id == me.id, Follow.created_at >= d30)
    )).scalar() or 0)

    views_7d = int((await db.execute(
        select(func.count()).select_from(ProfileView)
        .where(ProfileView.profile_user_id == me.id, ProfileView.created_at >= d7)
    )).scalar() or 0)
    views_30d = int((await db.execute(
        select(func.count()).select_from(ProfileView)
        .where(ProfileView.profile_user_id == me.id, ProfileView.created_at >= d30)
    )).scalar() or 0)

    agg = (await db.execute(
        select(
            func.count(Post.id),
            func.coalesce(func.sum(Post.like_count), 0),
            func.coalesce(func.sum(Post.comment_count), 0),
            func.coalesce(func.sum(Post.save_count), 0),
        ).where(Post.author_id == me.id)
    )).one()
    posts_total, likes_total, comments_total, saves_total = (int(x or 0) for x in agg)

    interactions = likes_total + comments_total + saves_total
    # نرخِ تعامل بدونِ دنبال‌کننده تعریف نشده است؛ صفر برمی‌گردد نه بی‌نهایت.
    engagement_rate = round(interactions * 100 / followers_total, 2) if followers_total else 0.0

    # سریِ روزانه: فقط روزهای دارای داده از DB می‌آید و بقیه با صفر پر می‌شود،
    # وگرنه نمودار در روزهای خالی می‌پرد.
    view_rows = (await db.execute(
        select(ProfileView.view_day, func.count())
        .where(ProfileView.profile_user_id == me.id, ProfileView.view_day >= from_day)
        .group_by(ProfileView.view_day)
    )).all()
    follow_rows = (await db.execute(
        select(func.date(Follow.created_at), func.count())
        .where(Follow.following_id == me.id, Follow.created_at >= d30)
        .group_by(func.date(Follow.created_at))
    )).all()

    def _series(rows) -> List[DayPoint]:
        counts = {r[0]: int(r[1]) for r in rows}
        return [
            DayPoint(day=from_day + timedelta(days=i),
                     value=counts.get(from_day + timedelta(days=i), 0))
            for i in range(30)
        ]

    top_rows = (await db.execute(
        select(Post).where(Post.author_id == me.id)
        .order_by((Post.like_count + Post.comment_count + Post.save_count).desc(),
                  Post.created_at.desc())
        .limit(5)
    )).scalars().all()

    # درآمدِ اشتراک از همان روتر اشتراک‌ها می‌آید؛ importِ محلی تا وابستگیِ
    # حلقوی بینِ دو ماژول ایجاد نشود.
    from app.api.v1.business.subscriptions import Subscription, SubscriptionCharge

    subscribers_active = int((await db.execute(
        select(func.count()).select_from(Subscription)
        .where(Subscription.owner_id == me.id,
               Subscription.status == "active",
               Subscription.current_period_end > now)
    )).scalar() or 0)
    revenue_30d = int((await db.execute(
        select(func.coalesce(func.sum(SubscriptionCharge.amount), 0))
        .join(Subscription, Subscription.id == SubscriptionCharge.subscription_id)
        .where(Subscription.owner_id == me.id, SubscriptionCharge.paid_at >= d30)
    )).scalar() or 0)

    return InsightsOut(
        followers_total=followers_total,
        followers_7d=followers_7d,
        followers_30d=followers_30d,
        views_7d=views_7d,
        views_30d=views_30d,
        posts_total=posts_total,
        likes_total=likes_total,
        comments_total=comments_total,
        saves_total=saves_total,
        engagement_rate=engagement_rate,
        subscribers_active=subscribers_active,
        revenue_30d=revenue_30d,
        views_series=_series(view_rows),
        followers_series=_series(follow_rows),
        top_posts=[
            TopPost(
                id=str(t.id), media_url=t.media_url, caption=t.caption,
                like_count=t.like_count or 0, comment_count=t.comment_count or 0,
                save_count=t.save_count or 0,
                engagement=(t.like_count or 0) + (t.comment_count or 0) + (t.save_count or 0),
                created_at=t.created_at,
            )
            for t in top_rows
        ],
    )


@router.get("/{earth_id}", response_model=BusinessOut)
async def public_business(
    earth_id: str,
    db: AsyncSession = Depends(get_db),
):
    """نمایهٔ عمومیِ یک کسب‌وکار (بدونِ نیاز به ورود)."""
    u = (await db.execute(select(User).where(User.earth_id == earth_id))).scalar_one_or_none()
    if u is None:
        raise HTTPException(404, detail="کاربر پیدا نشد")
    p = await _profile_of(db, u.id)
    if p is None:
        raise HTTPException(404, detail="این کاربر حسابِ کسب‌وکار ندارد")
    return _out(p, u, await _followers(db, u.id))


@router.post("/{earth_id}/view", status_code=204)
async def record_view(
    earth_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """ثبتِ بازدیدِ نمایه. هر بیننده در هر روز فقط یک‌بار شمرده می‌شود و
    بازدیدِ خودِ صاحبِ حساب اصلاً ثبت نمی‌شود."""
    u = (await db.execute(select(User).where(User.earth_id == earth_id))).scalar_one_or_none()
    if u is None:
        raise HTTPException(404, detail="کاربر پیدا نشد")
    if u.id == me.id:
        return

    db.add(ProfileView(profile_user_id=u.id, viewer_id=me.id, view_day=_now().date()))
    try:
        await db.commit()
    except Exception:
        # همان بیننده امروز قبلاً ثبت شده — این خطا نیست، یعنی تکراری است.
        await db.rollback()

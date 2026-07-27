"""
Dilix — گیمیفیکیشن (امتیاز، نشان، streak، تابلوی رتبه) — فاز ۵ (رشد)

    GET  /api/v1/gamification/me            نمایهٔ بازی: امتیاز، سطح، streak، نشان‌ها، رتبه
    POST /api/v1/gamification/check-in      ورودِ روزانه (یک‌بار در هر روز)
    GET  /api/v1/gamification/badges        کاتالوگِ نشان‌ها + پیشرفتِ واقعیِ من
    POST /api/v1/gamification/sync          اعطای نشان‌هایی که شرطشان محقق شده
    GET  /api/v1/gamification/history       دفترِ امتیازِ من
    GET  /api/v1/gamification/leaderboard   تابلوی رتبه (کل / هفتگی) + رتبهٔ من

چهار تصمیمی که ساختار را تعیین کرد:

۱) **هیچ امتیازی از هوا نمی‌آید.** شرطِ هر نشان از جدول‌های واقعیِ همین
   پلتفرم خوانده می‌شود (`posts`, `follows`, `shop_orders`, `users.referred_by`,
   `red_packets`, `bill_payments`, `users.kyc_level`). اگر امتیاز را با یک
   endpointِ «به من امتیاز بده» می‌دادیم، هر کلاینتی می‌توانست تابلوی رتبه را
   بسازد و کلِ سیستم به یک عددِ تزئینی تبدیل می‌شد.

۲) **دفترِ امتیاز append-only است و یکتاییِ `(user, kind, ref)` کلِ محافظ.**
   ورودِ روزانه با `ref = روز` و نشان با `ref = کدِ نشان` ثبت می‌شود؛ پس هم
   ورودِ دوباره در یک روز و هم اعطای دوبارهٔ یک نشان با **یک** ایندکس بی‌اثر
   می‌شود، نه با `if`ِ پایتونی که دو درخواستِ هم‌زمان از آن رد می‌شوند.

۳) **`points_total` مجموعِ کَش‌شدهٔ دفتر است، نه حقیقتِ مستقل.** جمعِ دفتر
   همیشه مرجع است؛ کَش فقط برای رتبه‌بندی است تا تابلوی رتبه مجبور نباشد
   دفترِ کلِ پلتفرم را جمع بزند. E2E این ناوردا را می‌سنجد.

۴) **streak از تاریخِ ذخیره‌شده حساب می‌شود، نه از شمارنده.** اگر آخرین ورود
   «دیروز» باشد ادامه می‌یابد و در غیرِ آن به ۱ برمی‌گردد؛ با شمارندهٔ ساده،
   کاربری که یک ماه غایب بود همان زنجیره را ادامه می‌داد.
"""
import uuid as _uuid
from datetime import date, datetime, timedelta, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from sqlalchemy import (
    BigInteger, Column, DateTime, ForeignKey, Index, Integer, String,
    func, select, text,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import Base, get_db
from app.models.user import User

router = APIRouter(prefix="/gamification", tags=["Gamification"])

# آستانهٔ سطح‌ها (امتیازِ لازم برای رسیدن به هر سطح).
LEVELS = [0, 500, 1_500, 3_500, 7_000, 12_000, 20_000, 35_000, 60_000, 100_000]

LEVEL_TITLES = [
    "تازه‌وارد", "کاوشگر", "فعال", "شناخته‌شده", "قابلِ اعتماد",
    "کهنه‌کار", "الگو", "پیشرو", "افسانه", "استادِ نقطه",
]

CHECKIN_BASE = 10          # امتیازِ پایهٔ ورودِ روزانه
CHECKIN_STREAK_BONUS = 5   # امتیازِ اضافه به‌ازای هر روزِ زنجیره
CHECKIN_STREAK_CAP = 10    # سقفِ روزهای زنجیره که پاداش می‌گیرند

# کاتالوگِ نشان‌ها: (کد، عنوان، توضیح، امتیاز، کلیدِ سیگنال، آستانه)
BADGES = [
    ("verified",   "هویتِ تأییدشده", "احرازِ هویتِ سطحِ ۲ را کامل کن",        200, "kyc_level", 2),
    ("first_post", "نخستین پست",     "نخستین پستت را منتشر کن",                50, "posts", 1),
    ("creator_10", "سازنده",         "۱۰ پست منتشر کن",                       200, "posts", 10),
    ("social_10",  "دیده‌شده",       "۱۰ دنبال‌کننده جمع کن",                 150, "followers", 10),
    ("social_100", "پُرمخاطب",       "۱۰۰ دنبال‌کننده جمع کن",                500, "followers", 100),
    ("shopper",    "خریدار",         "نخستین خریدت را کامل کن",               100, "purchases", 1),
    ("merchant",   "فروشنده",        "نخستین فروشت را کامل کن",               200, "sales", 1),
    ("inviter",    "دعوت‌کننده",     "یک نفر را با کدِ دعوتت بیاور",          150, "referrals", 1),
    ("network_10", "شبکه‌ساز",       "۱۰ نفر را مستقیم دعوت کن",              400, "referrals", 10),
    ("generous",   "دست‌ودل‌باز",    "یک هدیهٔ نقدی 🧧 بفرست",                100, "packets", 1),
    ("bill_payer", "قبض‌شناس",       "یک قبض را از نقطه پرداخت کن",           100, "bills", 1),
    ("streak_7",   "هفتهٔ کامل",     "۷ روزِ پیاپی وارد شو",                  300, "longest_streak", 7),
    ("streak_30",  "ماهِ کامل",      "۳۰ روزِ پیاپی وارد شو",               1_000, "longest_streak", 30),
]
BADGE_BY_CODE = {b[0]: b for b in BADGES}

KIND_LABEL = {
    "check_in": "ورودِ روزانه",
    "badge": "نشان",
}


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _today() -> date:
    return _now().date()


# ── مدل‌ها ────────────────────────────────────────────────────────────────────
class GameProfile(Base):
    """نمایهٔ بازیِ هر کاربر — یک ردیف به‌ازای هر کاربر.

    `points_total` جمعِ کَش‌شدهٔ `point_events` است. حقیقت همیشه دفتر است؛ این
    ستون فقط برای رتبه‌بندی نگهداری می‌شود.
    """
    __tablename__ = "game_profiles"

    id = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"),
                     nullable=False, unique=True)
    points_total = Column(BigInteger, nullable=False, default=0)
    streak_days = Column(Integer, nullable=False, default=0)
    longest_streak = Column(Integer, nullable=False, default=0)
    last_check_in = Column(String(10), nullable=True)   # YYYY-MM-DD
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)
    updated_at = Column(DateTime(timezone=True), nullable=False, default=_now, onupdate=_now)


class PointEvent(Base):
    """دفترِ امتیاز (append-only).

    `ref` هرگز NULL نیست چون در Postgres مقدارِ NULL یکتایی را دور می‌زند و
    آن‌وقت ایندکسِ زیر دیگر مانعِ ورودِ دوبارهٔ روزانه نمی‌شد.
    """
    __tablename__ = "point_events"

    id = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"),
                     nullable=False, index=True)
    kind = Column(String(24), nullable=False)      # check_in | badge
    ref = Column(String(64), nullable=False, default="")
    delta = Column(BigInteger, nullable=False)
    note = Column(String(160), nullable=True)
    created_at = Column(DateTime(timezone=True), nullable=False, default=_now)

    __table_args__ = (
        Index("uq_point_event", "user_id", "kind", "ref", unique=True),
        Index("ix_point_event_recent", "created_at"),
    )


class UserBadge(Base):
    """نشانِ اعطاشده — رکوردِ رسمیِ افتخار، جدا از دفترِ امتیاز."""
    __tablename__ = "user_badges"

    id = Column(UUID(as_uuid=True), primary_key=True, default=_uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"),
                     nullable=False, index=True)
    code = Column(String(32), nullable=False)
    awarded_at = Column(DateTime(timezone=True), nullable=False, default=_now)

    __table_args__ = (
        Index("uq_user_badge", "user_id", "code", unique=True),
    )


# ── Schemas ───────────────────────────────────────────────────────────────────
class BadgeOut(BaseModel):
    code: str
    title: str
    description: str
    points: int
    earned: bool
    progress: int
    target: int
    awarded_at: Optional[datetime] = None


class LevelOut(BaseModel):
    level: int
    title: str
    points: int
    next_at: Optional[int]
    to_next: int
    progress_pct: int


class ProfileOut(BaseModel):
    points: int
    level: LevelOut
    streak_days: int
    longest_streak: int
    checked_in_today: bool
    badges_earned: int
    badges_total: int
    rank: Optional[int]
    badges: List[BadgeOut]


class PointEventOut(BaseModel):
    id: str
    kind: str
    kind_label: str
    ref: str
    delta: int
    note: Optional[str]
    created_at: datetime


class LeaderRow(BaseModel):
    rank: int
    earth_id: str
    name: str
    avatar_url: Optional[str] = None
    points: int
    level: int
    is_me: bool


class LeaderboardOut(BaseModel):
    period: str
    rows: List[LeaderRow]
    my_rank: Optional[int]
    my_points: int


class CheckInOut(BaseModel):
    ok: bool
    already: bool
    gained: int
    points: int
    streak_days: int
    longest_streak: int


class SyncOut(BaseModel):
    awarded: List[str]
    gained: int
    points: int


# ── کمکی‌ها ───────────────────────────────────────────────────────────────────
def _level_of(points: int) -> LevelOut:
    idx = 0
    for i, threshold in enumerate(LEVELS):
        if points >= threshold:
            idx = i
    level = idx + 1
    nxt = LEVELS[idx + 1] if idx + 1 < len(LEVELS) else None
    base = LEVELS[idx]
    if nxt is None:
        return LevelOut(level=level, title=LEVEL_TITLES[idx], points=points,
                        next_at=None, to_next=0, progress_pct=100)
    span = nxt - base
    pct = int(((points - base) / span) * 100) if span > 0 else 0
    return LevelOut(level=level, title=LEVEL_TITLES[idx], points=points,
                    next_at=nxt, to_next=max(0, nxt - points),
                    progress_pct=max(0, min(100, pct)))


async def _profile(db: AsyncSession, user_id) -> GameProfile:
    p = (await db.execute(
        select(GameProfile).where(GameProfile.user_id == user_id)
    )).scalar_one_or_none()
    if p is None:
        p = GameProfile(user_id=user_id)
        db.add(p)
        try:
            await db.flush()
        except IntegrityError:
            # دو درخواستِ هم‌زمانِ نخستین‌بار؛ برندهٔ مسابقه ردیف را ساخته است.
            await db.rollback()
            p = (await db.execute(
                select(GameProfile).where(GameProfile.user_id == user_id)
            )).scalar_one()
    return p


async def _signals(db: AsyncSession, me: User) -> dict:
    """شمارشِ سیگنال‌های واقعی از جدول‌های موجود — همه در یک رفت‌وبرگشت."""
    row = (await db.execute(text("""
        SELECT
          (SELECT count(*) FROM posts WHERE author_id = :u)                                  AS posts,
          (SELECT count(*) FROM follows WHERE following_id = :u)                             AS followers,
          (SELECT count(*) FROM shop_orders WHERE seller_id = :u AND status = 'completed')   AS sales,
          (SELECT count(*) FROM shop_orders WHERE buyer_id  = :u AND status = 'completed')   AS purchases,
          (SELECT count(*) FROM users WHERE referred_by = :u)                                AS referrals,
          (SELECT count(*) FROM red_packets WHERE sender_id = :u)                            AS packets,
          (SELECT count(*) FROM bill_payments WHERE user_id = :u)                            AS bills
    """), {"u": str(me.id)})).mappings().one()
    return {k: int(v or 0) for k, v in row.items()}


async def _earned_map(db: AsyncSession, user_id) -> dict:
    rows = (await db.execute(
        select(UserBadge).where(UserBadge.user_id == user_id)
    )).scalars().all()
    return {b.code: b for b in rows}


def _badge_rows(signals: dict, prof: GameProfile, me: User, earned: dict) -> List[BadgeOut]:
    out: List[BadgeOut] = []
    for code, title, desc, pts, key, target in BADGES:
        if key == "kyc_level":
            progress = int(me.kyc_level or 0)
        elif key == "longest_streak":
            progress = int(prof.longest_streak or 0)
        else:
            progress = int(signals.get(key, 0))
        b = earned.get(code)
        out.append(BadgeOut(
            code=code, title=title, description=desc, points=pts,
            earned=b is not None, progress=min(progress, target), target=target,
            awarded_at=b.awarded_at if b else None,
        ))
    return out


async def _add_points(db: AsyncSession, prof: GameProfile, kind: str, ref: str,
                      delta: int, note: str) -> bool:
    """یک ردیفِ دفتر می‌افزاید و کَشِ مجموع را به‌روز می‌کند.

    برخوردِ ایندکسِ یکتا داخلِ SAVEPOINT گرفته می‌شود تا تراکنشِ بیرونی — که
    ممکن است چند نشان را با هم اعطا کند — با نخستین تکراری زمین نخورد.
    """
    sp = await db.begin_nested()
    try:
        db.add(PointEvent(user_id=prof.user_id, kind=kind, ref=ref,
                          delta=delta, note=note))
        await db.flush()
    except IntegrityError:
        await sp.rollback()
        return False
    prof.points_total = (prof.points_total or 0) + delta
    return True


# ── GET /gamification/me ──────────────────────────────────────────────────────
@router.get("/me", response_model=ProfileOut)
async def my_game_profile(
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    prof = await _profile(db, me.id)
    await db.commit()

    signals = await _signals(db, me)
    earned = await _earned_map(db, me.id)
    badges = _badge_rows(signals, prof, me, earned)

    rank = None
    if (prof.points_total or 0) > 0:
        higher = (await db.execute(
            select(func.count()).select_from(GameProfile)
            .where(GameProfile.points_total > prof.points_total)
        )).scalar() or 0
        rank = int(higher) + 1

    return ProfileOut(
        points=int(prof.points_total or 0),
        level=_level_of(int(prof.points_total or 0)),
        streak_days=int(prof.streak_days or 0),
        longest_streak=int(prof.longest_streak or 0),
        checked_in_today=(prof.last_check_in == _today().isoformat()),
        badges_earned=len(earned),
        badges_total=len(BADGES),
        rank=rank,
        badges=badges,
    )


# ── POST /gamification/check-in ───────────────────────────────────────────────
@router.post("/check-in", response_model=CheckInOut)
async def check_in(
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """ورودِ روزانه. تکرار در همان روز بی‌اثر است (نه خطا)."""
    prof = await _profile(db, me.id)
    today = _today()
    today_s = today.isoformat()

    if prof.last_check_in == today_s:
        await db.commit()
        return CheckInOut(ok=True, already=True, gained=0,
                          points=int(prof.points_total or 0),
                          streak_days=int(prof.streak_days or 0),
                          longest_streak=int(prof.longest_streak or 0))

    yesterday = (today - timedelta(days=1)).isoformat()
    streak = (int(prof.streak_days or 0) + 1) if prof.last_check_in == yesterday else 1
    gain = CHECKIN_BASE + min(streak, CHECKIN_STREAK_CAP) * CHECKIN_STREAK_BONUS

    added = await _add_points(db, prof, "check_in", today_s, gain,
                              f"ورودِ روزانه — زنجیرهٔ {streak} روزه")
    if not added:
        # ردیفِ امروز از پیش بود (درخواستِ هم‌زمان)؛ فقط وضعیت را برمی‌گردانیم.
        await db.commit()
        return CheckInOut(ok=True, already=True, gained=0,
                          points=int(prof.points_total or 0),
                          streak_days=int(prof.streak_days or 0),
                          longest_streak=int(prof.longest_streak or 0))

    prof.streak_days = streak
    prof.longest_streak = max(int(prof.longest_streak or 0), streak)
    prof.last_check_in = today_s
    await db.commit()

    return CheckInOut(ok=True, already=False, gained=gain,
                      points=int(prof.points_total or 0),
                      streak_days=streak,
                      longest_streak=int(prof.longest_streak or 0))


# ── GET /gamification/badges ──────────────────────────────────────────────────
@router.get("/badges", response_model=List[BadgeOut])
async def badge_catalog(
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    prof = await _profile(db, me.id)
    await db.commit()
    signals = await _signals(db, me)
    earned = await _earned_map(db, me.id)
    return _badge_rows(signals, prof, me, earned)


# ── POST /gamification/sync ───────────────────────────────────────────────────
@router.post("/sync", response_model=SyncOut)
async def sync_badges(
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """نشان‌هایی را که شرطشان در دادهٔ واقعی محقق شده اعطا می‌کند."""
    prof = await _profile(db, me.id)
    signals = await _signals(db, me)
    earned = await _earned_map(db, me.id)

    awarded: List[str] = []
    gained = 0
    for code, title, _desc, pts, key, target in BADGES:
        if code in earned:
            continue
        if key == "kyc_level":
            progress = int(me.kyc_level or 0)
        elif key == "longest_streak":
            progress = int(prof.longest_streak or 0)
        else:
            progress = int(signals.get(key, 0))
        if progress < target:
            continue

        sp = await db.begin_nested()
        try:
            db.add(UserBadge(user_id=me.id, code=code))
            await db.flush()
        except IntegrityError:
            await sp.rollback()
            continue
        if await _add_points(db, prof, "badge", code, pts, f"نشانِ «{title}»"):
            gained += pts
        awarded.append(code)

    await db.commit()
    return SyncOut(awarded=awarded, gained=gained, points=int(prof.points_total or 0))


# ── GET /gamification/history ─────────────────────────────────────────────────
@router.get("/history", response_model=List[PointEventOut])
async def point_history(
    limit: int = Query(50, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    rows = (await db.execute(
        select(PointEvent).where(PointEvent.user_id == me.id)
        .order_by(PointEvent.created_at.desc()).limit(limit)
    )).scalars().all()
    return [
        PointEventOut(
            id=str(r.id), kind=r.kind, kind_label=KIND_LABEL.get(r.kind, r.kind),
            ref=r.ref, delta=int(r.delta), note=r.note, created_at=r.created_at,
        ) for r in rows
    ]


# ── GET /gamification/leaderboard ─────────────────────────────────────────────
@router.get("/leaderboard", response_model=LeaderboardOut)
async def leaderboard(
    period: str = Query("all", pattern="^(all|week)$"),
    limit: int = Query(20, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """تابلوی رتبه. «هفتگی» از خودِ دفتر جمع زده می‌شود تا کاربرِ تازه‌فعال
    پشتِ امتیازِ انباشتهٔ قدیمی‌ها پنهان نماند."""
    if period == "week":
        since = _now() - timedelta(days=7)
        agg = (
            select(PointEvent.user_id.label("uid"),
                   func.sum(PointEvent.delta).label("pts"))
            .where(PointEvent.created_at >= since)
            .group_by(PointEvent.user_id)
        ).subquery()
        stmt = (
            select(User, agg.c.pts, GameProfile.points_total)
            .join(User, User.id == agg.c.uid)
            .outerjoin(GameProfile, GameProfile.user_id == agg.c.uid)
            .order_by(agg.c.pts.desc())
            .limit(limit)
        )
        rows = (await db.execute(stmt)).all()
        scored = [(u, int(pts or 0), int(total or 0)) for u, pts, total in rows]

        mine = (await db.execute(
            select(func.coalesce(func.sum(PointEvent.delta), 0))
            .where(PointEvent.user_id == me.id, PointEvent.created_at >= since)
        )).scalar() or 0
        my_points = int(mine)
        my_rank = None
        if my_points > 0:
            higher = (await db.execute(
                select(func.count()).select_from(agg).where(agg.c.pts > my_points)
            )).scalar() or 0
            my_rank = int(higher) + 1
    else:
        stmt = (
            select(User, GameProfile.points_total)
            .join(GameProfile, GameProfile.user_id == User.id)
            .where(GameProfile.points_total > 0)
            .order_by(GameProfile.points_total.desc())
            .limit(limit)
        )
        rows = (await db.execute(stmt)).all()
        scored = [(u, int(total or 0), int(total or 0)) for u, total in rows]

        prof = (await db.execute(
            select(GameProfile).where(GameProfile.user_id == me.id)
        )).scalar_one_or_none()
        my_points = int(prof.points_total or 0) if prof else 0
        my_rank = None
        if my_points > 0:
            higher = (await db.execute(
                select(func.count()).select_from(GameProfile)
                .where(GameProfile.points_total > my_points)
            )).scalar() or 0
            my_rank = int(higher) + 1

    out_rows = [
        LeaderRow(
            rank=i + 1,
            earth_id=u.earth_id,
            name=(u.full_name or u.username or u.earth_id),
            avatar_url=u.avatar_url,
            points=pts,
            level=_level_of(total).level,
            is_me=(u.id == me.id),
        )
        for i, (u, pts, total) in enumerate(scored)
    ]
    return LeaderboardOut(period=period, rows=out_rows,
                          my_rank=my_rank, my_points=my_points)

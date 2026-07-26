"""
Dilix — Social Graph Router (فاز ۰: گرافِ اجتماعی)
POST   /api/v1/social/follow                دنبال‌کردنِ یک کاربر (با earth_id)
DELETE /api/v1/social/follow/{earth_id}     لغوِ دنبال‌کردن
GET    /api/v1/social/profile/{earth_id}    کارتِ پروفایل + شمارنده‌ها + وضعیتِ رابطه
GET    /api/v1/social/followers/{earth_id}  دنبال‌کنندگان
GET    /api/v1/social/following/{earth_id}  دنبال‌شده‌ها
GET    /api/v1/social/suggestions           پیشنهادِ افراد برای دنبال‌کردن
"""
import io as _io
import re as _re
from typing import Optional, List

from fastapi import APIRouter, Depends, HTTPException, status, Query, Response
from pydantic import BaseModel, Field
from sqlalchemy import select, and_, or_, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.models.social import Follow

router = APIRouter(prefix="/social", tags=["Social"])


# ── Schemas ───────────────────────────────────────────────────
class UserMini(BaseModel):
    earth_id: str
    name: str
    username: Optional[str] = None
    avatar_url: Optional[str] = None
    role: Optional[str] = None
    kyc_level: int = 0
    is_following: bool = False   # آیا «من» این کاربر را دنبال می‌کنم


class ProfileOut(BaseModel):
    earth_id: str
    name: str
    username: Optional[str] = None
    avatar_url: Optional[str] = None
    bio: Optional[str] = None
    role: Optional[str] = None
    kyc_level: int = 0
    followers_count: int = 0
    following_count: int = 0
    is_following: bool = False     # من او را دنبال می‌کنم
    is_followed_by: bool = False   # او مرا دنبال می‌کند
    is_me: bool = False


class FollowRequest(BaseModel):
    earth_id: str = Field(..., description="Earth ID طرف مقابل (DLX-XXXXXXXX)")


class FollowResult(BaseModel):
    ok: bool = True
    following: bool
    followers_count: int


# ── Helpers ───────────────────────────────────────────────────
async def _user_by_earth_id(db: AsyncSession, earth_id: str) -> User:
    r = await db.execute(select(User).where(User.earth_id == earth_id))
    u = r.scalar_one_or_none()
    if not u:
        raise HTTPException(status_code=404, detail="کاربر پیدا نشد")
    return u


async def _count_followers(db: AsyncSession, user_id) -> int:
    r = await db.execute(
        select(func.count(Follow.id)).where(Follow.following_id == user_id)
    )
    return int(r.scalar_one() or 0)


async def _count_following(db: AsyncSession, user_id) -> int:
    r = await db.execute(
        select(func.count(Follow.id)).where(Follow.follower_id == user_id)
    )
    return int(r.scalar_one() or 0)


async def _is_following(db: AsyncSession, follower_id, following_id) -> bool:
    r = await db.execute(
        select(Follow.id).where(
            and_(Follow.follower_id == follower_id, Follow.following_id == following_id)
        )
    )
    return r.scalar_one_or_none() is not None


async def _my_following_ids(db: AsyncSession, me_id) -> set:
    r = await db.execute(select(Follow.following_id).where(Follow.follower_id == me_id))
    return {row[0] for row in r.all()}


def _name(u: User) -> str:
    return u.full_name or u.username or u.earth_id


# ── Endpoints ─────────────────────────────────────────────────
@router.post("/follow", response_model=FollowResult, status_code=status.HTTP_201_CREATED)
async def follow_user(
    body: FollowRequest,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """کاربرِ دیگر را دنبال کن (idempotent)."""
    if body.earth_id == me.earth_id:
        raise HTTPException(status_code=400, detail="نمی‌توانید خودتان را دنبال کنید")

    target = await _user_by_earth_id(db, body.earth_id)

    if not await _is_following(db, me.id, target.id):
        db.add(Follow(follower_id=me.id, following_id=target.id))
        await db.commit()

    return FollowResult(
        following=True,
        followers_count=await _count_followers(db, target.id),
    )


@router.delete("/follow/{earth_id}", response_model=FollowResult)
async def unfollow_user(
    earth_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """لغوِ دنبال‌کردن."""
    target = await _user_by_earth_id(db, earth_id)

    r = await db.execute(
        select(Follow).where(
            and_(Follow.follower_id == me.id, Follow.following_id == target.id)
        )
    )
    existing = r.scalar_one_or_none()
    if existing:
        await db.delete(existing)
        await db.commit()

    return FollowResult(
        following=False,
        followers_count=await _count_followers(db, target.id),
    )


@router.get("/profile/{earth_id}", response_model=ProfileOut)
async def get_profile(
    earth_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """کارتِ پروفایل با شمارنده‌ها و وضعیتِ رابطه نسبت به من."""
    u = await _user_by_earth_id(db, earth_id)
    is_me = u.id == me.id
    return ProfileOut(
        earth_id=u.earth_id,
        name=_name(u),
        username=u.username,
        avatar_url=u.avatar_url,
        bio=u.bio,
        role=u.role,
        kyc_level=u.kyc_level or 0,
        followers_count=await _count_followers(db, u.id),
        following_count=await _count_following(db, u.id),
        is_following=False if is_me else await _is_following(db, me.id, u.id),
        is_followed_by=False if is_me else await _is_following(db, u.id, me.id),
        is_me=is_me,
    )


@router.get("/followers/{earth_id}", response_model=List[UserMini])
async def list_followers(
    earth_id: str,
    limit: int = Query(50, le=200),
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """کسانی که این کاربر را دنبال می‌کنند."""
    u = await _user_by_earth_id(db, earth_id)
    q = (
        select(User)
        .join(Follow, Follow.follower_id == User.id)
        .where(Follow.following_id == u.id)
        .order_by(Follow.created_at.desc())
        .limit(limit)
    )
    r = await db.execute(q)
    users = r.scalars().all()
    my_following = await _my_following_ids(db, me.id)
    return [
        UserMini(
            earth_id=x.earth_id, name=_name(x), username=x.username,
            avatar_url=x.avatar_url, role=x.role, kyc_level=x.kyc_level or 0,
            is_following=x.id in my_following,
        )
        for x in users
    ]


@router.get("/following/{earth_id}", response_model=List[UserMini])
async def list_following(
    earth_id: str,
    limit: int = Query(50, le=200),
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """کسانی که این کاربر آن‌ها را دنبال می‌کند."""
    u = await _user_by_earth_id(db, earth_id)
    q = (
        select(User)
        .join(Follow, Follow.following_id == User.id)
        .where(Follow.follower_id == u.id)
        .order_by(Follow.created_at.desc())
        .limit(limit)
    )
    r = await db.execute(q)
    users = r.scalars().all()
    my_following = await _my_following_ids(db, me.id)
    return [
        UserMini(
            earth_id=x.earth_id, name=_name(x), username=x.username,
            avatar_url=x.avatar_url, role=x.role, kyc_level=x.kyc_level or 0,
            is_following=x.id in my_following,
        )
        for x in users
    ]


@router.get("/suggestions", response_model=List[UserMini])
async def suggestions(
    limit: int = Query(20, le=50),
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """پیشنهادِ افراد برای دنبال‌کردن: کسانی که هنوز دنبالشان نمی‌کنم."""
    my_following = await _my_following_ids(db, me.id)
    exclude = set(my_following) | {me.id}
    q = (
        select(User)
        .where(User.status == "active")
        .order_by(User.last_login_at.desc().nullslast())
        .limit(limit + len(exclude) + 5)
    )
    r = await db.execute(q)
    out: List[UserMini] = []
    for x in r.scalars().all():
        if x.id in exclude:
            continue
        out.append(UserMini(
            earth_id=x.earth_id, name=_name(x), username=x.username,
            avatar_url=x.avatar_url, role=x.role, kyc_level=x.kyc_level or 0,
            is_following=False,
        ))
        if len(out) >= limit:
            break
    return out


@router.get("/search", response_model=List[UserMini])
async def search_users(
    q: str = Query(..., min_length=1, max_length=50, description="نام، یوزرنیم یا Earth ID"),
    limit: int = Query(20, le=50),
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """جستجوی کاربر بر اساس نام، یوزرنیم یا Earth ID."""
    term = q.strip()
    like = f"%{term}%"
    query = (
        select(User)
        .where(
            and_(
                User.id != me.id,
                User.status == "active",
                or_(
                    User.full_name.ilike(like),
                    User.username.ilike(like),
                    User.earth_id.ilike(like),
                ),
            )
        )
        .order_by(User.last_login_at.desc().nullslast())
        .limit(limit)
    )
    r = await db.execute(query)
    users = r.scalars().all()
    my_following = await _my_following_ids(db, me.id)
    return [
        UserMini(
            earth_id=x.earth_id, name=_name(x), username=x.username,
            avatar_url=x.avatar_url, role=x.role, kyc_level=x.kyc_level or 0,
            is_following=x.id in my_following,
        )
        for x in users
    ]


# QR پروفایل — عمومی (فقط یک URL عمومی را کد می‌کند، بدون راز)
_EARTH_ID_RE = _re.compile(r"^DLX-[A-Z0-9]{4,16}$")


@router.get("/qr/{earth_id}")
async def profile_qr(earth_id: str):
    """SVG کد QR که لینک پروفایل (https://dilix.ir/u/{earth_id}) را کد می‌کند."""
    eid = earth_id.strip().upper()
    if not _EARTH_ID_RE.match(eid):
        raise HTTPException(status_code=404, detail="شناسه‌ی نامعتبر")
    import segno
    url = f"https://dilix.ir/u/{eid}"
    buf = _io.BytesIO()
    segno.make(url, error="m").save(
        buf, kind="svg", scale=7, border=3, dark="#0A0A0A", light="#FFFFFF"
    )
    return Response(
        content=buf.getvalue(),
        media_type="image/svg+xml",
        headers={"Cache-Control": "public, max-age=86400"},
    )

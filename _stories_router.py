"""
Dilix — Stories Router (داستانِ ۲۴ساعته)

POST   /api/v1/stories                     ساخت داستان (آپلود عکس/ویدیو + کپشن)
GET    /api/v1/stories/feed                نوارِ داستان‌ها (خودم + دنبال‌شده‌ها که داستانِ فعال دارند)
GET    /api/v1/stories/user/{earth_id}     داستان‌های فعالِ یک کاربر (به‌ترتیبِ زمانی)
POST   /api/v1/stories/{story_id}/view     ثبتِ بازدید (idempotent)
GET    /api/v1/stories/{story_id}/viewers  بازدیدکنندگان (فقط نویسنده)
DELETE /api/v1/stories/{story_id}          حذفِ داستانِ خودم
"""
import os
import uuid as _uuid
from datetime import datetime, timezone
from typing import Optional, List

from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File, Form
from pydantic import BaseModel
from sqlalchemy import select, func, and_
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.models.social import Follow
from app.models.stories import Story, StoryView

router = APIRouter(prefix="/stories", tags=["Stories"])

# ── Media storage ────────────────────────────────────────────
STORY_DIR = "/var/www/dilix-api/uploads/stories"
STORY_BASE_URL = "/uploads/stories"
_IMAGE_TYPES = {"image/jpeg", "image/png", "image/webp", "image/gif"}
_VIDEO_TYPES = {"video/webm", "video/mp4", "video/ogg", "video/quicktime"}
_MAX_STORY_SIZE = 30 * 1024 * 1024  # 30 MB


def _classify(content_type: str) -> str:
    ct = (content_type or "").split(";")[0].strip().lower()
    if ct in _VIDEO_TYPES or ct.startswith("video/"):
        return "video"
    return "image"


def _ext_for(media_type: str, filename: str) -> str:
    ext = os.path.splitext(filename or "")[1].lower()
    if ext:
        return ext
    return {"image": ".jpg", "video": ".webm"}.get(media_type, ".bin")


def _now():
    return datetime.now(timezone.utc)


def _name(u: User) -> str:
    return u.full_name or u.username or u.earth_id


# ── Schemas ──────────────────────────────────────────────────
class StoryOut(BaseModel):
    id: str
    author_earth_id: str
    author_name: str
    author_avatar: Optional[str] = None
    media_url: str
    media_type: str
    caption: Optional[str] = None
    view_count: int = 0
    viewed_by_me: bool = False
    is_mine: bool = False
    created_at: datetime


class RingOut(BaseModel):
    earth_id: str
    name: str
    avatar_url: Optional[str] = None
    story_count: int = 0
    has_unseen: bool = False
    is_me: bool = False
    latest_at: datetime


class ViewerOut(BaseModel):
    earth_id: str
    name: str
    avatar_url: Optional[str] = None
    viewed_at: datetime


# ── Helpers ──────────────────────────────────────────────────
async def _my_following_ids(db: AsyncSession, me_id) -> set:
    r = await db.execute(select(Follow.following_id).where(Follow.follower_id == me_id))
    return {row[0] for row in r.all()}


# ── Endpoints ────────────────────────────────────────────────
@router.post("", response_model=StoryOut, status_code=status.HTTP_201_CREATED)
async def create_story(
    file: UploadFile = File(...),
    caption: Optional[str] = Form(None),
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """آپلودِ یک داستانِ جدید (عکس یا ویدیو) با انقضای ۲۴ساعته."""
    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="فایل خالی است")
    if len(data) > _MAX_STORY_SIZE:
        raise HTTPException(status_code=413, detail="حجم داستان نباید بیشتر از ۳۰ مگابایت باشد")

    media_type = _classify(file.content_type or "")
    ext = _ext_for(media_type, file.filename or "")
    fname = f"{me.earth_id}_{_uuid.uuid4().hex[:10]}{ext}"
    os.makedirs(STORY_DIR, exist_ok=True)
    with open(os.path.join(STORY_DIR, fname), "wb") as f:
        f.write(data)
    media_url = f"{STORY_BASE_URL}/{fname}"

    s = Story(
        author_id=me.id, media_url=media_url, media_type=media_type,
        caption=(caption or "").strip()[:500] or None,
    )
    db.add(s)
    await db.commit()
    await db.refresh(s)
    return StoryOut(
        id=str(s.id), author_earth_id=me.earth_id, author_name=_name(me),
        author_avatar=me.avatar_url, media_url=s.media_url, media_type=s.media_type,
        caption=s.caption, view_count=0, viewed_by_me=False, is_mine=True,
        created_at=s.created_at,
    )


@router.get("/feed", response_model=List[RingOut])
async def stories_feed(
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """نوارِ داستان‌ها: خودم + کسانی که دنبال می‌کنم و داستانِ فعال دارند."""
    author_ids = await _my_following_ids(db, me.id)
    author_ids.add(me.id)

    now = _now()
    q = (
        select(Story.id, Story.author_id, Story.created_at)
        .where(and_(Story.author_id.in_(author_ids), Story.expires_at > now))
    )
    r = await db.execute(q)
    rows = r.all()
    if not rows:
        return []

    story_ids = [row[0] for row in rows]
    # داستان‌هایی که «من» دیده‌ام
    rv = await db.execute(
        select(StoryView.story_id).where(
            and_(StoryView.viewer_id == me.id, StoryView.story_id.in_(story_ids))
        )
    )
    seen_ids = {row[0] for row in rv.all()}

    # گروه‌بندی بر اساس نویسنده
    by_author: dict = {}
    for sid, aid, created in rows:
        g = by_author.setdefault(aid, {"count": 0, "latest": created, "unseen": False})
        g["count"] += 1
        if created > g["latest"]:
            g["latest"] = created
        if sid not in seen_ids:
            g["unseen"] = True

    # اطلاعاتِ کاربران
    ru = await db.execute(select(User).where(User.id.in_(list(by_author.keys()))))
    users = {u.id: u for u in ru.scalars().all()}

    rings: List[RingOut] = []
    for aid, g in by_author.items():
        u = users.get(aid)
        if not u:
            continue
        rings.append(RingOut(
            earth_id=u.earth_id, name=_name(u), avatar_url=u.avatar_url,
            story_count=g["count"], has_unseen=g["unseen"],
            is_me=(aid == me.id), latest_at=g["latest"],
        ))

    # ترتیب: خودم اول، سپس دیده‌نشده‌ها، سپس بر اساسِ جدیدترین
    rings.sort(key=lambda x: (not x.is_me, not x.has_unseen, -x.latest_at.timestamp()))
    return rings


@router.get("/user/{earth_id}", response_model=List[StoryOut])
async def user_stories(
    earth_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """داستان‌های فعالِ یک کاربر، به‌ترتیبِ قدیمی→جدید."""
    ru = await db.execute(select(User).where(User.earth_id == earth_id))
    author = ru.scalar_one_or_none()
    if not author:
        raise HTTPException(status_code=404, detail="کاربر پیدا نشد")

    now = _now()
    q = (
        select(Story)
        .where(and_(Story.author_id == author.id, Story.expires_at > now))
        .order_by(Story.created_at.asc())
    )
    r = await db.execute(q)
    stories = r.scalars().all()
    if not stories:
        return []

    sids = [s.id for s in stories]
    rv = await db.execute(
        select(StoryView.story_id).where(
            and_(StoryView.viewer_id == me.id, StoryView.story_id.in_(sids))
        )
    )
    seen = {row[0] for row in rv.all()}

    is_me = author.id == me.id
    return [
        StoryOut(
            id=str(s.id), author_earth_id=author.earth_id, author_name=_name(author),
            author_avatar=author.avatar_url, media_url=s.media_url, media_type=s.media_type,
            caption=s.caption, view_count=(s.view_count or 0),
            viewed_by_me=(s.id in seen), is_mine=is_me, created_at=s.created_at,
        )
        for s in stories
    ]


@router.post("/{story_id}/view", status_code=status.HTTP_204_NO_CONTENT)
async def view_story(
    story_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """ثبتِ بازدیدِ من (idempotent). بازدیدِ خودِ نویسنده شمارش نمی‌شود."""
    try:
        sid = _uuid.UUID(story_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="داستان پیدا نشد")
    s = await db.get(Story, sid)
    if not s:
        raise HTTPException(status_code=404, detail="داستان پیدا نشد")
    if s.author_id == me.id:
        return  # نویسنده بازدیدِ خودش را نمی‌سازد

    exists = await db.execute(
        select(StoryView.id).where(
            and_(StoryView.story_id == sid, StoryView.viewer_id == me.id)
        )
    )
    if exists.scalar_one_or_none() is None:
        db.add(StoryView(story_id=sid, viewer_id=me.id))
        s.view_count = (s.view_count or 0) + 1
        await db.commit()
    return


@router.get("/{story_id}/viewers", response_model=List[ViewerOut])
async def story_viewers(
    story_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """لیستِ بازدیدکنندگان (فقط برای نویسندهٔ داستان)."""
    try:
        sid = _uuid.UUID(story_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="داستان پیدا نشد")
    s = await db.get(Story, sid)
    if not s:
        raise HTTPException(status_code=404, detail="داستان پیدا نشد")
    if s.author_id != me.id:
        raise HTTPException(status_code=403, detail="فقط نویسنده می‌تواند بازدیدکنندگان را ببیند")

    q = (
        select(User, StoryView.created_at)
        .join(StoryView, StoryView.viewer_id == User.id)
        .where(StoryView.story_id == sid)
        .order_by(StoryView.created_at.desc())
    )
    r = await db.execute(q)
    return [
        ViewerOut(earth_id=u.earth_id, name=_name(u), avatar_url=u.avatar_url, viewed_at=vat)
        for (u, vat) in r.all()
    ]


@router.delete("/{story_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_story(
    story_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """حذفِ داستانِ خودم."""
    try:
        sid = _uuid.UUID(story_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="داستان پیدا نشد")
    s = await db.get(Story, sid)
    if not s or s.author_id != me.id:
        raise HTTPException(status_code=404, detail="داستان پیدا نشد")
    await db.delete(s)
    await db.commit()
    return

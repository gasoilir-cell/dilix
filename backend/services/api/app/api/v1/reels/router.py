"""
Dilix — Reels Router (ویدیوهای کوتاهِ عمودی)

POST   /api/v1/reels                    ساختِ ریلز (آپلود ویدیو/عکس + کپشن)
GET    /api/v1/reels/feed               فیدِ کشف (جدیدترین‌ها، cursor-paginated)
GET    /api/v1/reels/user/{earth_id}    ریلزهای یک کاربر (گرید)
POST   /api/v1/reels/{id}/view          ثبتِ بازدید (شمارنده)
POST   /api/v1/reels/{id}/like          لایک/آنلایک (toggle)
GET    /api/v1/reels/{id}/comments      لیستِ کامنت‌ها
POST   /api/v1/reels/{id}/comments      افزودنِ کامنت
DELETE /api/v1/reels/comments/{cid}     حذفِ کامنتِ خودم
DELETE /api/v1/reels/{id}               حذفِ ریلزِ خودم
"""
import os
import uuid as _uuid
from datetime import datetime, timezone
from typing import Optional, List

from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File, Form, Query
from pydantic import BaseModel
from sqlalchemy import select, and_, delete as sa_delete
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.models.reels import Reel, ReelLike, ReelComment

router = APIRouter(prefix="/reels", tags=["Reels"])

# ── Media storage ────────────────────────────────────────────
REEL_DIR = "/var/www/dilix-api/uploads/reels"
REEL_BASE_URL = "/uploads/reels"
_VIDEO_TYPES = {"video/webm", "video/mp4", "video/ogg", "video/quicktime"}
_MAX_REEL_SIZE = 60 * 1024 * 1024  # 60 MB


def _classify(content_type: str) -> str:
    ct = (content_type or "").split(";")[0].strip().lower()
    if ct.startswith("image/"):
        return "image"
    return "video"


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
class ReelOut(BaseModel):
    id: str
    author_earth_id: str
    author_name: str
    author_avatar: Optional[str] = None
    media_url: str
    media_type: str
    caption: Optional[str] = None
    view_count: int = 0
    like_count: int = 0
    comment_count: int = 0
    liked_by_me: bool = False
    is_mine: bool = False
    created_at: datetime


class FeedOut(BaseModel):
    items: List[ReelOut]
    next_cursor: Optional[str] = None


class LikeOut(BaseModel):
    liked: bool
    like_count: int


class CommentOut(BaseModel):
    id: str
    author_earth_id: str
    author_name: str
    author_avatar: Optional[str] = None
    body: str
    is_mine: bool = False
    created_at: datetime


# ── Helpers ──────────────────────────────────────────────────
async def _liked_set(db: AsyncSession, me_id, reel_ids: List) -> set:
    if not reel_ids:
        return set()
    r = await db.execute(
        select(ReelLike.reel_id).where(
            and_(ReelLike.user_id == me_id, ReelLike.reel_id.in_(reel_ids))
        )
    )
    return {row[0] for row in r.all()}


def _to_out(r: Reel, author: User, me_id, liked: set) -> ReelOut:
    return ReelOut(
        id=str(r.id), author_earth_id=author.earth_id, author_name=_name(author),
        author_avatar=author.avatar_url, media_url=r.media_url, media_type=r.media_type,
        caption=r.caption, view_count=(r.view_count or 0), like_count=(r.like_count or 0),
        comment_count=(r.comment_count or 0), liked_by_me=(r.id in liked),
        is_mine=(r.author_id == me_id), created_at=r.created_at,
    )


# ── Endpoints ────────────────────────────────────────────────
@router.post("", response_model=ReelOut, status_code=status.HTTP_201_CREATED)
async def create_reel(
    file: UploadFile = File(...),
    caption: Optional[str] = Form(None),
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """آپلودِ یک ریلزِ جدید (ویدیو یا عکس)."""
    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="فایل خالی است")
    if len(data) > _MAX_REEL_SIZE:
        raise HTTPException(status_code=413, detail="حجم ریلز نباید بیشتر از ۶۰ مگابایت باشد")

    media_type = _classify(file.content_type or "")
    ext = _ext_for(media_type, file.filename or "")
    fname = f"{me.earth_id}_{_uuid.uuid4().hex[:10]}{ext}"
    os.makedirs(REEL_DIR, exist_ok=True)
    with open(os.path.join(REEL_DIR, fname), "wb") as f:
        f.write(data)
    media_url = f"{REEL_BASE_URL}/{fname}"

    reel = Reel(
        author_id=me.id, media_url=media_url, media_type=media_type,
        caption=(caption or "").strip()[:2000] or None,
    )
    db.add(reel)
    await db.commit()
    await db.refresh(reel)
    return _to_out(reel, me, me.id, set())


@router.get("/feed", response_model=FeedOut)
async def reels_feed(
    cursor: Optional[str] = Query(None),
    limit: int = Query(10, ge=1, le=30),
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """فیدِ کشفِ عمومی: جدیدترین ریلزها، صفحه‌بندی با cursor (created_at ISO)."""
    q = select(Reel).order_by(Reel.created_at.desc()).limit(limit + 1)
    if cursor:
        try:
            cur_dt = datetime.fromisoformat(cursor)
            q = select(Reel).where(Reel.created_at < cur_dt).order_by(Reel.created_at.desc()).limit(limit + 1)
        except ValueError:
            pass
    r = await db.execute(q)
    reels = r.scalars().all()

    next_cursor = None
    if len(reels) > limit:
        next_cursor = reels[limit - 1].created_at.isoformat()
        reels = reels[:limit]

    if not reels:
        return FeedOut(items=[], next_cursor=None)

    author_ids = {x.author_id for x in reels}
    ru = await db.execute(select(User).where(User.id.in_(list(author_ids))))
    authors = {u.id: u for u in ru.scalars().all()}
    liked = await _liked_set(db, me.id, [x.id for x in reels])

    items = [_to_out(x, authors[x.author_id], me.id, liked) for x in reels if x.author_id in authors]
    return FeedOut(items=items, next_cursor=next_cursor)


@router.get("/user/{earth_id}", response_model=List[ReelOut])
async def user_reels(
    earth_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """ریلزهای یک کاربر (جدید→قدیم)."""
    ru = await db.execute(select(User).where(User.earth_id == earth_id))
    author = ru.scalar_one_or_none()
    if not author:
        raise HTTPException(status_code=404, detail="کاربر پیدا نشد")
    r = await db.execute(
        select(Reel).where(Reel.author_id == author.id).order_by(Reel.created_at.desc())
    )
    reels = r.scalars().all()
    liked = await _liked_set(db, me.id, [x.id for x in reels])
    return [_to_out(x, author, me.id, liked) for x in reels]


@router.post("/{reel_id}/view", status_code=status.HTTP_204_NO_CONTENT)
async def view_reel(
    reel_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """افزایشِ شمارندهٔ بازدید."""
    try:
        rid = _uuid.UUID(reel_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="ریلز پیدا نشد")
    reel = await db.get(Reel, rid)
    if not reel:
        raise HTTPException(status_code=404, detail="ریلز پیدا نشد")
    reel.view_count = (reel.view_count or 0) + 1
    await db.commit()
    return


@router.post("/{reel_id}/like", response_model=LikeOut)
async def toggle_like(
    reel_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """لایک/آنلایک (toggle)."""
    try:
        rid = _uuid.UUID(reel_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="ریلز پیدا نشد")
    reel = await db.get(Reel, rid)
    if not reel:
        raise HTTPException(status_code=404, detail="ریلز پیدا نشد")

    ex = await db.execute(
        select(ReelLike.id).where(and_(ReelLike.reel_id == rid, ReelLike.user_id == me.id))
    )
    row = ex.scalar_one_or_none()
    if row is None:
        db.add(ReelLike(reel_id=rid, user_id=me.id))
        reel.like_count = (reel.like_count or 0) + 1
        liked = True
    else:
        await db.execute(sa_delete(ReelLike).where(ReelLike.id == row))
        reel.like_count = max(0, (reel.like_count or 0) - 1)
        liked = False
    await db.commit()
    return LikeOut(liked=liked, like_count=(reel.like_count or 0))


@router.get("/{reel_id}/comments", response_model=List[CommentOut])
async def list_comments(
    reel_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """لیستِ کامنت‌های یک ریلز (جدید→قدیم)."""
    try:
        rid = _uuid.UUID(reel_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="ریلز پیدا نشد")
    q = (
        select(ReelComment, User)
        .join(User, User.id == ReelComment.author_id)
        .where(ReelComment.reel_id == rid)
        .order_by(ReelComment.created_at.desc())
    )
    r = await db.execute(q)
    return [
        CommentOut(
            id=str(c.id), author_earth_id=u.earth_id, author_name=_name(u),
            author_avatar=u.avatar_url, body=c.body, is_mine=(c.author_id == me.id),
            created_at=c.created_at,
        )
        for (c, u) in r.all()
    ]


@router.post("/{reel_id}/comments", response_model=CommentOut, status_code=status.HTTP_201_CREATED)
async def add_comment(
    reel_id: str,
    body: str = Form(...),
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """افزودنِ کامنت."""
    try:
        rid = _uuid.UUID(reel_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="ریلز پیدا نشد")
    reel = await db.get(Reel, rid)
    if not reel:
        raise HTTPException(status_code=404, detail="ریلز پیدا نشد")
    text = (body or "").strip()[:1000]
    if not text:
        raise HTTPException(status_code=400, detail="متنِ کامنت خالی است")
    c = ReelComment(reel_id=rid, author_id=me.id, body=text)
    db.add(c)
    reel.comment_count = (reel.comment_count or 0) + 1
    await db.commit()
    await db.refresh(c)
    return CommentOut(
        id=str(c.id), author_earth_id=me.earth_id, author_name=_name(me),
        author_avatar=me.avatar_url, body=c.body, is_mine=True, created_at=c.created_at,
    )


@router.delete("/comments/{comment_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_comment(
    comment_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """حذفِ کامنتِ خودم."""
    try:
        cid = _uuid.UUID(comment_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="کامنت پیدا نشد")
    c = await db.get(ReelComment, cid)
    if not c or c.author_id != me.id:
        raise HTTPException(status_code=404, detail="کامنت پیدا نشد")
    reel = await db.get(Reel, c.reel_id)
    await db.delete(c)
    if reel:
        reel.comment_count = max(0, (reel.comment_count or 0) - 1)
    await db.commit()
    return


@router.delete("/{reel_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_reel(
    reel_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """حذفِ ریلزِ خودم."""
    try:
        rid = _uuid.UUID(reel_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="ریلز پیدا نشد")
    reel = await db.get(Reel, rid)
    if not reel or reel.author_id != me.id:
        raise HTTPException(status_code=404, detail="ریلز پیدا نشد")
    await db.delete(reel)
    await db.commit()
    return

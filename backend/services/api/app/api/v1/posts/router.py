"""
Dilix — Posts Router (پستِ عکس/ویدیو + فیدِ اجتماعی)

POST   /api/v1/posts                    ساختِ پست (آپلود عکس/ویدیو + کپشن)
GET    /api/v1/posts/feed               فیدِ دنبال‌شونده‌ها + خودم (cursor)
GET    /api/v1/posts/explore            کاوشِ عمومی (جدیدترین‌های همه، cursor)
GET    /api/v1/posts/saved              پست‌های ذخیره‌شدهٔ من
GET    /api/v1/posts/user/{earth_id}    پست‌های یک کاربر (گرید)
GET    /api/v1/posts/{id}               یک پست
POST   /api/v1/posts/{id}/like          لایک/آنلایک
POST   /api/v1/posts/{id}/save          ذخیره/حذفِ ذخیره
GET    /api/v1/posts/{id}/comments      کامنت‌ها
POST   /api/v1/posts/{id}/comments      افزودنِ کامنت
DELETE /api/v1/posts/comments/{cid}     حذفِ کامنتِ خودم
DELETE /api/v1/posts/{id}               حذفِ پستِ خودم
"""
import os
import re
import uuid as _uuid
from datetime import datetime, timezone, timedelta
from typing import Optional, List

from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File, Form, Query
from pydantic import BaseModel
from sqlalchemy import select, and_, func, distinct, delete as sa_delete
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.models.social import Follow
from app.models.posts import Post, PostLike, PostComment, PostSave, PostHashtag

router = APIRouter(prefix="/posts", tags=["Posts"])

POST_DIR = "/var/www/dilix-api/uploads/posts"
POST_BASE_URL = "/uploads/posts"
_MAX_POST_SIZE = 50 * 1024 * 1024  # 50 MB


def _classify(content_type: str) -> str:
    ct = (content_type or "").split(";")[0].strip().lower()
    if ct.startswith("video/"):
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


# استخراجِ هشتگ از متن (پشتیبانی از فارسی، لاتین، عدد، زیرخط و ZWNJ)
_HASHTAG_RE = re.compile(r"#([0-9A-Za-z_\u0600-\u06FF\u200c]{1,80})")


def _extract_tags(text: Optional[str]) -> List[str]:
    if not text:
        return []
    seen: List[str] = []
    for raw in _HASHTAG_RE.findall(text):
        t = raw.strip("_\u200c").lower()
        if t and t not in seen:
            seen.append(t)
        if len(seen) >= 10:
            break
    return seen


# ── Schemas ──────────────────────────────────────────────────
class PostOut(BaseModel):
    id: str
    author_earth_id: str
    author_name: str
    author_avatar: Optional[str] = None
    media_url: str
    media_type: str
    caption: Optional[str] = None
    like_count: int = 0
    comment_count: int = 0
    liked_by_me: bool = False
    saved_by_me: bool = False
    is_mine: bool = False
    lat: Optional[float] = None
    lng: Optional[float] = None
    place_name: Optional[str] = None
    created_at: datetime


class FeedOut(BaseModel):
    items: List[PostOut]
    next_cursor: Optional[str] = None


class LikeOut(BaseModel):
    liked: bool
    like_count: int


class SaveOut(BaseModel):
    saved: bool


class CommentOut(BaseModel):
    id: str
    author_earth_id: str
    author_name: str
    author_avatar: Optional[str] = None
    body: str
    is_mine: bool = False
    created_at: datetime


# ── Helpers ──────────────────────────────────────────────────
async def _my_following_ids(db: AsyncSession, me_id) -> set:
    r = await db.execute(select(Follow.following_id).where(Follow.follower_id == me_id))
    return {row[0] for row in r.all()}


async def _flags(db: AsyncSession, me_id, post_ids: List):
    if not post_ids:
        return set(), set()
    rl = await db.execute(
        select(PostLike.post_id).where(and_(PostLike.user_id == me_id, PostLike.post_id.in_(post_ids)))
    )
    rs = await db.execute(
        select(PostSave.post_id).where(and_(PostSave.user_id == me_id, PostSave.post_id.in_(post_ids)))
    )
    return {x[0] for x in rl.all()}, {x[0] for x in rs.all()}


def _to_out(p: Post, author: User, me_id, liked: set, saved: set) -> PostOut:
    return PostOut(
        id=str(p.id), author_earth_id=author.earth_id, author_name=_name(author),
        author_avatar=author.avatar_url, media_url=p.media_url, media_type=p.media_type,
        caption=p.caption, like_count=(p.like_count or 0), comment_count=(p.comment_count or 0),
        liked_by_me=(p.id in liked), saved_by_me=(p.id in saved),
        is_mine=(p.author_id == me_id), lat=p.lat, lng=p.lng, place_name=p.place_name,
        created_at=p.created_at,
    )


async def _serialize_page(db: AsyncSession, me, posts: List[Post]) -> List[PostOut]:
    author_ids = {p.author_id for p in posts}
    ru = await db.execute(select(User).where(User.id.in_(list(author_ids))))
    authors = {u.id: u for u in ru.scalars().all()}
    liked, saved = await _flags(db, me.id, [p.id for p in posts])
    return [_to_out(p, authors[p.author_id], me.id, liked, saved) for p in posts if p.author_id in authors]


def _paginate(base, cursor: Optional[str], limit: int):
    q = base.order_by(Post.created_at.desc()).limit(limit + 1)
    if cursor:
        try:
            cur_dt = datetime.fromisoformat(cursor)
            q = base.where(Post.created_at < cur_dt).order_by(Post.created_at.desc()).limit(limit + 1)
        except ValueError:
            pass
    return q


# ── Endpoints ────────────────────────────────────────────────
@router.post("", response_model=PostOut, status_code=status.HTTP_201_CREATED)
async def create_post(
    file: UploadFile = File(...),
    caption: Optional[str] = Form(None),
    lat: Optional[float] = Form(None),
    lng: Optional[float] = Form(None),
    place_name: Optional[str] = Form(None),
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="فایل خالی است")
    if len(data) > _MAX_POST_SIZE:
        raise HTTPException(status_code=413, detail="حجم پست نباید بیشتر از ۵۰ مگابایت باشد")

    media_type = _classify(file.content_type or "")
    ext = _ext_for(media_type, file.filename or "")
    fname = f"{me.earth_id}_{_uuid.uuid4().hex[:10]}{ext}"
    os.makedirs(POST_DIR, exist_ok=True)
    with open(os.path.join(POST_DIR, fname), "wb") as f:
        f.write(data)

    # موقعیت فقط وقتی هر دو مختصات معتبر باشند ذخیره می‌شود
    glat = glng = None
    gplace = None
    if lat is not None and lng is not None and -90 <= lat <= 90 and -180 <= lng <= 180:
        glat, glng = float(lat), float(lng)
        gplace = (place_name or "").strip()[:120] or None

    cap = (caption or "").strip()[:2200] or None
    p = Post(
        author_id=me.id, media_url=f"{POST_BASE_URL}/{fname}", media_type=media_type,
        caption=cap, lat=glat, lng=glng, place_name=gplace,
    )
    db.add(p)
    await db.flush()
    for t in _extract_tags(cap):
        db.add(PostHashtag(post_id=p.id, tag=t, created_at=p.created_at))
    await db.commit()
    await db.refresh(p)
    return _to_out(p, me, me.id, set(), set())


@router.get("/feed", response_model=FeedOut)
async def feed(
    cursor: Optional[str] = Query(None),
    limit: int = Query(10, ge=1, le=30),
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    ids = await _my_following_ids(db, me.id)
    ids.add(me.id)
    q = _paginate(select(Post).where(Post.author_id.in_(list(ids))), cursor, limit)
    posts = (await db.execute(q)).scalars().all()
    next_cursor = None
    if len(posts) > limit:
        next_cursor = posts[limit - 1].created_at.isoformat()
        posts = posts[:limit]
    return FeedOut(items=await _serialize_page(db, me, posts), next_cursor=next_cursor)


@router.get("/explore", response_model=FeedOut)
async def explore(
    cursor: Optional[str] = Query(None),
    limit: int = Query(12, ge=1, le=40),
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    q = _paginate(select(Post), cursor, limit)
    posts = (await db.execute(q)).scalars().all()
    next_cursor = None
    if len(posts) > limit:
        next_cursor = posts[limit - 1].created_at.isoformat()
        posts = posts[:limit]
    return FeedOut(items=await _serialize_page(db, me, posts), next_cursor=next_cursor)


@router.get("/search", response_model=FeedOut)
async def search_posts(
    q: str = Query(..., min_length=1, max_length=80, description="جستجو در متنِ کپشنِ پست‌ها"),
    cursor: Optional[str] = Query(None),
    limit: int = Query(12, ge=1, le=40),
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """جستجوی محتوا در کپشنِ پست‌ها (جدیدترین اول، cursor-based)."""
    like = f"%{q.strip()}%"
    base = select(Post).where(Post.caption.ilike(like))
    query = _paginate(base, cursor, limit)
    posts = (await db.execute(query)).scalars().all()
    next_cursor = None
    if len(posts) > limit:
        next_cursor = posts[limit - 1].created_at.isoformat()
        posts = posts[:limit]
    return FeedOut(items=await _serialize_page(db, me, posts), next_cursor=next_cursor)


@router.get("/saved", response_model=List[PostOut])
async def saved_posts(
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    q = (
        select(Post).join(PostSave, PostSave.post_id == Post.id)
        .where(PostSave.user_id == me.id).order_by(PostSave.created_at.desc())
    )
    posts = (await db.execute(q)).scalars().all()
    return await _serialize_page(db, me, posts)


@router.get("/user/{earth_id}", response_model=List[PostOut])
async def user_posts(
    earth_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    ru = await db.execute(select(User).where(User.earth_id == earth_id))
    author = ru.scalar_one_or_none()
    if not author:
        raise HTTPException(status_code=404, detail="کاربر پیدا نشد")
    posts = (await db.execute(
        select(Post).where(Post.author_id == author.id).order_by(Post.created_at.desc())
    )).scalars().all()
    liked, saved = await _flags(db, me.id, [p.id for p in posts])
    return [_to_out(p, author, me.id, liked, saved) for p in posts]


# ── Explore بر پایهٔ علاقه (هشتگ/موضوع) ──────────────────────
class TopicOut(BaseModel):
    tag: str
    post_count: int


class TopicsOut(BaseModel):
    items: List[TopicOut]


@router.get("/topics", response_model=TopicsOut)
async def trending_topics(
    limit: int = Query(20, ge=1, le=50),
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """موضوع‌های داغ: پرتکرارترین هشتگ‌ها در ۱۴ روزِ اخیر."""
    since = _now() - timedelta(days=14)
    cnt = func.count(distinct(PostHashtag.post_id))
    q = (
        select(PostHashtag.tag, cnt.label("c"))
        .where(PostHashtag.created_at >= since)
        .group_by(PostHashtag.tag)
        .order_by(cnt.desc())
        .limit(limit)
    )
    r = await db.execute(q)
    items = [TopicOut(tag=t, post_count=int(c)) for (t, c) in r.all()]
    # اگر در ۱۴ روزِ اخیر چیزی نبود، به کلِ تاریخ برگرد
    if not items:
        q2 = (
            select(PostHashtag.tag, cnt.label("c"))
            .group_by(PostHashtag.tag).order_by(cnt.desc()).limit(limit)
        )
        r2 = await db.execute(q2)
        items = [TopicOut(tag=t, post_count=int(c)) for (t, c) in r2.all()]
    return TopicsOut(items=items)


@router.get("/topic/{tag}", response_model=FeedOut)
async def topic_feed(
    tag: str,
    cursor: Optional[str] = Query(None),
    limit: int = Query(12, ge=1, le=40),
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """فیدِ پست‌های یک موضوع/هشتگ (جدیدترین اول، cursor-based)."""
    tag_n = (tag or "").strip().lstrip("#").lower()[:80]
    if not tag_n:
        raise HTTPException(status_code=400, detail="موضوع نامعتبر است")
    tag_posts = select(PostHashtag.post_id).where(PostHashtag.tag == tag_n)
    base = select(Post).where(Post.id.in_(tag_posts))
    q = _paginate(base, cursor, limit)
    posts = (await db.execute(q)).scalars().all()
    next_cursor = None
    if len(posts) > limit:
        next_cursor = posts[limit - 1].created_at.isoformat()
        posts = posts[:limit]
    return FeedOut(items=await _serialize_page(db, me, posts), next_cursor=next_cursor)


@router.get("/interests", response_model=FeedOut)
async def interests_feed(
    cursor: Optional[str] = Query(None),
    limit: int = Query(12, ge=1, le=40),
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """
    «برای تو» — کاوشِ شخصی‌سازی‌شده بر پایهٔ علاقه:
    از هشتگِ پست‌هایی که لایک/ذخیره کرده‌ام سیگنالِ علاقه می‌سازد و
    پست‌های تازهٔ همان موضوع‌ها (به‌جز پست‌های خودم و آنچه دیده‌ام) را می‌آورد.
    اگر سیگنالی نبود، به کاوشِ عمومیِ جدید برمی‌گردد.
    """
    liked = select(PostLike.post_id).where(PostLike.user_id == me.id)
    saved = select(PostSave.post_id).where(PostSave.user_id == me.id)
    engaged = {row[0] for row in (await db.execute(liked)).all()}
    engaged |= {row[0] for row in (await db.execute(saved)).all()}

    tags: List[str] = []
    if engaged:
        rt = await db.execute(
            select(distinct(PostHashtag.tag)).where(PostHashtag.post_id.in_(list(engaged)))
        )
        tags = [x[0] for x in rt.all()]

    if tags:
        tag_posts = select(PostHashtag.post_id).where(PostHashtag.tag.in_(tags))
        base = select(Post).where(and_(
            Post.id.in_(tag_posts),
            Post.author_id != me.id,
            Post.id.notin_(list(engaged)) if engaged else True,
        ))
    else:
        # fallback: کاوشِ عمومی
        base = select(Post).where(Post.author_id != me.id)

    q = _paginate(base, cursor, limit)
    posts = (await db.execute(q)).scalars().all()
    next_cursor = None
    if len(posts) > limit:
        next_cursor = posts[limit - 1].created_at.isoformat()
        posts = posts[:limit]
    return FeedOut(items=await _serialize_page(db, me, posts), next_cursor=next_cursor)


# ── Moments — پست‌های دارای موقعیت روی کره ────────────────────
@router.get("/moments", response_model=List[PostOut])
async def moments(
    min_lat: Optional[float] = Query(None, ge=-90, le=90),
    max_lat: Optional[float] = Query(None, ge=-90, le=90),
    min_lng: Optional[float] = Query(None, ge=-180, le=180),
    max_lng: Optional[float] = Query(None, ge=-180, le=180),
    limit: int = Query(200, ge=1, le=500),
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """
    «لحظه‌ها» — پست‌های دارای موقعیت (lat/lng) برای نمایش روی کره.
    اگر bounding-box داده شود فیلترِ محدوده اعمال می‌شود، وگرنه جدیدترین‌های دارای موقعیت.
    """
    base = select(Post).where(and_(Post.lat.isnot(None), Post.lng.isnot(None)))
    if None not in (min_lat, max_lat, min_lng, max_lng):
        base = base.where(and_(
            Post.lat >= min_lat, Post.lat <= max_lat,
            Post.lng >= min_lng, Post.lng <= max_lng,
        ))
    q = base.order_by(Post.created_at.desc()).limit(limit)
    posts = (await db.execute(q)).scalars().all()
    return await _serialize_page(db, me, posts)


@router.get("/{post_id}", response_model=PostOut)
async def get_post(
    post_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    try:
        pid = _uuid.UUID(post_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="پست پیدا نشد")
    p = await db.get(Post, pid)
    if not p:
        raise HTTPException(status_code=404, detail="پست پیدا نشد")
    author = await db.get(User, p.author_id)
    liked, saved = await _flags(db, me.id, [p.id])
    return _to_out(p, author, me.id, liked, saved)


@router.post("/{post_id}/like", response_model=LikeOut)
async def toggle_like(
    post_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    try:
        pid = _uuid.UUID(post_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="پست پیدا نشد")
    p = await db.get(Post, pid)
    if not p:
        raise HTTPException(status_code=404, detail="پست پیدا نشد")
    ex = await db.execute(select(PostLike.id).where(and_(PostLike.post_id == pid, PostLike.user_id == me.id)))
    row = ex.scalar_one_or_none()
    if row is None:
        db.add(PostLike(post_id=pid, user_id=me.id))
        p.like_count = (p.like_count or 0) + 1
        liked = True
    else:
        await db.execute(sa_delete(PostLike).where(PostLike.id == row))
        p.like_count = max(0, (p.like_count or 0) - 1)
        liked = False
    await db.commit()
    return LikeOut(liked=liked, like_count=(p.like_count or 0))


@router.post("/{post_id}/save", response_model=SaveOut)
async def toggle_save(
    post_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    try:
        pid = _uuid.UUID(post_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="پست پیدا نشد")
    p = await db.get(Post, pid)
    if not p:
        raise HTTPException(status_code=404, detail="پست پیدا نشد")
    ex = await db.execute(select(PostSave.id).where(and_(PostSave.post_id == pid, PostSave.user_id == me.id)))
    row = ex.scalar_one_or_none()
    if row is None:
        db.add(PostSave(post_id=pid, user_id=me.id))
        p.save_count = (p.save_count or 0) + 1
        saved = True
    else:
        await db.execute(sa_delete(PostSave).where(PostSave.id == row))
        p.save_count = max(0, (p.save_count or 0) - 1)
        saved = False
    await db.commit()
    return SaveOut(saved=saved)


@router.get("/{post_id}/comments", response_model=List[CommentOut])
async def list_comments(
    post_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    try:
        pid = _uuid.UUID(post_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="پست پیدا نشد")
    q = (
        select(PostComment, User).join(User, User.id == PostComment.author_id)
        .where(PostComment.post_id == pid).order_by(PostComment.created_at.desc())
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


@router.post("/{post_id}/comments", response_model=CommentOut, status_code=status.HTTP_201_CREATED)
async def add_comment(
    post_id: str,
    body: str = Form(...),
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    try:
        pid = _uuid.UUID(post_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="پست پیدا نشد")
    p = await db.get(Post, pid)
    if not p:
        raise HTTPException(status_code=404, detail="پست پیدا نشد")
    text = (body or "").strip()[:1000]
    if not text:
        raise HTTPException(status_code=400, detail="متنِ کامنت خالی است")
    c = PostComment(post_id=pid, author_id=me.id, body=text)
    db.add(c)
    p.comment_count = (p.comment_count or 0) + 1
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
    try:
        cid = _uuid.UUID(comment_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="کامنت پیدا نشد")
    c = await db.get(PostComment, cid)
    if not c or c.author_id != me.id:
        raise HTTPException(status_code=404, detail="کامنت پیدا نشد")
    p = await db.get(Post, c.post_id)
    await db.delete(c)
    if p:
        p.comment_count = max(0, (p.comment_count or 0) - 1)
    await db.commit()
    return


@router.delete("/{post_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_post(
    post_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    try:
        pid = _uuid.UUID(post_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="پست پیدا نشد")
    p = await db.get(Post, pid)
    if not p or p.author_id != me.id:
        raise HTTPException(status_code=404, detail="پست پیدا نشد")
    await db.delete(p)
    await db.commit()
    return

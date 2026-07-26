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

from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File, Form, Body
from pydantic import BaseModel
from sqlalchemy import select, func, and_
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.models.social import Follow
from app.models.stories import Story, StoryView, ContactCircle, StoryHighlight, StoryHighlightItem

router = APIRouter(prefix="/stories", tags=["Stories"])

# ── مخاطبِ داستان ─────────────────────────────────────────────
# public=همه، followers=دنبال‌کنندگانِ من، colleagues/family/friends=حلقه‌های دستی
AUDIENCES = ("public", "followers", "colleagues", "family", "friends")
CIRCLE_AUDIENCES = ("colleagues", "family", "friends")


def _norm_audience(a: Optional[str]) -> Optional[str]:
    a = (a or "").strip().lower()
    return a if a in AUDIENCES else None

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
    audience: str = "public"
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
    """کسانی که «من» دنبالشان می‌کنم (برای مخاطبِ followers)."""
    r = await db.execute(select(Follow.following_id).where(Follow.follower_id == me_id))
    return {row[0] for row in r.all()}


async def _my_circle_memberships(db: AsyncSession, me_id) -> set:
    """مجموعهٔ (owner_id, circle) هایی که «من» عضوِ آن‌ها هستم."""
    r = await db.execute(
        select(ContactCircle.owner_id, ContactCircle.circle).where(ContactCircle.member_id == me_id)
    )
    return {(row[0], row[1]) for row in r.all()}


def _can_view(author_id, audience: str, me_id, i_follow: set, my_memberships: set) -> bool:
    """آیا «من» می‌توانم داستانی از author با این مخاطب را ببینم؟"""
    if author_id == me_id:
        return True
    aud = audience or "public"
    if aud == "public":
        return True
    if aud == "followers":
        return author_id in i_follow  # من نویسنده را دنبال می‌کنم
    if aud in CIRCLE_AUDIENCES:
        return (author_id, aud) in my_memberships
    return False


# ── Endpoints ────────────────────────────────────────────────
@router.post("", response_model=StoryOut, status_code=status.HTTP_201_CREATED)
async def create_story(
    file: UploadFile = File(...),
    caption: Optional[str] = Form(None),
    audience: Optional[str] = Form(None),
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """آپلودِ یک داستانِ جدید (عکس یا ویدیو) با انقضای ۲۴ساعته و مخاطبِ دلخواه."""
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

    # مخاطب: از فرم، وگرنه پیش‌فرضِ ذخیره‌شدهٔ کاربر، وگرنه public
    aud = _norm_audience(audience) or _norm_audience((me.metadata_ or {}).get("story_audience")) or "public"

    s = Story(
        author_id=me.id, media_url=media_url, media_type=media_type,
        caption=(caption or "").strip()[:500] or None, audience=aud,
    )
    db.add(s)
    await db.commit()
    await db.refresh(s)
    return StoryOut(
        id=str(s.id), author_earth_id=me.earth_id, author_name=_name(me),
        author_avatar=me.avatar_url, media_url=s.media_url, media_type=s.media_type,
        caption=s.caption, audience=s.audience, view_count=0, viewed_by_me=False, is_mine=True,
        created_at=s.created_at,
    )


@router.get("/feed", response_model=List[RingOut])
async def stories_feed(
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """نوارِ داستان‌ها: داستان‌های فعالی که «من» مجازِ دیدنشان هستم.

    مخاطبِ هر داستان (public/followers/colleagues/family/friends) بررسی می‌شود؛
    عمومی برای همه، followers برای دنبال‌کنندگان، و حلقه‌ها برای اعضای همان حلقه.
    """
    now = _now()
    q = (
        select(Story.id, Story.author_id, Story.created_at, Story.audience)
        .where(Story.expires_at > now)
    )
    r = await db.execute(q)
    all_rows = r.all()
    if not all_rows:
        return []

    i_follow = await _my_following_ids(db, me.id)
    my_memberships = await _my_circle_memberships(db, me.id)
    rows = [row for row in all_rows if _can_view(row[1], row[3], me.id, i_follow, my_memberships)]
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
    for sid, aid, created, _aud in rows:
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

    is_me = author.id == me.id
    if not is_me:
        # فقط داستان‌هایی که «من» مجازِ دیدنشان هستم
        i_follow = await _my_following_ids(db, me.id)
        my_memberships = await _my_circle_memberships(db, me.id)
        stories = [s for s in stories if _can_view(author.id, s.audience, me.id, i_follow, my_memberships)]
        if not stories:
            return []

    sids = [s.id for s in stories]
    rv = await db.execute(
        select(StoryView.story_id).where(
            and_(StoryView.viewer_id == me.id, StoryView.story_id.in_(sids))
        )
    )
    seen = {row[0] for row in rv.all()}

    return [
        StoryOut(
            id=str(s.id), author_earth_id=author.earth_id, author_name=_name(author),
            author_avatar=author.avatar_url, media_url=s.media_url, media_type=s.media_type,
            caption=s.caption, audience=s.audience, view_count=(s.view_count or 0),
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


# ── تنظیماتِ مخاطبِ پیش‌فرض ────────────────────────────────────
class StorySettingsOut(BaseModel):
    default_audience: str = "public"
    is_set: bool = False  # آیا کاربر قبلاً مخاطبِ پیش‌فرض را ذخیره کرده؟


class StorySettingsIn(BaseModel):
    default_audience: str


@router.get("/settings", response_model=StorySettingsOut)
async def get_story_settings(me: User = Depends(get_current_user)):
    """مخاطبِ پیش‌فرضِ داستان‌های من."""
    raw = (me.metadata_ or {}).get("story_audience")
    aud = _norm_audience(raw)
    return StorySettingsOut(default_audience=aud or "public", is_set=aud is not None)


@router.put("/settings", response_model=StorySettingsOut)
async def set_story_settings(
    body: StorySettingsIn,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """تنظیمِ مخاطبِ پیش‌فرضِ داستان (در متادیتای کاربر)."""
    aud = _norm_audience(body.default_audience)
    if not aud:
        raise HTTPException(status_code=422, detail="مخاطبِ نامعتبر")
    md = dict(me.metadata_ or {})
    md["story_audience"] = aud
    me.metadata_ = md  # بازتخصیص برای تشخیصِ تغییر توسط SQLAlchemy
    await db.commit()
    return StorySettingsOut(default_audience=aud, is_set=True)


# ── مدیریتِ حلقه‌های مخاطب (همکار/خانواده/دوست) ─────────────────
class CircleMember(BaseModel):
    earth_id: str
    name: str
    avatar_url: Optional[str] = None


class CirclesOut(BaseModel):
    colleagues: List[CircleMember] = []
    family: List[CircleMember] = []
    friends: List[CircleMember] = []


class CircleAddIn(BaseModel):
    earth_id: str


@router.get("/circles", response_model=CirclesOut)
async def list_circles(
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """اعضای حلقه‌های مخاطبِ من."""
    q = (
        select(User, ContactCircle.circle)
        .join(ContactCircle, ContactCircle.member_id == User.id)
        .where(ContactCircle.owner_id == me.id)
        .order_by(ContactCircle.created_at.desc())
    )
    r = await db.execute(q)
    out = CirclesOut()
    for u, circle in r.all():
        if circle in CIRCLE_AUDIENCES:
            getattr(out, circle).append(
                CircleMember(earth_id=u.earth_id, name=_name(u), avatar_url=u.avatar_url)
            )
    return out


@router.post("/circles/{circle}", response_model=CircleMember, status_code=status.HTTP_201_CREATED)
async def add_to_circle(
    circle: str,
    body: CircleAddIn,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """افزودنِ یک مخاطب (با earth_id) به یکی از حلقه‌ها."""
    if circle not in CIRCLE_AUDIENCES:
        raise HTTPException(status_code=404, detail="حلقهٔ نامعتبر")
    eid = (body.earth_id or "").strip().upper()
    ru = await db.execute(select(User).where(User.earth_id == eid))
    member = ru.scalar_one_or_none()
    if not member:
        raise HTTPException(status_code=404, detail="کاربر پیدا نشد")
    if member.id == me.id:
        raise HTTPException(status_code=400, detail="خودت را نمی‌توانی اضافه کنی")

    exists = await db.execute(
        select(ContactCircle.id).where(and_(
            ContactCircle.owner_id == me.id,
            ContactCircle.member_id == member.id,
            ContactCircle.circle == circle,
        ))
    )
    if exists.scalar_one_or_none() is None:
        db.add(ContactCircle(owner_id=me.id, member_id=member.id, circle=circle))
        await db.commit()
    return CircleMember(earth_id=member.earth_id, name=_name(member), avatar_url=member.avatar_url)


@router.delete("/circles/{circle}/{earth_id}", status_code=status.HTTP_204_NO_CONTENT)
async def remove_from_circle(
    circle: str,
    earth_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """حذفِ یک مخاطب از یک حلقه."""
    if circle not in CIRCLE_AUDIENCES:
        raise HTTPException(status_code=404, detail="حلقهٔ نامعتبر")
    ru = await db.execute(select(User).where(User.earth_id == earth_id.strip().upper()))
    member = ru.scalar_one_or_none()
    if not member:
        raise HTTPException(status_code=404, detail="کاربر پیدا نشد")
    rc = await db.execute(
        select(ContactCircle).where(and_(
            ContactCircle.owner_id == me.id,
            ContactCircle.member_id == member.id,
            ContactCircle.circle == circle,
        ))
    )
    row = rc.scalar_one_or_none()
    if row is not None:
        await db.delete(row)
        await db.commit()
    return


# ═══════════════════════════════════════════════════════════════
# Highlights — مجموعهٔ ماندگارِ داستان‌ها روی پروفایل
# ═══════════════════════════════════════════════════════════════
class HighlightOut(BaseModel):
    id: str
    title: str
    cover_url: Optional[str] = None
    item_count: int = 0
    is_mine: bool = False
    updated_at: datetime


class HighlightItemOut(BaseModel):
    id: str
    story_id: Optional[str] = None
    media_url: str
    media_type: str
    caption: Optional[str] = None
    sort_order: int = 0


class HighlightDetailOut(BaseModel):
    id: str
    title: str
    cover_url: Optional[str] = None
    is_mine: bool = False
    owner_earth_id: str
    owner_name: str
    items: List[HighlightItemOut]


class HighlightCreateIn(BaseModel):
    title: str
    story_ids: List[str] = []
    cover_url: Optional[str] = None


class HighlightItemsIn(BaseModel):
    story_ids: List[str]


class HighlightUpdateIn(BaseModel):
    title: Optional[str] = None
    cover_url: Optional[str] = None


def _uuids(ids: List[str]) -> list:
    out = []
    for s in ids or []:
        try:
            out.append(_uuid.UUID(str(s)))
        except (ValueError, AttributeError, TypeError):
            continue
    return out


async def _load_my_stories(db: AsyncSession, me_id, ids: List[str]) -> list:
    """داستان‌های متعلق به «من» با idهای داده‌شده (نادیده‌گرفتنِ انقضا)، به ترتیبِ ورودی."""
    uids = _uuids(ids)
    if not uids:
        return []
    r = await db.execute(
        select(Story).where(and_(Story.id.in_(uids), Story.author_id == me_id))
    )
    by_id = {s.id: s for s in r.scalars().all()}
    ordered = []
    for u in uids:
        s = by_id.get(u)
        if s is not None and s not in ordered:
            ordered.append(s)
    return ordered


def _pick_cover(items: List[StoryHighlightItem], explicit: Optional[str]) -> Optional[str]:
    if explicit:
        return explicit
    for it in items:
        if it.media_type == "image":
            return it.media_url
    return items[0].media_url if items else None


@router.post("/highlights", response_model=HighlightOut, status_code=status.HTTP_201_CREATED)
async def create_highlight(
    body: HighlightCreateIn,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """ساختِ یک هایلایتِ جدید از داستان‌های خودم (اسنپ‌شاتِ مستقل از انقضا)."""
    title = (body.title or "").strip()[:60] or "هایلایت"
    stories = await _load_my_stories(db, me.id, body.story_ids)
    if not stories:
        raise HTTPException(status_code=400, detail="حداقل یک داستانِ معتبر انتخاب کن")

    hl = StoryHighlight(owner_id=me.id, title=title, item_count=0, updated_at=_now())
    db.add(hl)
    await db.flush()  # برای گرفتنِ hl.id

    items: List[StoryHighlightItem] = []
    for i, s in enumerate(stories):
        it = StoryHighlightItem(
            highlight_id=hl.id, story_id=s.id, media_url=s.media_url,
            media_type=s.media_type, caption=s.caption, sort_order=i,
            source_created_at=s.created_at,
        )
        db.add(it)
        items.append(it)

    hl.cover_url = _pick_cover(items, body.cover_url)
    hl.item_count = len(items)
    await db.commit()
    await db.refresh(hl)
    return HighlightOut(
        id=str(hl.id), title=hl.title, cover_url=hl.cover_url,
        item_count=hl.item_count, is_mine=True, updated_at=hl.updated_at,
    )


@router.get("/highlights/user/{earth_id}", response_model=List[HighlightOut])
async def list_highlights(
    earth_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """هایلایت‌های یک کاربر (روی پروفایل — برای همه قابل‌مشاهده)."""
    ru = await db.execute(select(User).where(User.earth_id == earth_id.strip().upper()))
    owner = ru.scalar_one_or_none()
    if not owner:
        raise HTTPException(status_code=404, detail="کاربر پیدا نشد")
    r = await db.execute(
        select(StoryHighlight)
        .where(StoryHighlight.owner_id == owner.id)
        .order_by(StoryHighlight.updated_at.desc())
    )
    rows = r.scalars().all()
    return [
        HighlightOut(
            id=str(h.id), title=h.title, cover_url=h.cover_url,
            item_count=h.item_count, is_mine=(owner.id == me.id), updated_at=h.updated_at,
        )
        for h in rows
    ]


@router.get("/highlights/{highlight_id}", response_model=HighlightDetailOut)
async def get_highlight(
    highlight_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """محتوای یک هایلایت (آیتم‌ها به‌ترتیب)."""
    try:
        hid = _uuid.UUID(highlight_id)
    except (ValueError, AttributeError, TypeError):
        raise HTTPException(status_code=404, detail="هایلایت پیدا نشد")
    hl = await db.get(StoryHighlight, hid)
    if not hl:
        raise HTTPException(status_code=404, detail="هایلایت پیدا نشد")
    owner = await db.get(User, hl.owner_id)
    r = await db.execute(
        select(StoryHighlightItem)
        .where(StoryHighlightItem.highlight_id == hl.id)
        .order_by(StoryHighlightItem.sort_order.asc())
    )
    items = r.scalars().all()
    return HighlightDetailOut(
        id=str(hl.id), title=hl.title, cover_url=hl.cover_url,
        is_mine=(hl.owner_id == me.id),
        owner_earth_id=owner.earth_id if owner else "",
        owner_name=_name(owner) if owner else "",
        items=[
            HighlightItemOut(
                id=str(it.id), story_id=str(it.story_id) if it.story_id else None,
                media_url=it.media_url, media_type=it.media_type,
                caption=it.caption, sort_order=it.sort_order,
            )
            for it in items
        ],
    )


async def _owned_highlight(db: AsyncSession, highlight_id: str, me_id) -> StoryHighlight:
    try:
        hid = _uuid.UUID(highlight_id)
    except (ValueError, AttributeError, TypeError):
        raise HTTPException(status_code=404, detail="هایلایت پیدا نشد")
    hl = await db.get(StoryHighlight, hid)
    if not hl:
        raise HTTPException(status_code=404, detail="هایلایت پیدا نشد")
    if hl.owner_id != me_id:
        raise HTTPException(status_code=403, detail="این هایلایت متعلق به شما نیست")
    return hl


@router.patch("/highlights/{highlight_id}", response_model=HighlightOut)
async def update_highlight(
    highlight_id: str,
    body: HighlightUpdateIn,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """تغییرِ عنوان یا کاورِ هایلایت (فقط مالک)."""
    hl = await _owned_highlight(db, highlight_id, me.id)
    if body.title is not None:
        t = body.title.strip()[:60]
        if t:
            hl.title = t
    if body.cover_url is not None:
        hl.cover_url = body.cover_url.strip() or hl.cover_url
    hl.updated_at = _now()
    await db.commit()
    await db.refresh(hl)
    return HighlightOut(
        id=str(hl.id), title=hl.title, cover_url=hl.cover_url,
        item_count=hl.item_count, is_mine=True, updated_at=hl.updated_at,
    )


@router.post("/highlights/{highlight_id}/items", response_model=HighlightDetailOut)
async def add_highlight_items(
    highlight_id: str,
    body: HighlightItemsIn,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """افزودنِ داستان‌های بیشتر به یک هایلایت (فقط مالک)."""
    hl = await _owned_highlight(db, highlight_id, me.id)
    stories = await _load_my_stories(db, me.id, body.story_ids)
    if not stories:
        raise HTTPException(status_code=400, detail="حداقل یک داستانِ معتبر انتخاب کن")
    rmax = await db.execute(
        select(func.max(StoryHighlightItem.sort_order)).where(StoryHighlightItem.highlight_id == hl.id)
    )
    start = (rmax.scalar() or -1) + 1
    for i, s in enumerate(stories):
        db.add(StoryHighlightItem(
            highlight_id=hl.id, story_id=s.id, media_url=s.media_url,
            media_type=s.media_type, caption=s.caption, sort_order=start + i,
            source_created_at=s.created_at,
        ))
    hl.item_count = (hl.item_count or 0) + len(stories)
    if not hl.cover_url:
        hl.cover_url = stories[0].media_url
    hl.updated_at = _now()
    await db.commit()
    return await get_highlight(highlight_id, db, me)


@router.delete("/highlights/{highlight_id}/items/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
async def remove_highlight_item(
    highlight_id: str,
    item_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """حذفِ یک آیتم از هایلایت (فقط مالک)."""
    hl = await _owned_highlight(db, highlight_id, me.id)
    try:
        iid = _uuid.UUID(item_id)
    except (ValueError, AttributeError, TypeError):
        raise HTTPException(status_code=404, detail="آیتم پیدا نشد")
    it = await db.get(StoryHighlightItem, iid)
    if it is None or it.highlight_id != hl.id:
        raise HTTPException(status_code=404, detail="آیتم پیدا نشد")
    was_cover = (hl.cover_url == it.media_url)
    await db.delete(it)
    await db.flush()
    rest = (await db.execute(
        select(StoryHighlightItem)
        .where(StoryHighlightItem.highlight_id == hl.id)
        .order_by(StoryHighlightItem.sort_order.asc())
    )).scalars().all()
    hl.item_count = len(rest)
    if was_cover:
        hl.cover_url = _pick_cover(rest, None)
    hl.updated_at = _now()
    if not rest:
        await db.delete(hl)  # هایلایتِ خالی حذف می‌شود
    await db.commit()
    return


@router.delete("/highlights/{highlight_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_highlight(
    highlight_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """حذفِ کاملِ یک هایلایت (فقط مالک)."""
    hl = await _owned_highlight(db, highlight_id, me.id)
    await db.delete(hl)
    await db.commit()
    return

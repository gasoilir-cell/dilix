"""روتر داستان — /v1/stories/...

برگرفته از پیش‌نویسِ `_stories_router.py`. تفاوت‌ها با پیش‌نویس (برای هم‌راستایی با Core):
  • شناسه‌ی کاربر = earth_id (بدونِ JOIN با جدولِ users؛ enrichment نام/آواتار حذف شد).
  • مخاطبِ followers حذف شد (نیازمندِ گرافِ فالوِ ماژولِ Social)؛ فقط public و حلقه‌ها.
  • ساختِ داستان با media_url در بدنه‌ی JSON (به‌جای آپلودِ فایل).
"""
from __future__ import annotations

import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import and_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.modules.auth.deps import CurrentUser, get_current_user
from app.modules.stories.models import (
    AUDIENCES,
    CIRCLE_AUDIENCES,
    ContactCircle,
    Story,
    StoryView,
)
from app.modules.stories.schemas import (
    CircleAddIn,
    CircleMember,
    CirclesOut,
    RingOut,
    StoryCreate,
    StoryOut,
    ViewerOut,
)

router = APIRouter(prefix="/v1/stories", tags=["stories"])


def _now() -> datetime:
    return datetime.now(timezone.utc)


async def _my_circle_memberships(db: AsyncSession, me: uuid.UUID) -> set:
    r = await db.execute(
        select(ContactCircle.owner_earth_id, ContactCircle.circle).where(
            ContactCircle.member_earth_id == me
        )
    )
    return {(row[0], row[1]) for row in r.all()}


def _can_view(author: uuid.UUID, audience: str, me: uuid.UUID, memberships: set) -> bool:
    if author == me:
        return True
    aud = audience or "public"
    if aud == "public":
        return True
    if aud in CIRCLE_AUDIENCES:
        return (author, aud) in memberships
    return False


@router.post("", response_model=StoryOut, status_code=status.HTTP_201_CREATED)
async def create_story(
    body: StoryCreate,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> StoryOut:
    aud = body.audience if body.audience in AUDIENCES else "public"
    s = Story(
        author_earth_id=user.earth_id,
        media_url=body.media_url.strip(),
        media_type=body.media_type,
        caption=(body.caption or "").strip()[:500] or None,
        audience=aud,
    )
    db.add(s)
    await db.commit()
    await db.refresh(s)
    return StoryOut(
        id=s.id,
        author_earth_id=s.author_earth_id,
        media_url=s.media_url,
        media_type=s.media_type,
        caption=s.caption,
        audience=s.audience,
        view_count=0,
        viewed_by_me=False,
        is_mine=True,
        created_at=s.created_at,
    )


@router.get("/feed", response_model=list[RingOut])
async def stories_feed(
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> list[RingOut]:
    now = _now()
    rows = (
        await db.execute(
            select(Story.id, Story.author_earth_id, Story.created_at, Story.audience).where(
                Story.expires_at > now
            )
        )
    ).all()
    if not rows:
        return []

    memberships = await _my_circle_memberships(db, user.earth_id)
    visible = [r for r in rows if _can_view(r[1], r[3], user.earth_id, memberships)]
    if not visible:
        return []

    story_ids = [r[0] for r in visible]
    seen = {
        row[0]
        for row in (
            await db.execute(
                select(StoryView.story_id).where(
                    and_(
                        StoryView.viewer_earth_id == user.earth_id,
                        StoryView.story_id.in_(story_ids),
                    )
                )
            )
        ).all()
    }

    by_author: dict = {}
    for sid, aid, created, _aud in visible:
        g = by_author.setdefault(aid, {"count": 0, "latest": created, "unseen": False})
        g["count"] += 1
        if created > g["latest"]:
            g["latest"] = created
        if sid not in seen:
            g["unseen"] = True

    rings = [
        RingOut(
            author_earth_id=aid,
            story_count=g["count"],
            has_unseen=g["unseen"],
            is_me=(aid == user.earth_id),
            latest_at=g["latest"],
        )
        for aid, g in by_author.items()
    ]
    rings.sort(key=lambda x: (not x.is_me, not x.has_unseen, -x.latest_at.timestamp()))
    return rings


@router.get("/user/{earth_id}", response_model=list[StoryOut])
async def user_stories(
    earth_id: uuid.UUID,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> list[StoryOut]:
    now = _now()
    stories = (
        await db.execute(
            select(Story)
            .where(and_(Story.author_earth_id == earth_id, Story.expires_at > now))
            .order_by(Story.created_at.asc())
        )
    ).scalars().all()
    if not stories:
        return []

    is_me = earth_id == user.earth_id
    if not is_me:
        memberships = await _my_circle_memberships(db, user.earth_id)
        stories = [
            s for s in stories if _can_view(earth_id, s.audience, user.earth_id, memberships)
        ]
        if not stories:
            return []

    sids = [s.id for s in stories]
    seen = {
        row[0]
        for row in (
            await db.execute(
                select(StoryView.story_id).where(
                    and_(StoryView.viewer_earth_id == user.earth_id, StoryView.story_id.in_(sids))
                )
            )
        ).all()
    }
    return [
        StoryOut(
            id=s.id,
            author_earth_id=s.author_earth_id,
            media_url=s.media_url,
            media_type=s.media_type,
            caption=s.caption,
            audience=s.audience,
            view_count=(s.view_count or 0),
            viewed_by_me=(s.id in seen),
            is_mine=is_me,
            created_at=s.created_at,
        )
        for s in stories
    ]


@router.post("/{story_id}/view", status_code=status.HTTP_204_NO_CONTENT)
async def view_story(
    story_id: uuid.UUID,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> None:
    s = await db.get(Story, story_id)
    if not s:
        raise HTTPException(status_code=404, detail="داستان پیدا نشد")
    if s.author_earth_id == user.earth_id:
        return
    exists = await db.execute(
        select(StoryView.id).where(
            and_(StoryView.story_id == story_id, StoryView.viewer_earth_id == user.earth_id)
        )
    )
    if exists.scalar_one_or_none() is None:
        db.add(StoryView(story_id=story_id, viewer_earth_id=user.earth_id))
        s.view_count = (s.view_count or 0) + 1
        await db.commit()


@router.get("/{story_id}/viewers", response_model=list[ViewerOut])
async def story_viewers(
    story_id: uuid.UUID,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> list[ViewerOut]:
    s = await db.get(Story, story_id)
    if not s:
        raise HTTPException(status_code=404, detail="داستان پیدا نشد")
    if s.author_earth_id != user.earth_id:
        raise HTTPException(status_code=403, detail="فقط نویسنده می‌تواند بازدیدکنندگان را ببیند")
    rows = (
        await db.execute(
            select(StoryView.viewer_earth_id, StoryView.created_at)
            .where(StoryView.story_id == story_id)
            .order_by(StoryView.created_at.desc())
        )
    ).all()
    return [ViewerOut(viewer_earth_id=vid, viewed_at=vat) for (vid, vat) in rows]


@router.delete("/{story_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_story(
    story_id: uuid.UUID,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> None:
    s = await db.get(Story, story_id)
    if not s or s.author_earth_id != user.earth_id:
        raise HTTPException(status_code=404, detail="داستان پیدا نشد")
    await db.delete(s)
    await db.commit()


# ── مدیریتِ حلقه‌های مخاطب (همکار/خانواده/دوست) ─────────────────
@router.get("/circles", response_model=CirclesOut)
async def list_circles(
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> CirclesOut:
    rows = (
        await db.execute(
            select(ContactCircle.member_earth_id, ContactCircle.circle)
            .where(ContactCircle.owner_earth_id == user.earth_id)
            .order_by(ContactCircle.created_at.desc())
        )
    ).all()
    out = CirclesOut()
    for member_id, circle in rows:
        if circle in CIRCLE_AUDIENCES:
            getattr(out, circle).append(CircleMember(earth_id=member_id))
    return out


@router.post("/circles/{circle}", response_model=CircleMember, status_code=status.HTTP_201_CREATED)
async def add_to_circle(
    circle: str,
    body: CircleAddIn,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> CircleMember:
    if circle not in CIRCLE_AUDIENCES:
        raise HTTPException(status_code=404, detail="حلقهٔ نامعتبر")
    if body.earth_id == user.earth_id:
        raise HTTPException(status_code=400, detail="خودت را نمی‌توانی اضافه کنی")
    exists = await db.execute(
        select(ContactCircle.id).where(
            and_(
                ContactCircle.owner_earth_id == user.earth_id,
                ContactCircle.member_earth_id == body.earth_id,
                ContactCircle.circle == circle,
            )
        )
    )
    if exists.scalar_one_or_none() is None:
        db.add(
            ContactCircle(
                owner_earth_id=user.earth_id, member_earth_id=body.earth_id, circle=circle
            )
        )
        await db.commit()
    return CircleMember(earth_id=body.earth_id)


@router.delete("/circles/{circle}/{earth_id}", status_code=status.HTTP_204_NO_CONTENT)
async def remove_from_circle(
    circle: str,
    earth_id: uuid.UUID,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> None:
    if circle not in CIRCLE_AUDIENCES:
        raise HTTPException(status_code=404, detail="حلقهٔ نامعتبر")
    rc = await db.execute(
        select(ContactCircle).where(
            and_(
                ContactCircle.owner_earth_id == user.earth_id,
                ContactCircle.member_earth_id == earth_id,
                ContactCircle.circle == circle,
            )
        )
    )
    row = rc.scalar_one_or_none()
    if row is not None:
        await db.delete(row)
        await db.commit()

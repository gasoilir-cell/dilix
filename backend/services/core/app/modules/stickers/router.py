"""روتر استیکر — /v1/stickers/...

برگرفته از پیش‌نویسِ `_stickers_router.py`. تفاوت‌ها با پیش‌نویس (برای هم‌راستایی با Core):
  • شناسه‌ی کاربر = earth_id (بدونِ JOIN با جدولِ users؛ enrichment نام/آواتار حذف شد).
  • احراز هویت با `get_current_user` (CurrentUser) و session با `get_session`.
  • افزودنِ استیکر با media_url در بدنه‌ی JSON (به‌جای آپلودِ فایل).
"""
from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import delete as sa_delete
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.modules.auth.deps import CurrentUser, get_current_user
from app.modules.stickers.models import (
    InstalledPack,
    Sticker,
    StarredSticker,
    StickerPack,
)
from app.modules.stickers.schemas import (
    PackCreate,
    PackDetailOut,
    PackOut,
    PackUpdate,
    StickerCreate,
    StickerOut,
)

router = APIRouter(prefix="/v1/stickers", tags=["stickers"])


async def _starred_ids(db: AsyncSession, user_id: uuid.UUID, sticker_ids: list) -> set:
    if not sticker_ids:
        return set()
    rows = (
        await db.execute(
            select(StarredSticker.sticker_id).where(
                StarredSticker.user_earth_id == user_id,
                StarredSticker.sticker_id.in_(sticker_ids),
            )
        )
    ).scalars().all()
    return set(rows)


async def _installed_ids(db: AsyncSession, user_id: uuid.UUID, pack_ids: list) -> set:
    if not pack_ids:
        return set()
    rows = (
        await db.execute(
            select(InstalledPack.pack_id).where(
                InstalledPack.user_earth_id == user_id,
                InstalledPack.pack_id.in_(pack_ids),
            )
        )
    ).scalars().all()
    return set(rows)


def _pack_out(p: StickerPack, me: uuid.UUID, installed: set) -> PackOut:
    return PackOut(
        id=p.id,
        owner_earth_id=p.owner_earth_id,
        title=p.title,
        description=p.description,
        cover_url=p.cover_url,
        is_public=bool(p.is_public),
        is_animated=bool(p.is_animated),
        is_mine=(p.owner_earth_id == me),
        is_installed=(p.id in installed),
        install_count=p.install_count or 0,
        sticker_count=p.sticker_count or 0,
        created_at=p.created_at,
    )


def _sticker_out(s: Sticker, starred: set) -> StickerOut:
    return StickerOut(
        id=s.id,
        pack_id=s.pack_id,
        media_url=s.media_url,
        media_type=s.media_type,
        emoji_tag=s.emoji_tag,
        title=s.title,
        is_starred=(s.id in starred),
        created_at=s.created_at,
    )


# ── Pack CRUD ────────────────────────────────────────────────
@router.post("/packs", response_model=PackOut, status_code=status.HTTP_201_CREATED)
async def create_pack(
    body: PackCreate,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> PackOut:
    p = StickerPack(
        owner_earth_id=user.earth_id,
        title=body.title.strip(),
        description=(body.description or "").strip() or None,
        is_public=bool(body.is_public),
    )
    db.add(p)
    await db.commit()
    await db.refresh(p)
    return _pack_out(p, user.earth_id, set())


@router.get("/packs/mine", response_model=list[PackOut])
async def my_packs(
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> list[PackOut]:
    packs = (
        await db.execute(
            select(StickerPack)
            .where(StickerPack.owner_earth_id == user.earth_id)
            .order_by(StickerPack.updated_at.desc())
        )
    ).scalars().all()
    return [_pack_out(p, user.earth_id, set()) for p in packs]


@router.get("/packs/installed", response_model=list[PackOut])
async def installed_packs(
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> list[PackOut]:
    packs = (
        await db.execute(
            select(StickerPack)
            .join(InstalledPack, InstalledPack.pack_id == StickerPack.id)
            .where(InstalledPack.user_earth_id == user.earth_id)
            .order_by(InstalledPack.created_at.desc())
        )
    ).scalars().all()
    installed = {p.id for p in packs}
    return [_pack_out(p, user.earth_id, installed) for p in packs]


@router.get("/packs/public", response_model=list[PackOut])
async def public_packs(
    q: str | None = Query(default=None, max_length=120),
    limit: int = Query(default=40, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> list[PackOut]:
    stmt = select(StickerPack).where(
        StickerPack.is_public.is_(True),
        StickerPack.sticker_count > 0,
    )
    if q and q.strip():
        like = f"%{q.strip()}%"
        stmt = stmt.where(
            or_(StickerPack.title.ilike(like), StickerPack.description.ilike(like))
        )
    stmt = (
        stmt.order_by(StickerPack.install_count.desc(), StickerPack.updated_at.desc())
        .limit(limit)
        .offset(offset)
    )
    packs = (await db.execute(stmt)).scalars().all()
    installed = await _installed_ids(db, user.earth_id, [p.id for p in packs])
    return [_pack_out(p, user.earth_id, installed) for p in packs]


@router.get("/packs/{pack_id}", response_model=PackDetailOut)
async def pack_detail(
    pack_id: uuid.UUID,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> PackDetailOut:
    p = await db.get(StickerPack, pack_id)
    if not p:
        raise HTTPException(status_code=404, detail="بسته یافت نشد")
    if not p.is_public and p.owner_earth_id != user.earth_id:
        if not await _installed_ids(db, user.earth_id, [pack_id]):
            raise HTTPException(status_code=403, detail="این بسته خصوصی است")

    stickers = (
        await db.execute(
            select(Sticker).where(Sticker.pack_id == pack_id).order_by(Sticker.created_at.asc())
        )
    ).scalars().all()
    starred = await _starred_ids(db, user.earth_id, [s.id for s in stickers])
    installed = await _installed_ids(db, user.earth_id, [pack_id])
    base = _pack_out(p, user.earth_id, installed)
    return PackDetailOut(
        **base.model_dump(),
        stickers=[_sticker_out(s, starred) for s in stickers],
    )


@router.patch("/packs/{pack_id}", response_model=PackOut)
async def update_pack(
    pack_id: uuid.UUID,
    body: PackUpdate,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> PackOut:
    p = await db.get(StickerPack, pack_id)
    if not p or p.owner_earth_id != user.earth_id:
        raise HTTPException(status_code=404, detail="بسته یافت نشد")
    if body.title is not None:
        p.title = body.title.strip()
    if body.description is not None:
        p.description = body.description.strip() or None
    if body.is_public is not None:
        p.is_public = bool(body.is_public)
    await db.commit()
    await db.refresh(p)
    return _pack_out(p, user.earth_id, set())


@router.delete("/packs/{pack_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_pack(
    pack_id: uuid.UUID,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> None:
    p = await db.get(StickerPack, pack_id)
    if not p or p.owner_earth_id != user.earth_id:
        raise HTTPException(status_code=404, detail="بسته یافت نشد")
    await db.delete(p)
    await db.commit()


# ── Install / Uninstall ──────────────────────────────────────
@router.post("/packs/{pack_id}/install", status_code=status.HTTP_204_NO_CONTENT)
async def install_pack(
    pack_id: uuid.UUID,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> None:
    p = await db.get(StickerPack, pack_id)
    if not p or not p.is_public:
        raise HTTPException(status_code=404, detail="بسته‌ی عمومی یافت نشد")
    if not await _installed_ids(db, user.earth_id, [pack_id]):
        db.add(InstalledPack(user_earth_id=user.earth_id, pack_id=pack_id))
        p.install_count = (p.install_count or 0) + 1
        await db.commit()


@router.delete("/packs/{pack_id}/install", status_code=status.HTTP_204_NO_CONTENT)
async def uninstall_pack(
    pack_id: uuid.UUID,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> None:
    res = await db.execute(
        sa_delete(InstalledPack).where(
            InstalledPack.user_earth_id == user.earth_id,
            InstalledPack.pack_id == pack_id,
        )
    )
    if res.rowcount:
        p = await db.get(StickerPack, pack_id)
        if p and (p.install_count or 0) > 0:
            p.install_count -= 1
    await db.commit()


# ── Stickers ─────────────────────────────────────────────────
@router.post(
    "/packs/{pack_id}/stickers", response_model=StickerOut, status_code=status.HTTP_201_CREATED
)
async def add_sticker(
    pack_id: uuid.UUID,
    body: StickerCreate,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> StickerOut:
    p = await db.get(StickerPack, pack_id)
    if not p or p.owner_earth_id != user.earth_id:
        raise HTTPException(status_code=404, detail="بسته یافت نشد")
    s = Sticker(
        pack_id=pack_id,
        owner_earth_id=user.earth_id,
        media_url=body.media_url.strip(),
        media_type=body.media_type,
        emoji_tag=(body.emoji_tag or "").strip()[:32] or None,
        title=(body.title or "").strip()[:120] or None,
    )
    db.add(s)
    p.sticker_count = (p.sticker_count or 0) + 1
    if body.media_type in ("video", "voice"):
        p.is_animated = True
    if not p.cover_url:
        p.cover_url = s.media_url
    await db.commit()
    await db.refresh(s)
    return _sticker_out(s, set())


@router.delete("/{sticker_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_sticker(
    sticker_id: uuid.UUID,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> None:
    s = await db.get(Sticker, sticker_id)
    if not s or s.owner_earth_id != user.earth_id:
        raise HTTPException(status_code=404, detail="استیکر یافت نشد")
    p = await db.get(StickerPack, s.pack_id)
    await db.delete(s)
    if p and (p.sticker_count or 0) > 0:
        p.sticker_count -= 1
    await db.commit()


# ── Starred (quick access) ───────────────────────────────────
@router.get("/starred", response_model=list[StickerOut])
async def my_starred(
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> list[StickerOut]:
    rows = (
        await db.execute(
            select(Sticker)
            .join(StarredSticker, StarredSticker.sticker_id == Sticker.id)
            .where(StarredSticker.user_earth_id == user.earth_id)
            .order_by(StarredSticker.created_at.desc())
        )
    ).scalars().all()
    return [_sticker_out(s, {s.id for s in rows}) for s in rows]


@router.post("/{sticker_id}/star", status_code=status.HTTP_204_NO_CONTENT)
async def star_sticker(
    sticker_id: uuid.UUID,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> None:
    s = await db.get(Sticker, sticker_id)
    if not s:
        raise HTTPException(status_code=404, detail="استیکر یافت نشد")
    if not await _starred_ids(db, user.earth_id, [sticker_id]):
        db.add(StarredSticker(user_earth_id=user.earth_id, sticker_id=sticker_id))
        await db.commit()


@router.delete("/{sticker_id}/star", status_code=status.HTTP_204_NO_CONTENT)
async def unstar_sticker(
    sticker_id: uuid.UUID,
    user: CurrentUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_session),
) -> None:
    await db.execute(
        sa_delete(StarredSticker).where(
            StarredSticker.user_earth_id == user.earth_id,
            StarredSticker.sticker_id == sticker_id,
        )
    )
    await db.commit()

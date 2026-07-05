"""
Dilix — Sticker / Emoji Library Router

POST   /api/v1/stickers/packs                     ساخت بسته‌ی جدید
GET    /api/v1/stickers/packs/mine                بسته‌های من (مالک)
GET    /api/v1/stickers/packs/installed           بسته‌های نصب‌شده (کتابخانه‌ی من)
GET    /api/v1/stickers/packs/public              کاوش/جست‌وجوی بسته‌های عمومی
GET    /api/v1/stickers/packs/{id}                جزئیات بسته + استیکرها
PATCH  /api/v1/stickers/packs/{id}                ویرایش بسته (عنوان/عمومی)
DELETE /api/v1/stickers/packs/{id}                حذف بسته‌ی من
POST   /api/v1/stickers/packs/{id}/install        نصب بسته‌ی عمومی
DELETE /api/v1/stickers/packs/{id}/install        حذف نصب
POST   /api/v1/stickers/packs/{id}/stickers       افزودن استیکر (آپلود مدیا)
DELETE /api/v1/stickers/{id}                       حذف استیکرِ من
GET    /api/v1/stickers/starred                    استیکرهای ستاره‌دارِ من
POST   /api/v1/stickers/{id}/star                  ستاره‌دار کردن (toggle-safe)
DELETE /api/v1/stickers/{id}/star                  حذف ستاره
"""
import os
import uuid as _uuid
from datetime import datetime
from typing import Optional, List

from fastapi import APIRouter, Depends, HTTPException, status, Query, UploadFile, File, Form
from pydantic import BaseModel, Field
from sqlalchemy import select, func, delete as sa_delete, and_, or_
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.models.stickers import (
    StickerPack, Sticker, StarredSticker, InstalledPack,
)

router = APIRouter(prefix="/stickers", tags=["Stickers"])

# ── Media storage ────────────────────────────────────────────
STICKER_DIR = "/var/www/dilix-api/uploads/stickers"
STICKER_BASE_URL = "/uploads/stickers"
_IMAGE_TYPES = {"image/jpeg", "image/png", "image/webp", "image/gif"}
_VIDEO_TYPES = {"video/webm", "video/mp4", "video/ogg", "video/quicktime"}
_AUDIO_TYPES = {"audio/webm", "audio/ogg", "audio/mpeg", "audio/mp4", "audio/wav", "audio/aac"}
_MAX_STICKER_SIZE = 12 * 1024 * 1024  # 12 MB


def _classify(content_type: str) -> str:
    ct = (content_type or "").split(";")[0].strip().lower()
    if ct in _IMAGE_TYPES or ct.startswith("image/"):
        return "image"
    if ct in _VIDEO_TYPES or ct.startswith("video/"):
        return "video"
    if ct in _AUDIO_TYPES or ct.startswith("audio/"):
        return "voice"
    return "image"


def _ext_for(media_type: str, filename: str) -> str:
    ext = os.path.splitext(filename or "")[1].lower()
    if ext:
        return ext
    return {"image": ".png", "video": ".webm", "voice": ".webm"}.get(media_type, ".bin")


# ── Schemas ──────────────────────────────────────────────────
class PackCreate(BaseModel):
    title: str = Field(..., min_length=1, max_length=120)
    description: Optional[str] = Field(None, max_length=300)
    is_public: bool = False


class PackUpdate(BaseModel):
    title: Optional[str] = Field(None, min_length=1, max_length=120)
    description: Optional[str] = Field(None, max_length=300)
    is_public: Optional[bool] = None


class StickerOut(BaseModel):
    id: str
    pack_id: str
    media_url: str
    media_type: str
    emoji_tag: Optional[str] = None
    title: Optional[str] = None
    is_starred: bool = False
    created_at: datetime


class PackOut(BaseModel):
    id: str
    title: str
    description: Optional[str] = None
    cover_url: Optional[str] = None
    is_public: bool
    is_animated: bool
    is_mine: bool
    is_installed: bool
    install_count: int
    sticker_count: int
    owner_name: Optional[str] = None
    created_at: datetime


class PackDetailOut(PackOut):
    stickers: List[StickerOut] = []


# ── Helpers ──────────────────────────────────────────────────
async def _starred_ids(db: AsyncSession, user_id, sticker_ids: List) -> set:
    if not sticker_ids:
        return set()
    rows = (await db.execute(
        select(StarredSticker.sticker_id).where(
            StarredSticker.user_id == user_id,
            StarredSticker.sticker_id.in_(sticker_ids),
        )
    )).scalars().all()
    return set(rows)


async def _installed_ids(db: AsyncSession, user_id, pack_ids: List) -> set:
    if not pack_ids:
        return set()
    rows = (await db.execute(
        select(InstalledPack.pack_id).where(
            InstalledPack.user_id == user_id,
            InstalledPack.pack_id.in_(pack_ids),
        )
    )).scalars().all()
    return set(rows)


def _pack_out(p: StickerPack, me_id, installed: set, owner_name: Optional[str]) -> PackOut:
    return PackOut(
        id=str(p.id),
        title=p.title,
        description=p.description,
        cover_url=p.cover_url,
        is_public=bool(p.is_public),
        is_animated=bool(p.is_animated),
        is_mine=(p.owner_id == me_id),
        is_installed=(p.id in installed),
        install_count=p.install_count or 0,
        sticker_count=p.sticker_count or 0,
        owner_name=owner_name,
        created_at=p.created_at,
    )


async def _owner_names(db: AsyncSession, owner_ids: List) -> dict:
    if not owner_ids:
        return {}
    rows = (await db.execute(
        select(User.id, User.full_name, User.username, User.earth_id)
        .where(User.id.in_(list(set(owner_ids))))
    )).all()
    return {r[0]: (r[1] or r[2] or r[3]) for r in rows}


# ── Pack CRUD ────────────────────────────────────────────────
@router.post("/packs", response_model=PackOut, status_code=status.HTTP_201_CREATED)
async def create_pack(
    body: PackCreate,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    p = StickerPack(
        owner_id=me.id,
        title=body.title.strip(),
        description=(body.description or "").strip() or None,
        is_public=bool(body.is_public),
    )
    db.add(p)
    await db.commit()
    await db.refresh(p)
    return _pack_out(p, me.id, set(), me.full_name or me.username or me.earth_id)


@router.get("/packs/mine", response_model=List[PackOut])
async def my_packs(
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    packs = (await db.execute(
        select(StickerPack).where(StickerPack.owner_id == me.id)
        .order_by(StickerPack.updated_at.desc())
    )).scalars().all()
    name = me.full_name or me.username or me.earth_id
    return [_pack_out(p, me.id, set(), name) for p in packs]


@router.get("/packs/installed", response_model=List[PackOut])
async def installed_packs(
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    packs = (await db.execute(
        select(StickerPack)
        .join(InstalledPack, InstalledPack.pack_id == StickerPack.id)
        .where(InstalledPack.user_id == me.id)
        .order_by(InstalledPack.created_at.desc())
    )).scalars().all()
    pack_ids = [p.id for p in packs]
    installed = set(pack_ids)
    names = await _owner_names(db, [p.owner_id for p in packs])
    return [_pack_out(p, me.id, installed, names.get(p.owner_id)) for p in packs]


@router.get("/packs/public", response_model=List[PackOut])
async def public_packs(
    q: Optional[str] = Query(None, max_length=120),
    limit: int = Query(40, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """کاوش و جست‌وجوی کتابخانه‌های عمومی."""
    stmt = select(StickerPack).where(
        StickerPack.is_public.is_(True),
        StickerPack.sticker_count > 0,
    )
    if q and q.strip():
        like = f"%{q.strip()}%"
        stmt = stmt.where(or_(
            StickerPack.title.ilike(like),
            StickerPack.description.ilike(like),
        ))
    stmt = stmt.order_by(
        StickerPack.install_count.desc(), StickerPack.updated_at.desc()
    ).limit(limit).offset(offset)
    packs = (await db.execute(stmt)).scalars().all()
    pack_ids = [p.id for p in packs]
    installed = await _installed_ids(db, me.id, pack_ids)
    names = await _owner_names(db, [p.owner_id for p in packs])
    return [_pack_out(p, me.id, installed, names.get(p.owner_id)) for p in packs]


@router.get("/packs/{pack_id}", response_model=PackDetailOut)
async def pack_detail(
    pack_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    try:
        pid = _uuid.UUID(pack_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="بسته یافت نشد")
    p = await db.get(StickerPack, pid)
    if not p:
        raise HTTPException(status_code=404, detail="بسته یافت نشد")
    if not p.is_public and p.owner_id != me.id:
        # فقط اگر نصب کرده باشد اجازه‌ی دیدن دارد
        inst = await _installed_ids(db, me.id, [pid])
        if not inst:
            raise HTTPException(status_code=403, detail="این بسته خصوصی است")

    stickers = (await db.execute(
        select(Sticker).where(Sticker.pack_id == pid).order_by(Sticker.created_at.asc())
    )).scalars().all()
    starred = await _starred_ids(db, me.id, [s.id for s in stickers])
    installed = await _installed_ids(db, me.id, [pid])
    names = await _owner_names(db, [p.owner_id])

    base = _pack_out(p, me.id, installed, names.get(p.owner_id))
    return PackDetailOut(
        **base.model_dump(),
        stickers=[
            StickerOut(
                id=str(s.id), pack_id=str(s.pack_id), media_url=s.media_url,
                media_type=s.media_type, emoji_tag=s.emoji_tag, title=s.title,
                is_starred=(s.id in starred), created_at=s.created_at,
            ) for s in stickers
        ],
    )


@router.patch("/packs/{pack_id}", response_model=PackOut)
async def update_pack(
    pack_id: str,
    body: PackUpdate,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    p = await db.get(StickerPack, _uuid.UUID(pack_id))
    if not p or p.owner_id != me.id:
        raise HTTPException(status_code=404, detail="بسته یافت نشد")
    if body.title is not None:
        p.title = body.title.strip()
    if body.description is not None:
        p.description = body.description.strip() or None
    if body.is_public is not None:
        p.is_public = bool(body.is_public)
    await db.commit()
    await db.refresh(p)
    return _pack_out(p, me.id, set(), me.full_name or me.username or me.earth_id)


@router.delete("/packs/{pack_id}", status_code=status.HTTP_200_OK)
async def delete_pack(
    pack_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    p = await db.get(StickerPack, _uuid.UUID(pack_id))
    if not p or p.owner_id != me.id:
        raise HTTPException(status_code=404, detail="بسته یافت نشد")
    await db.delete(p)
    await db.commit()
    return {"ok": True}


# ── Install / Uninstall ──────────────────────────────────────
@router.post("/packs/{pack_id}/install", status_code=status.HTTP_200_OK)
async def install_pack(
    pack_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    pid = _uuid.UUID(pack_id)
    p = await db.get(StickerPack, pid)
    if not p or not p.is_public:
        raise HTTPException(status_code=404, detail="بسته‌ی عمومی یافت نشد")
    exists = await _installed_ids(db, me.id, [pid])
    if not exists:
        db.add(InstalledPack(user_id=me.id, pack_id=pid))
        p.install_count = (p.install_count or 0) + 1
        await db.commit()
    return {"ok": True, "installed": True}


@router.delete("/packs/{pack_id}/install", status_code=status.HTTP_200_OK)
async def uninstall_pack(
    pack_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    pid = _uuid.UUID(pack_id)
    res = await db.execute(
        sa_delete(InstalledPack).where(
            InstalledPack.user_id == me.id, InstalledPack.pack_id == pid
        )
    )
    if res.rowcount:
        p = await db.get(StickerPack, pid)
        if p and (p.install_count or 0) > 0:
            p.install_count -= 1
    await db.commit()
    return {"ok": True, "installed": False}


# ── Stickers ─────────────────────────────────────────────────
@router.post("/packs/{pack_id}/stickers", response_model=StickerOut,
             status_code=status.HTTP_201_CREATED)
async def add_sticker(
    pack_id: str,
    file: UploadFile = File(...),
    emoji_tag: Optional[str] = Form(None),
    title: Optional[str] = Form(None),
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    pid = _uuid.UUID(pack_id)
    p = await db.get(StickerPack, pid)
    if not p or p.owner_id != me.id:
        raise HTTPException(status_code=404, detail="بسته یافت نشد")

    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="فایل خالی است")
    if len(data) > _MAX_STICKER_SIZE:
        raise HTTPException(status_code=413, detail="حجم استیکر نباید بیشتر از ۱۲ مگابایت باشد")

    media_type = _classify(file.content_type or "")
    ext = _ext_for(media_type, file.filename or "")
    fname = f"{pid.hex[:8]}_{me.earth_id}_{_uuid.uuid4().hex[:8]}{ext}"
    os.makedirs(STICKER_DIR, exist_ok=True)
    with open(os.path.join(STICKER_DIR, fname), "wb") as f:
        f.write(data)
    media_url = f"{STICKER_BASE_URL}/{fname}"

    s = Sticker(
        pack_id=pid, owner_id=me.id, media_url=media_url, media_type=media_type,
        emoji_tag=(emoji_tag or "").strip()[:32] or None,
        title=(title or "").strip()[:120] or None,
    )
    db.add(s)
    # update pack denormalized fields
    p.sticker_count = (p.sticker_count or 0) + 1
    if media_type in ("video", "voice"):
        p.is_animated = True
    if not p.cover_url:
        p.cover_url = media_url
    await db.commit()
    await db.refresh(s)
    return StickerOut(
        id=str(s.id), pack_id=str(s.pack_id), media_url=s.media_url,
        media_type=s.media_type, emoji_tag=s.emoji_tag, title=s.title,
        is_starred=False, created_at=s.created_at,
    )


@router.delete("/{sticker_id}", status_code=status.HTTP_200_OK)
async def delete_sticker(
    sticker_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    s = await db.get(Sticker, _uuid.UUID(sticker_id))
    if not s or s.owner_id != me.id:
        raise HTTPException(status_code=404, detail="استیکر یافت نشد")
    p = await db.get(StickerPack, s.pack_id)
    await db.delete(s)
    if p and (p.sticker_count or 0) > 0:
        p.sticker_count -= 1
    await db.commit()
    return {"ok": True}


# ── Starred (quick access) ───────────────────────────────────
@router.get("/starred", response_model=List[StickerOut])
async def my_starred(
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    rows = (await db.execute(
        select(Sticker).join(StarredSticker, StarredSticker.sticker_id == Sticker.id)
        .where(StarredSticker.user_id == me.id)
        .order_by(StarredSticker.created_at.desc())
    )).scalars().all()
    return [
        StickerOut(
            id=str(s.id), pack_id=str(s.pack_id), media_url=s.media_url,
            media_type=s.media_type, emoji_tag=s.emoji_tag, title=s.title,
            is_starred=True, created_at=s.created_at,
        ) for s in rows
    ]


@router.get("/{sticker_id}", response_model=StickerOut)
async def get_sticker(
    sticker_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """جزئیات یک استیکر (برای کاوشِ کتابخانه‌ی متصل از داخلِ چت)."""
    try:
        sid = _uuid.UUID(sticker_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="استیکر یافت نشد")
    s = await db.get(Sticker, sid)
    if not s:
        raise HTTPException(status_code=404, detail="استیکر یافت نشد")
    starred = await _starred_ids(db, me.id, [sid])
    return StickerOut(
        id=str(s.id), pack_id=str(s.pack_id), media_url=s.media_url,
        media_type=s.media_type, emoji_tag=s.emoji_tag, title=s.title,
        is_starred=(sid in starred), created_at=s.created_at,
    )


@router.post("/{sticker_id}/star", status_code=status.HTTP_200_OK)
async def star_sticker(
    sticker_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    sid = _uuid.UUID(sticker_id)
    s = await db.get(Sticker, sid)
    if not s:
        raise HTTPException(status_code=404, detail="استیکر یافت نشد")
    exists = await _starred_ids(db, me.id, [sid])
    if not exists:
        db.add(StarredSticker(user_id=me.id, sticker_id=sid))
        await db.commit()
    return {"ok": True, "starred": True}


@router.delete("/{sticker_id}/star", status_code=status.HTTP_200_OK)
async def unstar_sticker(
    sticker_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    sid = _uuid.UUID(sticker_id)
    await db.execute(
        sa_delete(StarredSticker).where(
            StarredSticker.user_id == me.id, StarredSticker.sticker_id == sid
        )
    )
    await db.commit()
    return {"ok": True, "starred": False}

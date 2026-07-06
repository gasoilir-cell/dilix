"""
Dilix — Messages Router (Phase 1: full messenger)
GET    /api/v1/messages/rooms                          لیست مکالمات
POST   /api/v1/messages/rooms                          شروع مکالمه جدید (با earth_id)
GET    /api/v1/messages/rooms/{id}/messages            تاریخچه پیام‌ها
POST   /api/v1/messages/rooms/{id}/messages            ارسال پیام (+ reply_to_id)
POST   /api/v1/messages/rooms/{id}/media               ارسال عکس/صوت/فایل
POST   /api/v1/messages/rooms/{id}/location            ارسال موقعیت ثابت
POST   /api/v1/messages/rooms/{id}/live-location       شروع موقعیت زنده
PATCH  /api/v1/messages/live-location/{id}             به‌روزرسانی موقعیت زنده
POST   /api/v1/messages/live-location/{id}/stop        توقف موقعیت زنده
PATCH  /api/v1/messages/messages/{id}                  ویرایش پیام خودم
DELETE /api/v1/messages/messages/{id}                  حذف پیام خودم (برای همه)
POST   /api/v1/messages/messages/{id}/react            واکنش (toggle emoji)
DELETE /api/v1/messages/messages/{id}/react            حذف واکنش من
POST   /api/v1/messages/rooms/{id}/read                علامت‌گذاری خوانده‌شده
POST   /api/v1/messages/groups                         ساختِ گروه (name + member earth_ids)
GET    /api/v1/messages/rooms/{id}/members             اعضای گروه
POST   /api/v1/messages/rooms/{id}/members             افزودنِ عضو (earth_id)
DELETE /api/v1/messages/rooms/{id}/members/{earth_id}  حذف/ترکِ عضو
"""
import os
import json
import time
import uuid as _uuid
from datetime import datetime, timezone, timedelta
from typing import Optional, List, Dict

import httpx
from fastapi import APIRouter, Depends, HTTPException, status, Query, UploadFile, File, Form
from pydantic import BaseModel, Field
from sqlalchemy import select, and_, or_, func, delete as sa_delete
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.api.deps import get_current_user
from app.models.user import User
from app.models.messages import (
    MessageRoom, RoomMember, Message, MessageReaction, MessageTranslation,
    MessagePoll, PollVote, UserBlock,
)

router = APIRouter(prefix="/messages", tags=["Messages"])

_ALLOWED_EMOJI = {"❤️", "👍", "😂", "😮", "😢", "🙏", "🔥", "👏"}

# ── Media (photo / voice / file) ──────────────────────────────
CHAT_MEDIA_DIR = "/var/www/dilix-api/uploads/chat"
CHAT_MEDIA_BASE_URL = "/uploads/chat"
_IMAGE_TYPES = {"image/jpeg", "image/png", "image/webp", "image/gif"}
_AUDIO_TYPES = {
    "audio/webm", "audio/ogg", "audio/mpeg", "audio/mp4",
    "audio/wav", "audio/x-wav", "audio/aac", "audio/mp3",
}
_VIDEO_TYPES = {"video/webm", "video/mp4", "video/ogg", "video/quicktime"}
_MAX_MEDIA_SIZE = 25 * 1024 * 1024  # 25 MB


def _classify_media(content_type: str) -> str:
    # content-type ممکن است پارامتر داشته باشد (مثلاً audio/webm;codecs=opus) — پارامترها را جدا کن
    ct = (content_type or "").split(";")[0].strip().lower()
    if ct in _IMAGE_TYPES or ct.startswith("image/"):
        return "image"
    if ct in _AUDIO_TYPES or ct.startswith("audio/"):
        return "voice"
    if ct in _VIDEO_TYPES or ct.startswith("video/"):
        return "video"
    return "file"


def _human_size(n: int) -> str:
    if n < 1024:
        return f"{n} B"
    if n < 1024 * 1024:
        return f"{n / 1024:.0f} KB"
    return f"{n / (1024 * 1024):.1f} MB"


_MEDIA_LABEL = {
    "image": "🖼 عکس", "voice": "🎤 پیام صوتی", "file": "📎 فایل",
    "video": "🎬 ویدیو", "location": "📍 موقعیت مکانی", "live_location": "📡 موقعیت زنده",
    "call": "📞 تماس", "poll": "📊 نظرسنجی",
}


def _last_preview(msg) -> str:
    """متنِ پیش‌نمایشِ آخرین پیام برای لیستِ اتاق‌ها (رسانه → برچسب)"""
    if getattr(msg, "media_type", None):
        label = _MEDIA_LABEL.get(msg.media_type, "📎 فایل")
        cap = (msg.content or "").strip()
        return f"{label}: {cap[:60]}" if cap else label
    return (msg.content or "")[:80]


def _build_location(msg) -> Optional["LocationInfo"]:
    """LocationInfo از روی رکوردِ پیام (برای مسیرِ location/live_location)"""
    if msg.media_type not in ("location", "live_location") or msg.loc_lat is None:
        return None
    is_live = msg.media_type == "live_location"
    active = bool(
        is_live and msg.live_expires_at is not None
        and msg.live_expires_at > datetime.now(timezone.utc)
    )
    return LocationInfo(
        lat=msg.loc_lat,
        lng=msg.loc_lng,
        label=msg.loc_label,
        live=is_live,
        active=active,
        updated_at=msg.live_updated_at,
        expires_at=msg.live_expires_at,
    )


async def _build_polls(db: AsyncSession, msg_ids, me_id) -> Dict[str, "PollInfo"]:
    """PollInfo برای پیام‌های نظرسنجی (batch): شمارشِ رأیِ هر گزینه + رأیِ من + رأی‌دهندگانِ یکتا."""
    if not msg_ids:
        return {}
    polls = (await db.execute(
        select(MessagePoll).where(MessagePoll.message_id.in_(msg_ids))
    )).scalars().all()
    if not polls:
        return {}
    poll_by_id = {p.id: p for p in polls}
    votes = (await db.execute(
        select(PollVote).where(PollVote.poll_id.in_(list(poll_by_id.keys())))
    )).scalars().all()

    counts: Dict[str, Dict[int, int]] = {}       # poll_id -> {option_index: count}
    voters: Dict[str, set] = {}                   # poll_id -> set(user_id)
    mine: Dict[str, set] = {}                     # poll_id -> set(option_index) که من رأی داده‌ام
    for v in votes:
        pid = str(v.poll_id)
        counts.setdefault(pid, {})[v.option_index] = counts.setdefault(pid, {}).get(v.option_index, 0) + 1
        voters.setdefault(pid, set()).add(v.user_id)
        if v.user_id == me_id:
            mine.setdefault(pid, set()).add(v.option_index)

    result: Dict[str, PollInfo] = {}
    for p in polls:
        pid = str(p.id)
        try:
            opts = json.loads(p.options)
        except (ValueError, TypeError):
            opts = []
        c = counts.get(pid, {})
        my = mine.get(pid, set())
        result[str(p.message_id)] = PollInfo(
            id=pid,
            question=p.question,
            multiple=bool(p.multiple),
            total_votes=len(voters.get(pid, set())),
            options=[
                PollOption(text=str(t), votes=c.get(i, 0), voted=(i in my))
                for i, t in enumerate(opts)
            ],
        )
    return result


# ── Translation (Google free endpoint; reachable, no key, auto-detect) ──
_TRANSLATE_URL = "https://translate.googleapis.com/translate_a/single"
_SUPPORTED_LANGS = {
    "fa", "en", "ar", "tr", "ru", "zh-CN", "fr", "de", "es", "hi", "ur",
    "ps", "ku", "az", "it", "pt", "ja", "ko", "nl", "sv",
}
_LANG_ALIASES = {"zh": "zh-CN", "cn": "zh-CN", "farsi": "fa", "persian": "fa"}


def _norm_lang(code: str) -> str:
    c = (code or "").strip()
    low = c.lower()
    if low in _LANG_ALIASES:
        return _LANG_ALIASES[low]
    if c in _SUPPORTED_LANGS:
        return c
    if low in _SUPPORTED_LANGS:
        return low
    raise HTTPException(status_code=400, detail="زبانِ مقصد پشتیبانی نمی‌شود")


async def _google_translate(text: str, target: str):
    """ترجمه با endpointِ عمومیِ Google. برمی‌گرداند (translated_text, detected_lang)."""
    params = {
        "client": "gtx", "sl": "auto", "tl": target,
        "dt": "t", "q": text,
    }
    try:
        async with httpx.AsyncClient(timeout=12) as c:
            resp = await c.get(_TRANSLATE_URL, params=params)
    except httpx.HTTPError:
        raise HTTPException(status_code=503, detail="سرویسِ ترجمه در دسترس نیست")
    if resp.status_code != 200:
        raise HTTPException(status_code=503, detail="سرویسِ ترجمه پاسخ نداد")
    try:
        data = resp.json()
    except (json.JSONDecodeError, ValueError):
        raise HTTPException(status_code=502, detail="پاسخِ ترجمه نامعتبر بود")
    segments = data[0] or []
    translated = "".join(seg[0] for seg in segments if seg and seg[0])
    detected = None
    if len(data) > 2 and isinstance(data[2], str):
        detected = data[2]
    return translated, detected


# ── Schemas ───────────────────────────────────────────────────
class RoomOut(BaseModel):
    id: str
    type: str
    name: Optional[str]
    partner_name: Optional[str]
    partner_earth_id: Optional[str]
    partner_role: Optional[str]
    partner_avatar: Optional[str]
    last_message: Optional[str]
    last_message_at: Optional[datetime]
    unread_count: int
    member_count: int = 0
    is_admin: bool = False
    partner_online: bool = False
    partner_last_seen: Optional[datetime] = None
    is_muted: bool = False
    is_blocked: bool = False
    created_at: datetime


class ReplyPreview(BaseModel):
    id: str
    sender_name: Optional[str]
    content: str
    is_deleted: bool


class LocationInfo(BaseModel):
    lat: float
    lng: float
    label: Optional[str] = None
    live: bool = False             # is this a live (moving) share
    active: bool = False           # live and not yet expired/stopped
    updated_at: Optional[datetime] = None
    expires_at: Optional[datetime] = None


class PollOption(BaseModel):
    text: str
    votes: int = 0
    voted: bool = False            # آیا من به این گزینه رأی داده‌ام


class PollInfo(BaseModel):
    id: str
    question: str
    multiple: bool = False
    total_votes: int = 0           # تعدادِ رأی‌دهندگانِ یکتا
    options: List[PollOption]


class MessageOut(BaseModel):
    id: str
    sender_id: str
    sender_name: Optional[str]
    sender_earth_id: Optional[str]
    content: str
    is_mine: bool
    is_deleted: bool
    edited: bool
    reply_to: Optional[ReplyPreview]
    reactions: Dict[str, int]      # emoji -> count
    my_reaction: Optional[str]     # my emoji on this message
    is_read: bool                  # (mine only) seen by partner
    media_url: Optional[str] = None
    media_type: Optional[str] = None   # image | voice | file | location | live_location | poll
    media_name: Optional[str] = None
    media_meta: Optional[str] = None
    sticker_id: Optional[str] = None
    location: Optional[LocationInfo] = None
    poll: Optional[PollInfo] = None
    is_forwarded: bool = False
    forwarded_from: Optional[str] = None
    is_pinned: bool = False
    created_at: datetime


class StartRoomRequest(BaseModel):
    earth_id: str = Field(..., description="Earth ID طرف مقابل (DLX-XXXXXXXX)")


class SendMessageRequest(BaseModel):
    content: str = Field(..., min_length=1, max_length=4000)
    reply_to_id: Optional[str] = None


class EditMessageRequest(BaseModel):
    content: str = Field(..., min_length=1, max_length=4000)


class ReactRequest(BaseModel):
    emoji: str = Field(..., max_length=16)


class ForwardRequest(BaseModel):
    room_id: str = Field(..., description="اتاقِ مقصدِ بازارسال")
    anonymous: bool = Field(False, description="بی‌نام (بدونِ نامِ فرستندهٔ اصلی)")


class CreatePollRequest(BaseModel):
    question: str = Field(..., min_length=1, max_length=300)
    options: List[str] = Field(..., min_items=2, max_items=12)
    multiple: bool = Field(False, description="اجازهٔ انتخابِ چند گزینه")
    reply_to_id: Optional[str] = None


class VoteRequest(BaseModel):
    option_index: int = Field(..., ge=0, le=11)


class LocationRequest(BaseModel):
    lat: float = Field(..., ge=-90, le=90)
    lng: float = Field(..., ge=-180, le=180)
    label: Optional[str] = Field(None, max_length=200)
    reply_to_id: Optional[str] = None


class LiveLocationRequest(BaseModel):
    lat: float = Field(..., ge=-90, le=90)
    lng: float = Field(..., ge=-180, le=180)
    duration_minutes: int = Field(60, ge=1, le=1440)   # up to 24h
    reply_to_id: Optional[str] = None


class LiveLocationUpdate(BaseModel):
    lat: float = Field(..., ge=-90, le=90)
    lng: float = Field(..., ge=-180, le=180)


class CreateGroupRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=200)
    member_earth_ids: List[str] = Field(default_factory=list)


class AddMemberRequest(BaseModel):
    earth_id: str = Field(..., description="Earth ID عضوِ جدید")


class MemberOut(BaseModel):
    earth_id: str
    name: Optional[str]
    role: Optional[str]
    avatar_url: Optional[str]
    is_me: bool
    is_admin: bool


class TranslateMessageRequest(BaseModel):
    target_lang: str = Field(..., max_length=8)


class TranslateTextRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=4000)
    target_lang: str = Field(..., max_length=8)


class TranslationOut(BaseModel):
    message_id: Optional[str] = None
    target_lang: str
    detected_lang: Optional[str]
    original: str
    translated_text: str
    cached: bool = False


# ── Helpers ───────────────────────────────────────────────────
async def _get_or_create_direct_room(
    db: AsyncSession, user_a_id, user_b_id
) -> MessageRoom:
    """اتاق direct بین دو کاربر را پیدا یا می‌سازد"""
    q = select(RoomMember.room_id).where(RoomMember.user_id == user_a_id)
    r = await db.execute(q)
    rooms_a = set(str(row[0]) for row in r.all())

    q2 = select(RoomMember.room_id).where(RoomMember.user_id == user_b_id)
    r2 = await db.execute(q2)
    rooms_b = set(str(row[0]) for row in r2.all())

    common = rooms_a & rooms_b
    if common:
        room_id = _uuid.UUID(next(iter(common)))
        room = await db.get(MessageRoom, room_id)
        if room and room.type == "direct":
            return room

    room = MessageRoom(type="direct")
    db.add(room)
    await db.flush()
    db.add(RoomMember(room_id=room.id, user_id=user_a_id))
    db.add(RoomMember(room_id=room.id, user_id=user_b_id))
    await db.commit()
    await db.refresh(room)
    return room


async def _require_member(db: AsyncSession, room_id, user_id) -> None:
    mem_q = select(RoomMember).where(
        and_(RoomMember.room_id == room_id, RoomMember.user_id == user_id)
    )
    mem_r = await db.execute(mem_q)
    if not mem_r.scalar_one_or_none():
        raise HTTPException(status_code=403, detail="دسترسی ندارید")


async def _partner_last_read(db: AsyncSession, room_id, me_id) -> Optional[datetime]:
    """آخرین زمان خواندن توسط طرف مقابل (برای تیک دوگانه)"""
    q = (
        select(func.max(RoomMember.last_read_at))
        .where(and_(RoomMember.room_id == room_id, RoomMember.user_id != me_id))
    )
    r = await db.execute(q)
    return r.scalar_one_or_none()


# ── حضور (آنلاین/آخرین بازدید) و «در حال نوشتن» ──────────────────
_ONLINE_WINDOW = 45          # ثانیه؛ کاربر «آنلاین» اگر در این بازه فعال بوده باشد
_TYPING_TTL = 6.0            # ثانیه؛ اعتبارِ سیگنالِ در حال نوشتن
# وضعیتِ گذرای «در حال نوشتن»؛ کلید f"{room_id}:{user_id}" -> زمانِ انقضا (epoch)
_typing_state: Dict[str, float] = {}


def _is_online(last_seen: Optional[datetime]) -> bool:
    if not last_seen:
        return False
    if last_seen.tzinfo is None:
        last_seen = last_seen.replace(tzinfo=timezone.utc)
    return (datetime.now(timezone.utc) - last_seen).total_seconds() <= _ONLINE_WINDOW


async def _touch_presence(db: AsyncSession, me: User) -> None:
    """ثبتِ حضور: آخرین فعالیتِ کاربرِ جاری = اکنون (heartbeat)."""
    me.last_seen_at = datetime.now(timezone.utc)
    await db.commit()


async def _resolve_reply(db: AsyncSession, rid, reply_to_id: Optional[str]):
    """اعتبارسنجیِ reply هم‌اتاق؛ برمی‌گرداند (reply_to_uuid, ReplyPreview|None)"""
    if not reply_to_id:
        return None, None
    try:
        reply_uuid = _uuid.UUID(reply_to_id)
    except (ValueError, AttributeError):
        return None, None
    parent = await db.get(Message, reply_uuid)
    if not parent or parent.room_id != rid:
        return None, None
    psender = await db.get(User, parent.sender_id)
    preview = ReplyPreview(
        id=str(parent.id),
        sender_name=(psender.full_name or psender.username or psender.earth_id) if psender else None,
        content="" if parent.is_deleted else parent.content[:120],
        is_deleted=bool(parent.is_deleted),
    )
    return reply_uuid, preview


async def _direct_partner_id(db: AsyncSession, rid, me_id):
    """شناسهٔ عضوِ دیگرِ یک اتاقِ direct (در گروه/سیستم → None)."""
    room = await db.get(MessageRoom, rid)
    if not room or room.type != "direct":
        return None
    return (await db.execute(
        select(RoomMember.user_id).where(
            and_(RoomMember.room_id == rid, RoomMember.user_id != me_id)
        )
    )).scalar_one_or_none()


async def _is_pair_blocked(db: AsyncSession, a_id, b_id) -> bool:
    """آیا بینِ دو کاربر مسدودسازی (در هر جهت) وجود دارد؟"""
    if not a_id or not b_id:
        return False
    return (await db.execute(
        select(UserBlock.id).where(or_(
            and_(UserBlock.blocker_id == a_id, UserBlock.blocked_id == b_id),
            and_(UserBlock.blocker_id == b_id, UserBlock.blocked_id == a_id),
        )).limit(1)
    )).scalar_one_or_none() is not None


async def _ensure_not_blocked(db: AsyncSession, rid, me_id) -> None:
    """در اتاقِ direct اگر یکی از طرفین دیگری را مسدود کرده باشد، ارسال ممنوع است."""
    other = await _direct_partner_id(db, rid, me_id)
    if other and await _is_pair_blocked(db, me_id, other):
        raise HTTPException(status_code=403, detail="به دلیلِ مسدودسازی امکانِ ارسالِ پیام نیست")


# ── Endpoints ─────────────────────────────────────────────────

@router.get("/rooms", response_model=List[RoomOut])
async def list_rooms(
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """لیست تمام اتاق‌های من با آخرین پیام و شمارِ نخوانده‌ها"""
    q = select(RoomMember).where(RoomMember.user_id == me.id)
    r = await db.execute(q)
    my_memberships = r.scalars().all()
    if not my_memberships:
        return []

    room_ids = [m.room_id for m in my_memberships]
    last_read_by_room = {m.room_id: m.last_read_at for m in my_memberships}
    cleared_by_room = {m.room_id: m.cleared_at for m in my_memberships}
    muted_by_room = {m.room_id: m.muted_until for m in my_memberships}
    now_dt = datetime.now(timezone.utc)

    # کاربرانی که من مسدود کرده‌ام (برای نمایشِ وضعیتِ اتاقِ direct)
    my_blocks = set((await db.execute(
        select(UserBlock.blocked_id).where(UserBlock.blocker_id == me.id)
    )).scalars().all())

    rooms_q = select(MessageRoom).where(MessageRoom.id.in_(room_ids))
    rooms_r = await db.execute(rooms_q)
    rooms = rooms_r.scalars().all()

    result = []
    for room in rooms:
        partner_name = partner_earth_id = partner_role = partner_avatar = None
        partner_online = False
        partner_last_seen = None
        is_blocked = False
        if room.type == "direct":
            members_q = (
                select(User)
                .join(RoomMember, RoomMember.user_id == User.id)
                .where(and_(RoomMember.room_id == room.id, User.id != me.id))
            )
            members_r = await db.execute(members_q)
            partner = members_r.scalar_one_or_none()
            if partner:
                partner_name = partner.full_name or partner.username or partner.earth_id
                partner_earth_id = partner.earth_id
                partner_role = partner.role
                partner_avatar = partner.avatar_url
                partner_last_seen = partner.last_seen_at
                partner_online = _is_online(partner.last_seen_at)
                is_blocked = partner.id in my_blocks

        my_cleared = cleared_by_room.get(room.id)
        last_msg_q = (
            select(Message)
            .where(and_(Message.room_id == room.id, Message.is_deleted == False))
            .order_by(Message.created_at.desc())
            .limit(1)
        )
        if my_cleared is not None:
            last_msg_q = last_msg_q.where(Message.created_at > my_cleared)
        last_r = await db.execute(last_msg_q)
        last_msg = last_r.scalar_one_or_none()

        # unread = messages by others, after my last_read_at
        my_read = last_read_by_room.get(room.id)
        unread_filter = [
            Message.room_id == room.id,
            Message.sender_id != me.id,
            Message.is_deleted == False,
        ]
        if my_read is not None:
            unread_filter.append(Message.created_at > my_read)
        if my_cleared is not None:
            unread_filter.append(Message.created_at > my_cleared)
        unread_q = select(func.count(Message.id)).where(and_(*unread_filter))
        unread_r = await db.execute(unread_q)
        unread_count = unread_r.scalar_one_or_none() or 0

        member_count = 0
        if room.type == "group":
            mc_q = select(func.count(RoomMember.id)).where(RoomMember.room_id == room.id)
            mc_r = await db.execute(mc_q)
            member_count = mc_r.scalar_one_or_none() or 0

        result.append(RoomOut(
            id=str(room.id),
            type=room.type,
            name=room.name if room.type != "direct" else None,
            partner_name=partner_name,
            partner_earth_id=partner_earth_id,
            partner_role=partner_role,
            partner_avatar=partner_avatar if room.type == "direct" else room.avatar_url,
            last_message=_last_preview(last_msg) if last_msg else None,
            last_message_at=last_msg.created_at if last_msg else None,
            unread_count=unread_count,
            member_count=member_count,
            is_admin=(room.created_by == me.id),
            partner_online=partner_online,
            partner_last_seen=partner_last_seen,
            is_muted=bool(muted_by_room.get(room.id) and muted_by_room[room.id] > now_dt),
            is_blocked=is_blocked,
            created_at=room.created_at,
        ))

    await _touch_presence(db, me)
    return sorted(result, key=lambda r: r.last_message_at or r.created_at, reverse=True)


@router.post("/rooms", response_model=RoomOut, status_code=status.HTTP_201_CREATED)
async def start_or_get_room(
    body: StartRoomRequest,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """شروع مکالمه با یک کاربر دیگر (یا بازگشت اتاق موجود)"""
    if body.earth_id == me.earth_id:
        raise HTTPException(status_code=400, detail="نمی‌توانید با خودتان مکالمه داشته باشید")

    user_q = select(User).where(User.earth_id == body.earth_id)
    user_r = await db.execute(user_q)
    partner = user_r.scalar_one_or_none()
    if not partner:
        raise HTTPException(status_code=404, detail="کاربر پیدا نشد")

    room = await _get_or_create_direct_room(db, me.id, partner.id)

    i_blocked = (await db.execute(
        select(UserBlock.id).where(and_(
            UserBlock.blocker_id == me.id, UserBlock.blocked_id == partner.id
        )).limit(1)
    )).scalar_one_or_none() is not None

    return RoomOut(
        id=str(room.id),
        type=room.type,
        name=room.name,
        partner_name=partner.full_name or partner.username or partner.earth_id,
        partner_earth_id=partner.earth_id,
        partner_role=partner.role,
        partner_avatar=partner.avatar_url,
        last_message=None,
        last_message_at=None,
        unread_count=0,
        partner_online=_is_online(partner.last_seen_at),
        partner_last_seen=partner.last_seen_at,
        is_blocked=i_blocked,
        created_at=room.created_at,
    )


class RoomStatusOut(BaseModel):
    partner_online: bool = False
    partner_last_seen: Optional[datetime] = None
    typing: List[str] = []            # نامِ اعضایی که همین حالا در حال نوشتن‌اند


@router.get("/rooms/{room_id}/status", response_model=RoomStatusOut)
async def room_status(
    room_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """وضعیتِ لحظه‌ایِ اتاق: آنلاین/آخرین‌بازدیدِ طرف مقابل + «در حال نوشتن».
    خودِ این فراخوانی به‌عنوانِ heartbeat حضورِ منِ جاری را تازه می‌کند."""
    me_id = me.id
    try:
        rid = _uuid.UUID(room_id)
    except (ValueError, AttributeError):
        raise HTTPException(status_code=400, detail="اتاقِ نامعتبر")
    await _require_member(db, rid, me_id)

    now_e = time.time()
    others = (
        await db.execute(
            select(User)
            .join(RoomMember, RoomMember.user_id == User.id)
            .where(and_(RoomMember.room_id == rid, User.id != me_id))
        )
    ).scalars().all()

    typing: List[str] = []
    partner_online = False
    partner_last_seen = None
    for u in others:
        exp = _typing_state.get(f"{room_id}:{u.id}")
        if exp and exp > now_e:
            typing.append(u.full_name or u.username or u.earth_id)
        if partner_last_seen is None:  # اتاقِ direct: یک عضوِ دیگر
            partner_last_seen = u.last_seen_at
            partner_online = _is_online(u.last_seen_at)

    await _touch_presence(db, me)
    return RoomStatusOut(
        partner_online=partner_online,
        partner_last_seen=partner_last_seen,
        typing=typing,
    )


@router.post("/rooms/{room_id}/typing", status_code=status.HTTP_204_NO_CONTENT)
async def set_typing(
    room_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """اعلامِ «در حال نوشتن» (گذرا، اعتبارِ ~۶ ثانیه)."""
    try:
        rid = _uuid.UUID(room_id)
    except (ValueError, AttributeError):
        raise HTTPException(status_code=400, detail="اتاقِ نامعتبر")
    await _require_member(db, rid, me.id)
    _typing_state[f"{room_id}:{me.id}"] = time.time() + _TYPING_TTL
    # پاکسازیِ سبک از ورودی‌های منقضی تا dict رشد نکند
    if len(_typing_state) > 500:
        now_e = time.time()
        for k in [k for k, v in _typing_state.items() if v <= now_e]:
            _typing_state.pop(k, None)
    await _touch_presence(db, me)
    return None


@router.get("/rooms/{room_id}/messages", response_model=List[MessageOut])
async def get_messages(
    room_id: str,
    limit: int = Query(50, le=100),
    before: Optional[str] = Query(None, description="cursor: message id"),
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """تاریخچه پیام‌های یک اتاق (شاملِ reply/reaction/edited/read)"""
    rid = _uuid.UUID(room_id)
    await _require_member(db, rid, me.id)

    my_mem = (await db.execute(
        select(RoomMember).where(and_(RoomMember.room_id == rid, RoomMember.user_id == me.id))
    )).scalar_one_or_none()
    cleared = my_mem.cleared_at if my_mem else None

    q = (
        select(Message, User.full_name, User.username, User.earth_id)
        .join(User, User.id == Message.sender_id)
        .where(Message.room_id == rid)
        .order_by(Message.created_at.desc())
        .limit(limit)
    )
    if cleared is not None:
        q = q.where(Message.created_at > cleared)
    if before:
        pivot = await db.get(Message, _uuid.UUID(before))
        if pivot:
            q = q.where(Message.created_at < pivot.created_at)

    r = await db.execute(q)
    rows = list(reversed(r.all()))
    if not rows:
        return []

    msg_ids = [row[0].id for row in rows]

    # reactions for these messages
    react_q = select(MessageReaction).where(MessageReaction.message_id.in_(msg_ids))
    react_r = await db.execute(react_q)
    reactions_by_msg: Dict[str, Dict[str, int]] = {}
    my_reaction_by_msg: Dict[str, str] = {}
    for rc in react_r.scalars().all():
        mid = str(rc.message_id)
        reactions_by_msg.setdefault(mid, {})
        reactions_by_msg[mid][rc.emoji] = reactions_by_msg[mid].get(rc.emoji, 0) + 1
        if rc.user_id == me.id:
            my_reaction_by_msg[mid] = rc.emoji

    # reply previews
    reply_ids = [row[0].reply_to_id for row in rows if row[0].reply_to_id]
    reply_map: Dict[str, ReplyPreview] = {}
    if reply_ids:
        rp_q = (
            select(Message, User.full_name, User.username, User.earth_id)
            .join(User, User.id == Message.sender_id)
            .where(Message.id.in_(reply_ids))
        )
        rp_r = await db.execute(rp_q)
        for rmsg, fn, un, eid in rp_r.all():
            reply_map[str(rmsg.id)] = ReplyPreview(
                id=str(rmsg.id),
                sender_name=fn or un or eid,
                content="" if rmsg.is_deleted else rmsg.content[:120],
                is_deleted=bool(rmsg.is_deleted),
            )

    partner_read_at = await _partner_last_read(db, rid, me.id)
    poll_map = await _build_polls(db, msg_ids, me.id)

    msgs = []
    for msg, full_name, username, earth_id in rows:
        mid = str(msg.id)
        is_mine = msg.sender_id == me.id
        is_read = bool(
            is_mine and partner_read_at is not None and msg.created_at <= partner_read_at
        )
        msgs.append(MessageOut(
            id=mid,
            sender_id=str(msg.sender_id),
            sender_name=full_name or username or earth_id,
            sender_earth_id=earth_id,
            content="" if msg.is_deleted else msg.content,
            is_mine=is_mine,
            is_deleted=bool(msg.is_deleted),
            edited=msg.edited_at is not None,
            reply_to=reply_map.get(str(msg.reply_to_id)) if msg.reply_to_id else None,
            reactions=reactions_by_msg.get(mid, {}),
            my_reaction=my_reaction_by_msg.get(mid),
            is_read=is_read,
            media_url=None if msg.is_deleted else msg.media_url,
            media_type=None if msg.is_deleted else msg.media_type,
            media_name=None if msg.is_deleted else msg.media_name,
            media_meta=None if msg.is_deleted else msg.media_meta,
            sticker_id=(str(msg.sticker_id) if msg.sticker_id else None),
            location=None if msg.is_deleted else _build_location(msg),
            poll=None if msg.is_deleted else poll_map.get(mid),
            is_forwarded=bool(getattr(msg, "is_forwarded", False)) and not msg.is_deleted,
            forwarded_from=None if msg.is_deleted else getattr(msg, "forwarded_from", None),
            is_pinned=bool(getattr(msg, "pinned_at", None)) and not msg.is_deleted,
            created_at=msg.created_at,
        ))
    return msgs


@router.get("/rooms/{room_id}/messages/search", response_model=List[MessageOut])
async def search_messages(
    room_id: str,
    q: str = Query(..., min_length=2, max_length=100, description="عبارتِ جستجو"),
    limit: int = Query(50, le=100),
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """جستجوی متنِ پیام‌ها در یک اتاق (ILIKE روی content و caption)."""
    rid = _uuid.UUID(room_id)
    await _require_member(db, rid, me.id)

    term = q.strip()
    if len(term) < 2:
        return []
    like = f"%{term}%"

    query = (
        select(Message, User.full_name, User.username, User.earth_id)
        .join(User, User.id == Message.sender_id)
        .where(and_(
            Message.room_id == rid,
            Message.is_deleted == False,
            Message.content.isnot(None),
            Message.content.ilike(like),
        ))
        .order_by(Message.created_at.desc())
        .limit(limit)
    )
    r = await db.execute(query)
    rows = r.all()

    partner_read_at = await _partner_last_read(db, rid, me.id)

    out = []
    for msg, full_name, username, earth_id in rows:
        is_mine = msg.sender_id == me.id
        out.append(MessageOut(
            id=str(msg.id),
            sender_id=str(msg.sender_id),
            sender_name=full_name or username or earth_id,
            sender_earth_id=earth_id,
            content=msg.content,
            is_mine=is_mine,
            is_deleted=False,
            edited=msg.edited_at is not None,
            reply_to=None,
            reactions={},
            my_reaction=None,
            is_read=bool(is_mine and partner_read_at is not None and msg.created_at <= partner_read_at),
            media_url=msg.media_url,
            media_type=msg.media_type,
            media_name=msg.media_name,
            media_meta=msg.media_meta,
            sticker_id=(str(msg.sticker_id) if msg.sticker_id else None),
            location=_build_location(msg),
            is_forwarded=bool(getattr(msg, "is_forwarded", False)),
            forwarded_from=getattr(msg, "forwarded_from", None),
            created_at=msg.created_at,
        ))
    return out


class PinStateOut(BaseModel):
    is_pinned: bool
    pinned_count: int


@router.post("/messages/{message_id}/pin", response_model=PinStateOut)
async def toggle_pin(
    message_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """سنجاق/برداشتنِ سنجاقِ یک پیام (toggle). هر عضوِ اتاق مجاز است."""
    try:
        mid = _uuid.UUID(message_id)
    except (ValueError, AttributeError):
        raise HTTPException(status_code=400, detail="پیامِ نامعتبر")
    msg = await db.get(Message, mid)
    if not msg or msg.is_deleted:
        raise HTTPException(status_code=404, detail="پیام پیدا نشد")
    room_id_local = msg.room_id
    await _require_member(db, room_id_local, me.id)

    if getattr(msg, "pinned_at", None):
        msg.pinned_at = None
        msg.pinned_by = None
        is_pinned_now = False
    else:
        msg.pinned_at = datetime.now(timezone.utc)
        msg.pinned_by = me.id
        is_pinned_now = True
    await db.commit()

    cnt = (await db.execute(
        select(func.count(Message.id)).where(and_(
            Message.room_id == room_id_local,
            Message.pinned_at.isnot(None),
            Message.is_deleted == False,
        ))
    )).scalar_one_or_none() or 0
    return PinStateOut(is_pinned=is_pinned_now, pinned_count=cnt)


@router.get("/rooms/{room_id}/pins", response_model=List[MessageOut])
async def list_pins(
    room_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """پیام‌های سنجاق‌شدهٔ اتاق (جدید‌ترین سنجاق اول)."""
    try:
        rid = _uuid.UUID(room_id)
    except (ValueError, AttributeError):
        raise HTTPException(status_code=400, detail="اتاقِ نامعتبر")
    await _require_member(db, rid, me.id)

    query = (
        select(Message, User.full_name, User.username, User.earth_id)
        .join(User, User.id == Message.sender_id)
        .where(and_(
            Message.room_id == rid,
            Message.is_deleted == False,
            Message.pinned_at.isnot(None),
        ))
        .order_by(Message.pinned_at.desc())
        .limit(50)
    )
    rows = (await db.execute(query)).all()
    partner_read_at = await _partner_last_read(db, rid, me.id)

    out = []
    for msg, full_name, username, earth_id in rows:
        is_mine = msg.sender_id == me.id
        out.append(MessageOut(
            id=str(msg.id),
            sender_id=str(msg.sender_id),
            sender_name=full_name or username or earth_id,
            sender_earth_id=earth_id,
            content=msg.content,
            is_mine=is_mine,
            is_deleted=False,
            edited=msg.edited_at is not None,
            reply_to=None,
            reactions={},
            my_reaction=None,
            is_read=bool(is_mine and partner_read_at is not None and msg.created_at <= partner_read_at),
            media_url=msg.media_url,
            media_type=msg.media_type,
            media_name=msg.media_name,
            media_meta=msg.media_meta,
            sticker_id=(str(msg.sticker_id) if msg.sticker_id else None),
            location=_build_location(msg),
            is_forwarded=bool(getattr(msg, "is_forwarded", False)),
            forwarded_from=getattr(msg, "forwarded_from", None),
            is_pinned=True,
            created_at=msg.created_at,
        ))
    return out


@router.post("/rooms/{room_id}/messages", response_model=MessageOut, status_code=status.HTTP_201_CREATED)
async def send_message(
    room_id: str,
    body: SendMessageRequest,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """ارسال پیام (با پاسخ‌دادن اختیاری)"""
    rid = _uuid.UUID(room_id)
    await _require_member(db, rid, me.id)
    await _ensure_not_blocked(db, rid, me.id)

    reply_to_uuid = None
    reply_preview = None
    if body.reply_to_id:
        try:
            reply_to_uuid = _uuid.UUID(body.reply_to_id)
        except ValueError:
            reply_to_uuid = None
        if reply_to_uuid:
            parent = await db.get(Message, reply_to_uuid)
            if not parent or parent.room_id != rid:
                reply_to_uuid = None
            else:
                psender = await db.get(User, parent.sender_id)
                reply_preview = ReplyPreview(
                    id=str(parent.id),
                    sender_name=(psender.full_name or psender.username or psender.earth_id) if psender else None,
                    content="" if parent.is_deleted else parent.content[:120],
                    is_deleted=bool(parent.is_deleted),
                )

    msg = Message(
        room_id=rid,
        sender_id=me.id,
        content=body.content,
        reply_to_id=reply_to_uuid,
    )
    db.add(msg)
    await db.commit()
    await db.refresh(msg)

    return MessageOut(
        id=str(msg.id),
        sender_id=str(msg.sender_id),
        sender_name=me.full_name or me.username or me.earth_id,
        sender_earth_id=me.earth_id,
        content=msg.content,
        is_mine=True,
        is_deleted=False,
        edited=False,
        reply_to=reply_preview,
        reactions={},
        my_reaction=None,
        is_read=False,
        created_at=msg.created_at,
    )


@router.post("/rooms/{room_id}/poll", response_model=MessageOut, status_code=status.HTTP_201_CREATED)
async def create_poll(
    room_id: str,
    body: CreatePollRequest,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """ساختِ نظرسنجی به‌صورتِ یک پیام (media_type='poll'؛ سؤال در content ذخیره می‌شود)."""
    rid = _uuid.UUID(room_id)
    await _require_member(db, rid, me.id)
    await _ensure_not_blocked(db, rid, me.id)

    question = body.question.strip()
    options = [o.strip() for o in body.options if o and o.strip()]
    if not question:
        raise HTTPException(status_code=400, detail="سؤالِ نظرسنجی خالی است")
    if len(options) < 2:
        raise HTTPException(status_code=400, detail="حداقل ۲ گزینهٔ معتبر لازم است")

    reply_to_uuid = None
    if body.reply_to_id:
        try:
            ruid = _uuid.UUID(body.reply_to_id)
            parent = await db.get(Message, ruid)
            if parent and parent.room_id == rid:
                reply_to_uuid = ruid
        except ValueError:
            pass

    msg = Message(
        room_id=rid,
        sender_id=me.id,
        content=question,
        media_type="poll",
        reply_to_id=reply_to_uuid,
    )
    db.add(msg)
    await db.flush()

    poll = MessagePoll(
        message_id=msg.id,
        question=question,
        options=json.dumps(options, ensure_ascii=False),
        multiple=bool(body.multiple),
    )
    db.add(poll)
    await db.commit()
    await db.refresh(msg)
    await db.refresh(poll)

    return MessageOut(
        id=str(msg.id),
        sender_id=str(msg.sender_id),
        sender_name=me.full_name or me.username or me.earth_id,
        sender_earth_id=me.earth_id,
        content=msg.content,
        is_mine=True,
        is_deleted=False,
        edited=False,
        reply_to=None,
        reactions={},
        my_reaction=None,
        is_read=False,
        media_type="poll",
        poll=PollInfo(
            id=str(poll.id),
            question=poll.question,
            multiple=bool(poll.multiple),
            total_votes=0,
            options=[PollOption(text=o, votes=0, voted=False) for o in options],
        ),
        created_at=msg.created_at,
    )


@router.post("/polls/{poll_id}/vote", response_model=PollInfo)
async def vote_poll(
    poll_id: str,
    body: VoteRequest,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """رأی‌دادن/برداشتنِ رأی از یک گزینه (toggle). در حالتِ تک‌گزینه‌ای رأیِ قبلی جایگزین می‌شود."""
    try:
        pid = _uuid.UUID(poll_id)
    except (ValueError, AttributeError):
        raise HTTPException(status_code=400, detail="نظرسنجیِ نامعتبر")

    poll = await db.get(MessagePoll, pid)
    if not poll:
        raise HTTPException(status_code=404, detail="نظرسنجی پیدا نشد")

    msg = await db.get(Message, poll.message_id)
    if not msg or msg.is_deleted:
        raise HTTPException(status_code=404, detail="نظرسنجی پیدا نشد")
    await _require_member(db, msg.room_id, me.id)

    try:
        opts = json.loads(poll.options)
    except (ValueError, TypeError):
        opts = []
    if body.option_index >= len(opts):
        raise HTTPException(status_code=400, detail="گزینهٔ نامعتبر")

    existing = (await db.execute(
        select(PollVote).where(and_(PollVote.poll_id == pid, PollVote.user_id == me.id))
    )).scalars().all()
    same = next((v for v in existing if v.option_index == body.option_index), None)

    if same:
        # تپِ دوباره روی همان گزینه = برداشتنِ رأی
        await db.delete(same)
    else:
        if not poll.multiple:
            # تک‌گزینه‌ای: رأی‌های قبلی حذف می‌شوند
            for v in existing:
                await db.delete(v)
        db.add(PollVote(poll_id=pid, user_id=me.id, option_index=body.option_index))
    await db.commit()

    result = await _build_polls(db, [poll.message_id], me.id)
    return result[str(poll.message_id)]


@router.post("/rooms/{room_id}/media", response_model=MessageOut, status_code=status.HTTP_201_CREATED)
async def send_media_message(
    room_id: str,
    file: UploadFile = File(...),
    caption: Optional[str] = Form(None),
    reply_to_id: Optional[str] = Form(None),
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """ارسالِ عکس / پیامِ صوتی / فایل در چت"""
    rid = _uuid.UUID(room_id)
    await _require_member(db, rid, me.id)
    await _ensure_not_blocked(db, rid, me.id)

    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="فایل خالی است")
    if len(data) > _MAX_MEDIA_SIZE:
        raise HTTPException(status_code=413, detail="حجم فایل نباید بیشتر از ۲۵ مگابایت باشد")

    media_type = _classify_media(file.content_type or "")
    ext = os.path.splitext(file.filename or "")[1].lower()
    if not ext:
        ext = {"image": ".jpg", "voice": ".webm", "video": ".webm"}.get(media_type, ".bin")
    filename = f"{rid.hex[:8]}_{me.earth_id}_{_uuid.uuid4().hex[:8]}{ext}"
    os.makedirs(CHAT_MEDIA_DIR, exist_ok=True)
    with open(os.path.join(CHAT_MEDIA_DIR, filename), "wb") as f:
        f.write(data)
    media_url = f"{CHAT_MEDIA_BASE_URL}/{filename}"

    # reply validation (same as text send)
    reply_to_uuid = None
    reply_preview = None
    if reply_to_id:
        try:
            reply_to_uuid = _uuid.UUID(reply_to_id)
        except ValueError:
            reply_to_uuid = None
        if reply_to_uuid:
            parent = await db.get(Message, reply_to_uuid)
            if not parent or parent.room_id != rid:
                reply_to_uuid = None
            else:
                psender = await db.get(User, parent.sender_id)
                reply_preview = ReplyPreview(
                    id=str(parent.id),
                    sender_name=(psender.full_name or psender.username or psender.earth_id) if psender else None,
                    content="" if parent.is_deleted else parent.content[:120],
                    is_deleted=bool(parent.is_deleted),
                )

    msg = Message(
        room_id=rid,
        sender_id=me.id,
        content=(caption or "").strip(),
        reply_to_id=reply_to_uuid,
        media_url=media_url,
        media_type=media_type,
        media_name=(file.filename or "")[:300] if media_type == "file" else None,
        media_meta=_human_size(len(data)),
    )
    db.add(msg)
    await db.commit()
    await db.refresh(msg)

    return MessageOut(
        id=str(msg.id),
        sender_id=str(msg.sender_id),
        sender_name=me.full_name or me.username or me.earth_id,
        sender_earth_id=me.earth_id,
        content=msg.content,
        is_mine=True,
        is_deleted=False,
        edited=False,
        reply_to=reply_preview,
        reactions={},
        my_reaction=None,
        is_read=False,
        media_url=msg.media_url,
        media_type=msg.media_type,
        media_name=msg.media_name,
        media_meta=msg.media_meta,
        created_at=msg.created_at,
    )


def _location_out(msg, me, reply_preview) -> MessageOut:
    return MessageOut(
        id=str(msg.id),
        sender_id=str(msg.sender_id),
        sender_name=me.full_name or me.username or me.earth_id,
        sender_earth_id=me.earth_id,
        content=msg.content or "",
        is_mine=True,
        is_deleted=False,
        edited=False,
        reply_to=reply_preview,
        reactions={},
        my_reaction=None,
        is_read=False,
        media_type=msg.media_type,
        location=_build_location(msg),
        created_at=msg.created_at,
    )


@router.post("/rooms/{room_id}/location", response_model=MessageOut, status_code=status.HTTP_201_CREATED)
async def send_location(
    room_id: str,
    body: LocationRequest,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """ارسالِ موقعیتِ مکانیِ ثابت (نقطهٔ روی نقشه)"""
    rid = _uuid.UUID(room_id)
    await _require_member(db, rid, me.id)
    await _ensure_not_blocked(db, rid, me.id)
    reply_uuid, reply_preview = await _resolve_reply(db, rid, body.reply_to_id)

    msg = Message(
        room_id=rid, sender_id=me.id, content="",
        reply_to_id=reply_uuid,
        media_type="location",
        loc_lat=body.lat, loc_lng=body.lng,
        loc_label=(body.label or None),
    )
    db.add(msg)
    await db.commit()
    await db.refresh(msg)
    return _location_out(msg, me, reply_preview)


@router.post("/rooms/{room_id}/live-location", response_model=MessageOut, status_code=status.HTTP_201_CREATED)
async def start_live_location(
    room_id: str,
    body: LiveLocationRequest,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """شروعِ اشتراکِ موقعیتِ زنده (متحرک) تا مدتِ مشخص"""
    rid = _uuid.UUID(room_id)
    await _require_member(db, rid, me.id)
    await _ensure_not_blocked(db, rid, me.id)
    reply_uuid, reply_preview = await _resolve_reply(db, rid, body.reply_to_id)

    now = datetime.now(timezone.utc)
    expires = now + timedelta(minutes=body.duration_minutes)
    msg = Message(
        room_id=rid, sender_id=me.id, content="",
        reply_to_id=reply_uuid,
        media_type="live_location",
        loc_lat=body.lat, loc_lng=body.lng,
        live_expires_at=expires, live_updated_at=now,
    )
    db.add(msg)
    await db.commit()
    await db.refresh(msg)
    return _location_out(msg, me, reply_preview)


@router.patch("/live-location/{message_id}", response_model=MessageOut)
async def update_live_location(
    message_id: str,
    body: LiveLocationUpdate,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """به‌روزرسانیِ مختصاتِ موقعیتِ زنده (فقط توسطِ صاحبِ اشتراک، تا انقضا)"""
    msg = await db.get(Message, _uuid.UUID(message_id))
    if not msg or msg.media_type != "live_location" or msg.is_deleted:
        raise HTTPException(status_code=404, detail="اشتراکِ موقعیتِ زنده پیدا نشد")
    if msg.sender_id != me.id:
        raise HTTPException(status_code=403, detail="فقط صاحبِ اشتراک می‌تواند به‌روزرسانی کند")
    now = datetime.now(timezone.utc)
    if msg.live_expires_at is None or msg.live_expires_at <= now:
        raise HTTPException(status_code=410, detail="این اشتراکِ موقعیت به پایان رسیده است")

    msg.loc_lat = body.lat
    msg.loc_lng = body.lng
    msg.live_updated_at = now
    await db.commit()
    await db.refresh(msg)
    return _location_out(msg, me, None)


@router.post("/live-location/{message_id}/stop", status_code=status.HTTP_200_OK)
async def stop_live_location(
    message_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """توقفِ اشتراکِ موقعیتِ زنده (صاحبِ اشتراک)"""
    msg = await db.get(Message, _uuid.UUID(message_id))
    if not msg or msg.media_type != "live_location" or msg.is_deleted:
        raise HTTPException(status_code=404, detail="اشتراکِ موقعیتِ زنده پیدا نشد")
    if msg.sender_id != me.id:
        raise HTTPException(status_code=403, detail="فقط صاحبِ اشتراک می‌تواند متوقف کند")
    msg.live_expires_at = datetime.now(timezone.utc)
    await db.commit()
    return {"stopped": True}


@router.patch("/messages/{message_id}", response_model=MessageOut)
async def edit_message(
    message_id: str,
    body: EditMessageRequest,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """ویرایش پیامِ خودم"""
    msg = await db.get(Message, _uuid.UUID(message_id))
    if not msg or msg.is_deleted:
        raise HTTPException(status_code=404, detail="پیام پیدا نشد")
    if msg.sender_id != me.id:
        raise HTTPException(status_code=403, detail="فقط می‌توانید پیام خودتان را ویرایش کنید")

    msg.content = body.content
    msg.edited_at = datetime.now(timezone.utc)
    # stale translations of the old text must go
    await db.execute(
        sa_delete(MessageTranslation).where(MessageTranslation.message_id == msg.id)
    )
    await db.commit()
    await db.refresh(msg)

    return MessageOut(
        id=str(msg.id),
        sender_id=str(msg.sender_id),
        sender_name=me.full_name or me.username or me.earth_id,
        sender_earth_id=me.earth_id,
        content=msg.content,
        is_mine=True,
        is_deleted=False,
        edited=True,
        reply_to=None,
        reactions={},
        my_reaction=None,
        is_read=False,
        created_at=msg.created_at,
    )


@router.delete("/messages/{message_id}", status_code=status.HTTP_200_OK)
async def delete_message(
    message_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """حذف پیامِ خودم برای همه (soft delete)"""
    msg = await db.get(Message, _uuid.UUID(message_id))
    if not msg:
        raise HTTPException(status_code=404, detail="پیام پیدا نشد")
    if msg.sender_id != me.id:
        raise HTTPException(status_code=403, detail="فقط می‌توانید پیام خودتان را حذف کنید")
    msg.is_deleted = True
    await db.commit()
    return {"ok": True, "id": message_id}


@router.post("/messages/{message_id}/forward", response_model=MessageOut, status_code=status.HTTP_201_CREATED)
async def forward_message(
    message_id: str,
    body: ForwardRequest,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """بازارسالِ پیام به اتاقِ دیگر — با نامِ فرستندهٔ اصلی یا بی‌نام."""
    src = await db.get(Message, _uuid.UUID(message_id))
    if not src or src.is_deleted:
        raise HTTPException(status_code=404, detail="پیام پیدا نشد")
    # باید عضوِ اتاقِ مبدأ باشم تا حقِ دیدن/بازارسالِ پیام را داشته باشم
    await _require_member(db, src.room_id, me.id)

    try:
        target_rid = _uuid.UUID(body.room_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="اتاقِ مقصد نامعتبر است")
    await _require_member(db, target_rid, me.id)

    # نامِ فرستندهٔ اصلی برای انتسابِ بازارسال
    orig_name = None
    if not body.anonymous:
        osender = await db.get(User, src.sender_id)
        if osender:
            orig_name = osender.full_name or osender.username or osender.earth_id

    new_msg = Message(
        room_id=target_rid,
        sender_id=me.id,
        content=src.content,
        media_url=src.media_url,
        media_type=src.media_type,
        media_name=src.media_name,
        media_meta=src.media_meta,
        sticker_id=src.sticker_id,
        loc_lat=src.loc_lat,
        loc_lng=src.loc_lng,
        loc_label=src.loc_label,
        is_forwarded=(not body.anonymous),
        forwarded_from=orig_name,
    )
    # موقعیتِ زنده به‌صورتِ ثابت بازارسال می‌شود (نه لینکِ زندهٔ کسِ دیگر)
    if new_msg.media_type == "live_location":
        new_msg.media_type = "location"
    db.add(new_msg)
    await db.commit()
    await db.refresh(new_msg)

    return MessageOut(
        id=str(new_msg.id),
        sender_id=str(new_msg.sender_id),
        sender_name=me.full_name or me.username or me.earth_id,
        sender_earth_id=me.earth_id,
        content=new_msg.content,
        is_mine=True,
        is_deleted=False,
        edited=False,
        reply_to=None,
        reactions={},
        my_reaction=None,
        is_read=False,
        media_url=new_msg.media_url,
        media_type=new_msg.media_type,
        media_name=new_msg.media_name,
        media_meta=new_msg.media_meta,
        sticker_id=(str(new_msg.sticker_id) if new_msg.sticker_id else None),
        location=_build_location(new_msg),
        is_forwarded=new_msg.is_forwarded,
        forwarded_from=new_msg.forwarded_from,
        created_at=new_msg.created_at,
    )


@router.post("/messages/{message_id}/react", status_code=status.HTTP_200_OK)
async def react_message(
    message_id: str,
    body: ReactRequest,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """واکنش به پیام (toggle): همان ایموجی دوباره → حذف، ایموجی متفاوت → جایگزین"""
    emoji = body.emoji.strip()
    if emoji not in _ALLOWED_EMOJI:
        raise HTTPException(status_code=400, detail="ایموجی نامعتبر")

    mid = _uuid.UUID(message_id)
    msg = await db.get(Message, mid)
    if not msg or msg.is_deleted:
        raise HTTPException(status_code=404, detail="پیام پیدا نشد")
    await _require_member(db, msg.room_id, me.id)

    existing_q = select(MessageReaction).where(
        and_(MessageReaction.message_id == mid, MessageReaction.user_id == me.id)
    )
    existing_r = await db.execute(existing_q)
    existing = existing_r.scalar_one_or_none()

    my_reaction: Optional[str]
    if existing is None:
        db.add(MessageReaction(message_id=mid, user_id=me.id, emoji=emoji))
        my_reaction = emoji
    elif existing.emoji == emoji:
        await db.delete(existing)
        my_reaction = None
    else:
        existing.emoji = emoji
        my_reaction = emoji
    await db.commit()

    # recompute counts
    counts_q = (
        select(MessageReaction.emoji, func.count(MessageReaction.id))
        .where(MessageReaction.message_id == mid)
        .group_by(MessageReaction.emoji)
    )
    counts_r = await db.execute(counts_q)
    reactions = {row[0]: row[1] for row in counts_r.all()}
    return {"ok": True, "reactions": reactions, "my_reaction": my_reaction}


@router.post("/rooms/{room_id}/read", status_code=status.HTTP_200_OK)
async def mark_read(
    room_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """علامت‌گذاری تمام پیام‌های اتاق به‌عنوان خوانده‌شده"""
    rid = _uuid.UUID(room_id)
    mem_q = select(RoomMember).where(
        and_(RoomMember.room_id == rid, RoomMember.user_id == me.id)
    )
    mem_r = await db.execute(mem_q)
    mem = mem_r.scalar_one_or_none()
    if not mem:
        raise HTTPException(status_code=403, detail="دسترسی ندارید")
    mem.last_read_at = datetime.now(timezone.utc)
    await db.commit()
    return {"ok": True}


# ── Translation ───────────────────────────────────────────────

@router.post("/messages/{message_id}/translate", response_model=TranslationOut)
async def translate_message(
    message_id: str,
    body: TranslateMessageRequest,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """ترجمهٔ یک پیامِ چت به زبانِ مقصد (با کشِ پایدار)."""
    target = _norm_lang(body.target_lang)
    mid = _uuid.UUID(message_id)
    msg = await db.get(Message, mid)
    if not msg or msg.is_deleted:
        raise HTTPException(status_code=404, detail="پیام پیدا نشد")
    await _require_member(db, msg.room_id, me.id)

    original = (msg.content or "").strip()
    if not original:
        raise HTTPException(status_code=400, detail="این پیام متنی برای ترجمه ندارد")

    # cache lookup
    cache_q = select(MessageTranslation).where(
        and_(MessageTranslation.message_id == mid, MessageTranslation.target_lang == target)
    )
    cache_r = await db.execute(cache_q)
    cached = cache_r.scalar_one_or_none()
    if cached:
        return TranslationOut(
            message_id=message_id, target_lang=target,
            detected_lang=cached.detected_lang, original=original,
            translated_text=cached.translated_text, cached=True,
        )

    translated, detected = await _google_translate(original, target)
    if not translated:
        raise HTTPException(status_code=502, detail="ترجمه‌ای برگردانده نشد")

    db.add(MessageTranslation(
        message_id=mid, target_lang=target,
        translated_text=translated, detected_lang=detected,
    ))
    try:
        await db.commit()
    except Exception:
        await db.rollback()  # concurrent insert → ignore, cache already there next time

    return TranslationOut(
        message_id=message_id, target_lang=target,
        detected_lang=detected, original=original,
        translated_text=translated, cached=False,
    )


@router.post("/translate", response_model=TranslationOut)
async def translate_text(
    body: TranslateTextRequest,
    me: User = Depends(get_current_user),
):
    """ترجمهٔ متنِ آزاد (پیش‌نمایشِ نگارش پیش از ارسال). بدون کش."""
    target = _norm_lang(body.target_lang)
    text = body.text.strip()
    if not text:
        raise HTTPException(status_code=400, detail="متنی برای ترجمه نیست")
    translated, detected = await _google_translate(text, target)
    if not translated:
        raise HTTPException(status_code=502, detail="ترجمه‌ای برگردانده نشد")
    return TranslationOut(
        message_id=None, target_lang=target,
        detected_lang=detected, original=text,
        translated_text=translated, cached=False,
    )


# ── Groups ────────────────────────────────────────────────────

@router.post("/groups", response_model=RoomOut, status_code=status.HTTP_201_CREATED)
async def create_group(
    body: CreateGroupRequest,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """ساختِ گروه با نام و لیستِ earth_id اعضا (سازنده admin است)"""
    name = body.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="نامِ گروه لازم است")

    # resolve member earth_ids -> users (exclude me + dedup)
    member_ids = set()
    wanted = [e.strip().upper() for e in body.member_earth_ids if e.strip()]
    if wanted:
        u_q = select(User).where(User.earth_id.in_(wanted))
        u_r = await db.execute(u_q)
        for u in u_r.scalars().all():
            if u.id != me.id:
                member_ids.add(u.id)

    room = MessageRoom(type="group", name=name, created_by=me.id)
    db.add(room)
    await db.flush()

    db.add(RoomMember(room_id=room.id, user_id=me.id))
    for uid in member_ids:
        db.add(RoomMember(room_id=room.id, user_id=uid))
    await db.commit()
    await db.refresh(room)

    return RoomOut(
        id=str(room.id),
        type="group",
        name=room.name,
        partner_name=None,
        partner_earth_id=None,
        partner_role=None,
        partner_avatar=room.avatar_url,
        last_message=None,
        last_message_at=None,
        unread_count=0,
        member_count=len(member_ids) + 1,
        is_admin=True,
        created_at=room.created_at,
    )


@router.get("/rooms/{room_id}/members", response_model=List[MemberOut])
async def list_members(
    room_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """اعضای یک اتاق (گروه یا direct)"""
    rid = _uuid.UUID(room_id)
    await _require_member(db, rid, me.id)
    room = await db.get(MessageRoom, rid)

    q = (
        select(User)
        .join(RoomMember, RoomMember.user_id == User.id)
        .where(RoomMember.room_id == rid)
    )
    r = await db.execute(q)
    users = r.scalars().all()
    return [
        MemberOut(
            earth_id=u.earth_id,
            name=u.full_name or u.username or u.earth_id,
            role=u.role,
            avatar_url=u.avatar_url,
            is_me=(u.id == me.id),
            is_admin=(room is not None and room.created_by == u.id),
        )
        for u in users
    ]


@router.post("/rooms/{room_id}/members", status_code=status.HTTP_200_OK)
async def add_member(
    room_id: str,
    body: AddMemberRequest,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """افزودنِ عضو به گروه (فقط اعضای موجود می‌توانند)"""
    rid = _uuid.UUID(room_id)
    await _require_member(db, rid, me.id)
    room = await db.get(MessageRoom, rid)
    if not room or room.type != "group":
        raise HTTPException(status_code=400, detail="فقط برای گروه‌ها ممکن است")

    u_q = select(User).where(User.earth_id == body.earth_id.strip().upper())
    u_r = await db.execute(u_q)
    target = u_r.scalar_one_or_none()
    if not target:
        raise HTTPException(status_code=404, detail="کاربر پیدا نشد")

    exists_q = select(RoomMember).where(
        and_(RoomMember.room_id == rid, RoomMember.user_id == target.id)
    )
    exists_r = await db.execute(exists_q)
    if exists_r.scalar_one_or_none():
        return {"ok": True, "already_member": True}

    db.add(RoomMember(room_id=rid, user_id=target.id))
    await db.commit()
    return {"ok": True, "already_member": False}


@router.delete("/rooms/{room_id}/members/{earth_id}", status_code=status.HTTP_200_OK)
async def remove_member(
    room_id: str,
    earth_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """حذفِ عضو: خود کاربر (ترکِ گروه) یا admin برای دیگران"""
    rid = _uuid.UUID(room_id)
    await _require_member(db, rid, me.id)
    room = await db.get(MessageRoom, rid)
    if not room or room.type != "group":
        raise HTTPException(status_code=400, detail="فقط برای گروه‌ها ممکن است")

    u_q = select(User).where(User.earth_id == earth_id.strip().upper())
    u_r = await db.execute(u_q)
    target = u_r.scalar_one_or_none()
    if not target:
        raise HTTPException(status_code=404, detail="کاربر پیدا نشد")

    is_self = target.id == me.id
    is_admin = room.created_by == me.id
    if not is_self and not is_admin:
        raise HTTPException(status_code=403, detail="فقط ادمین می‌تواند دیگران را حذف کند")

    mem_q = select(RoomMember).where(
        and_(RoomMember.room_id == rid, RoomMember.user_id == target.id)
    )
    mem_r = await db.execute(mem_q)
    mem = mem_r.scalar_one_or_none()
    if mem:
        await db.delete(mem)
        await db.commit()
    return {"ok": True, "left": is_self}


# ── Send a sticker from the library ──────────────────────────
class StickerSendIn(BaseModel):
    sticker_id: str
    reply_to_id: Optional[str] = None


@router.post("/rooms/{room_id}/sticker", response_model=MessageOut,
             status_code=status.HTTP_201_CREATED)
async def send_sticker_message(
    room_id: str,
    body: StickerSendIn,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """ارسالِ یک استیکر از کتابخانه (با حفظِ لینک به بسته برای کاوش)."""
    from app.models.stickers import Sticker
    rid = _uuid.UUID(room_id)
    await _require_member(db, rid, me.id)
    await _ensure_not_blocked(db, rid, me.id)
    try:
        sid = _uuid.UUID(body.sticker_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="استیکر یافت نشد")
    st = await db.get(Sticker, sid)
    if not st:
        raise HTTPException(status_code=404, detail="استیکر یافت نشد")

    reply_to_uuid = None
    reply_preview = None
    if body.reply_to_id:
        try:
            reply_to_uuid = _uuid.UUID(body.reply_to_id)
        except ValueError:
            reply_to_uuid = None
        if reply_to_uuid:
            parent = await db.get(Message, reply_to_uuid)
            if not parent or parent.room_id != rid:
                reply_to_uuid = None
            else:
                psender = await db.get(User, parent.sender_id)
                reply_preview = ReplyPreview(
                    id=str(parent.id),
                    sender_name=(psender.full_name or psender.username or psender.earth_id) if psender else None,
                    content="" if parent.is_deleted else parent.content[:120],
                    is_deleted=bool(parent.is_deleted),
                )

    msg = Message(
        room_id=rid, sender_id=me.id, content="",
        reply_to_id=reply_to_uuid,
        media_url=st.media_url, media_type=st.media_type,
        sticker_id=st.id,
    )
    db.add(msg)
    st.use_count = (st.use_count or 0) + 1
    await db.commit()
    await db.refresh(msg)
    return MessageOut(
        id=str(msg.id), sender_id=str(msg.sender_id),
        sender_name=me.full_name or me.username or me.earth_id,
        sender_earth_id=me.earth_id, content="", is_mine=True, is_deleted=False,
        edited=False, reply_to=reply_preview, reactions={}, my_reaction=None,
        is_read=False, media_url=msg.media_url, media_type=msg.media_type,
        sticker_id=str(msg.sticker_id), created_at=msg.created_at,
    )


# ── تنظیماتِ گفتگو: مسدودسازی / بی‌صداکردن / پاک‌کردن ─────────────

class BlockStateOut(BaseModel):
    blocked: bool


class MuteRequest(BaseModel):
    muted: bool
    duration_minutes: Optional[int] = Field(None, ge=1, le=525600)  # None + muted=true → همیشه


class MuteStateOut(BaseModel):
    muted: bool
    muted_until: Optional[datetime] = None


class ClearChatOut(BaseModel):
    ok: bool = True
    cleared_at: datetime


@router.post("/users/{earth_id}/block", response_model=BlockStateOut)
async def toggle_block(
    earth_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """مسدود/رفعِ مسدودیِ یک کاربر (toggle). در اتاقِ direct، مسدودی ارسالِ پیام را از هر دو طرف می‌بندد."""
    target = (await db.execute(
        select(User).where(User.earth_id == earth_id)
    )).scalar_one_or_none()
    if not target:
        raise HTTPException(status_code=404, detail="کاربر پیدا نشد")
    if target.id == me.id:
        raise HTTPException(status_code=400, detail="نمی‌توانید خودتان را مسدود کنید")

    existing = (await db.execute(
        select(UserBlock).where(and_(
            UserBlock.blocker_id == me.id, UserBlock.blocked_id == target.id
        ))
    )).scalar_one_or_none()
    if existing:
        await db.delete(existing)
        await db.commit()
        return BlockStateOut(blocked=False)
    db.add(UserBlock(blocker_id=me.id, blocked_id=target.id))
    await db.commit()
    return BlockStateOut(blocked=True)


@router.get("/blocks", response_model=List[str])
async def list_blocks(
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """earth_idِ کاربرانی که من مسدود کرده‌ام."""
    rows = (await db.execute(
        select(User.earth_id)
        .join(UserBlock, UserBlock.blocked_id == User.id)
        .where(UserBlock.blocker_id == me.id)
    )).all()
    return [r[0] for r in rows]


@router.post("/rooms/{room_id}/mute", response_model=MuteStateOut)
async def set_mute(
    room_id: str,
    body: MuteRequest,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """بی‌صداکردن/فعال‌کردنِ اعلانِ یک اتاق (به‌ازای عضویتِ من)."""
    try:
        rid = _uuid.UUID(room_id)
    except (ValueError, AttributeError):
        raise HTTPException(status_code=400, detail="اتاقِ نامعتبر")
    mem = (await db.execute(
        select(RoomMember).where(and_(RoomMember.room_id == rid, RoomMember.user_id == me.id))
    )).scalar_one_or_none()
    if not mem:
        raise HTTPException(status_code=403, detail="دسترسی ندارید")

    now = datetime.now(timezone.utc)
    if not body.muted:
        mem.muted_until = None
    elif body.duration_minutes:
        mem.muted_until = now + timedelta(minutes=body.duration_minutes)
    else:
        mem.muted_until = now + timedelta(days=3650)   # عملاً همیشه
    await db.commit()
    active = bool(mem.muted_until and mem.muted_until > now)
    return MuteStateOut(muted=active, muted_until=mem.muted_until if active else None)


@router.post("/rooms/{room_id}/clear", response_model=ClearChatOut)
async def clear_chat(
    room_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """پاک‌کردنِ گفتگو برایِ من: پیام‌های موجود از نمایِ من پنهان می‌شوند (طرف مقابل دست‌نخورده)."""
    try:
        rid = _uuid.UUID(room_id)
    except (ValueError, AttributeError):
        raise HTTPException(status_code=400, detail="اتاقِ نامعتبر")
    mem = (await db.execute(
        select(RoomMember).where(and_(RoomMember.room_id == rid, RoomMember.user_id == me.id))
    )).scalar_one_or_none()
    if not mem:
        raise HTTPException(status_code=403, detail="دسترسی ندارید")

    now = datetime.now(timezone.utc)
    mem.cleared_at = now
    mem.last_read_at = now
    await db.commit()
    return ClearChatOut(ok=True, cleared_at=now)

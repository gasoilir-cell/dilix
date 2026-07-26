"""
Dilix — Live Router (پخشِ زندهٔ ویدیویی ۱-به-چند)
میزبان یک نشستِ زنده می‌سازد؛ بینندگان می‌پیوندند و میزبان به هر بیننده یک offerِ WebRTC
می‌فرستد (mesh از میزبان). سیگنالینگ روی همان Redis-poll (مثلِ /calls) سوار است؛ مدیا P2P می‌ماند.
چت/قلبِ زنده سبک و ephemeral روی Redis‌اند؛ جدولِ live_sessions فقط برای کشف/فهرست و تاریخچه.

POST /api/v1/live/start            شروعِ پخشِ زنده (میزبان)
GET  /api/v1/live                  فهرستِ پخش‌های زندهٔ فعال (کشف)
POST /api/v1/live/signal           رله‌ی offer/answer/ice/bye
GET  /api/v1/live/poll             دریافتِ سیگنال‌های صف‌شدهٔ من + heartbeat
POST /api/v1/live/{id}/join        پیوستنِ بیننده (به میزبان اعلام می‌کند)
POST /api/v1/live/{id}/leave       ترکِ بیننده
GET  /api/v1/live/{id}/state       وضعیت (بیننده‌ها/قلب‌ها/status) + heartbeatِ بیننده
POST /api/v1/live/{id}/chat        ارسالِ پیامِ چتِ زنده
GET  /api/v1/live/{id}/messages    پیام‌های اخیرِ چتِ زنده
POST /api/v1/live/{id}/heart       ارسالِ قلب (❤)
POST /api/v1/live/{id}/stop        پایانِ پخش (میزبان)
"""
import json
import time
import uuid as _uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import get_db
from app.core.redis import get_redis
from app.models.user import User
from app.models.live import LiveSession

router = APIRouter(prefix="/live", tags=["Live"])

Q_PREFIX       = "live:q:"        # LIST صفِ سیگنالِ هر earth_id (poll)
VIEWERS_PREFIX = "live:viewers:"  # ZSET بیننده‌ها (earth → ts) برای شمارش/حضور
HEARTS_PREFIX  = "live:hearts:"   # INT شمارندهٔ قلب‌ها
CHAT_PREFIX    = "live:chat:"     # LIST پیام‌های چتِ زنده (capped)

Q_TTL       = 90
SEEN_TTL    = 15    # بیننده‌ای که ۱۵s heartbeat نداشته آفلاین حساب می‌شود
MAX_Q       = 120
MAX_CHAT    = 100
STATE_TTL   = 6 * 3600  # کلیدهای Redisِ نشست بعد از ۶ ساعت خودپاک

ICE_SERVERS = [
    {"urls": "stun:stun.l.google.com:19302"},
    {"urls": "stun:stun1.l.google.com:19302"},
]

_SIGNAL_TYPES = {"offer", "answer", "ice", "bye"}


def _now():
    return datetime.now(timezone.utc)


def _host_out(u: User) -> dict:
    return {
        "earth_id": u.earth_id,
        "name": u.full_name or u.username or u.earth_id,
        "avatar_url": u.avatar_url,
    }


async def _push(r, to_earth: str, obj: dict) -> None:
    key = Q_PREFIX + to_earth
    await r.lpush(key, json.dumps(obj))
    await r.ltrim(key, 0, MAX_Q - 1)
    await r.expire(key, Q_TTL)


async def _viewer_count(r, sid: str) -> int:
    key = VIEWERS_PREFIX + sid
    await r.zremrangebyscore(key, 0, time.time() - SEEN_TTL)
    return int(await r.zcard(key))


async def _hearts(r, sid: str) -> int:
    v = await r.get(HEARTS_PREFIX + sid)
    try:
        return int(v) if v is not None else 0
    except (ValueError, TypeError):
        return 0


# ── Schemas ──────────────────────────────────────────────────
class StartIn(BaseModel):
    title: Optional[str] = Field(None, max_length=120)


class SignalIn(BaseModel):
    session_id: str
    to_earth_id: str
    type: str
    sdp: Optional[str] = None
    candidate: Optional[dict] = None


class ChatIn(BaseModel):
    text: str = Field(..., min_length=1, max_length=500)


class HeartIn(BaseModel):
    count: int = Field(1, ge=1, le=20)


# ── نشستِ فعال (helper) ───────────────────────────────────────
async def _get_live(db: AsyncSession, sid: str) -> LiveSession:
    try:
        sid_u = _uuid.UUID(sid)
    except ValueError:
        raise HTTPException(status_code=404, detail="پخشِ زنده پیدا نشد")
    s = await db.get(LiveSession, sid_u)
    if not s:
        raise HTTPException(status_code=404, detail="پخشِ زنده پیدا نشد")
    return s


# ── Endpoints ────────────────────────────────────────────────
@router.post("/start")
async def start_live(
    body: StartIn,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """شروعِ پخشِ زنده — یک نشستِ live می‌سازد و session_id + ICE برمی‌گرداند."""
    # اگر پخشِ زندهٔ بازِ قبلی داشتم، ببندش (تک‌پخشِ هم‌زمان به‌ازای میزبان)
    prev = (await db.execute(
        select(LiveSession).where(LiveSession.host_id == me.id, LiveSession.status == "live")
    )).scalars().all()
    for p in prev:
        p.status = "ended"
        p.ended_at = _now()
    title = (body.title or "").strip()[:120] or None
    s = LiveSession(host_id=me.id, title=title, status="live")
    db.add(s)
    await db.commit()
    await db.refresh(s)
    return {
        "session_id": str(s.id),
        "host": _host_out(me),
        "title": s.title,
        "iceServers": ICE_SERVERS,
        "started_at": s.started_at,
    }


@router.get("")
async def list_live(
    limit: int = Query(30, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """فهرستِ پخش‌های زندهٔ فعال (کشف) — به‌ترتیبِ جدیدترین."""
    q = (
        select(LiveSession, User)
        .join(User, User.id == LiveSession.host_id)
        .where(LiveSession.status == "live")
        .order_by(LiveSession.started_at.desc())
        .limit(limit)
    )
    rows = (await db.execute(q)).all()
    r = await get_redis()
    items = []
    for s, host in rows:
        items.append({
            "session_id": str(s.id),
            "title": s.title,
            "host": _host_out(host),
            "viewer_count": await _viewer_count(r, str(s.id)),
            "hearts": await _hearts(r, str(s.id)),
            "started_at": s.started_at,
            "is_mine": host.id == me.id,
        })
    return {"items": items}


@router.post("/signal")
async def signal(body: SignalIn, me: User = Depends(get_current_user)):
    """رله‌ی سیگنالِ offer/answer/ice/bye به صفِ مقصد."""
    if body.type not in _SIGNAL_TYPES:
        raise HTTPException(status_code=400, detail="نوعِ سیگنال نامعتبر")
    to = body.to_earth_id.strip().upper()
    r = await get_redis()
    await _push(r, to, {
        "type": body.type, "session_id": body.session_id,
        "from": me.earth_id, "sdp": body.sdp,
        "candidate": body.candidate, "ts": time.time(),
    })
    return {"ok": True}


@router.get("/poll")
async def poll(me: User = Depends(get_current_user)):
    """دریافت و خالی‌کردنِ صفِ سیگنالِ من (میزبان یا بیننده)."""
    r = await get_redis()
    key = Q_PREFIX + me.earth_id
    items = await r.lrange(key, 0, -1)
    if items:
        await r.delete(key)
    signals = []
    for it in reversed(items):
        try:
            signals.append(json.loads(it))
        except (ValueError, TypeError):
            pass
    return {"signals": signals}


@router.post("/{session_id}/join")
async def join_live(
    session_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """پیوستنِ بیننده — به میزبان اعلام می‌کند تا offer بفرستد."""
    s = await _get_live(db, session_id)
    if s.status != "live":
        raise HTTPException(status_code=410, detail="این پخش پایان یافته است")
    host = await db.get(User, s.host_id)
    r = await get_redis()
    sid = str(s.id)
    if host.id != me.id:
        # بیننده را در حضور ثبت کن و به میزبان خبر بده
        await r.zadd(VIEWERS_PREFIX + sid, {me.earth_id: time.time()})
        await r.expire(VIEWERS_PREFIX + sid, STATE_TTL)
        await _push(r, host.earth_id, {
            "type": "viewer-join", "session_id": sid,
            "from": me.earth_id,
            "from_name": me.full_name or me.username or me.earth_id,
            "from_avatar": me.avatar_url, "ts": time.time(),
        })
    vc = await _viewer_count(r, sid)
    # peak را در صورتِ لزوم به‌روزرسانی کن
    if vc > (s.peak_viewers or 0):
        s.peak_viewers = vc
        await db.commit()
    return {
        "session_id": sid,
        "host": _host_out(host),
        "host_earth_id": host.earth_id,
        "title": s.title,
        "status": s.status,
        "iceServers": ICE_SERVERS,
        "viewer_count": vc,
        "hearts": await _hearts(r, sid),
        "is_host": host.id == me.id,
    }


@router.post("/{session_id}/leave")
async def leave_live(
    session_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """ترکِ بیننده — از حضور حذف و به میزبان خبر می‌دهد."""
    s = await _get_live(db, session_id)
    host = await db.get(User, s.host_id)
    r = await get_redis()
    sid = str(s.id)
    await r.zrem(VIEWERS_PREFIX + sid, me.earth_id)
    if host and host.id != me.id:
        await _push(r, host.earth_id, {
            "type": "viewer-leave", "session_id": sid,
            "from": me.earth_id, "ts": time.time(),
        })
    return {"ok": True}


@router.get("/{session_id}/state")
async def live_state(
    session_id: str,
    heartbeat: bool = Query(True, description="حضورِ بیننده را تازه کن"),
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """وضعیتِ لحظه‌ای (بیننده‌ها/قلب‌ها/status) + heartbeatِ حضورِ بیننده."""
    s = await _get_live(db, session_id)
    r = await get_redis()
    sid = str(s.id)
    if heartbeat and s.status == "live" and s.host_id != me.id:
        await r.zadd(VIEWERS_PREFIX + sid, {me.earth_id: time.time()})
        await r.expire(VIEWERS_PREFIX + sid, STATE_TTL)
    return {
        "session_id": sid,
        "status": s.status,
        "viewer_count": await _viewer_count(r, sid),
        "hearts": await _hearts(r, sid),
    }


@router.post("/{session_id}/chat")
async def live_chat(
    session_id: str,
    body: ChatIn,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """ارسالِ پیامِ چتِ زنده (روی Redis، ephemeral)."""
    s = await _get_live(db, session_id)
    if s.status != "live":
        raise HTTPException(status_code=410, detail="این پخش پایان یافته است")
    r = await get_redis()
    sid = str(s.id)
    obj = {
        "id": _uuid.uuid4().hex[:12],
        "from": me.earth_id,
        "from_name": me.full_name or me.username or me.earth_id,
        "from_avatar": me.avatar_url,
        "text": body.text.strip()[:500],
        "ts": time.time(),
    }
    key = CHAT_PREFIX + sid
    await r.rpush(key, json.dumps(obj))
    await r.ltrim(key, -MAX_CHAT, -1)
    await r.expire(key, STATE_TTL)
    return obj


@router.get("/{session_id}/messages")
async def live_messages(
    session_id: str,
    limit: int = Query(50, ge=1, le=MAX_CHAT),
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """پیام‌های اخیرِ چتِ زنده (قدیم→جدید)."""
    await _get_live(db, session_id)
    r = await get_redis()
    key = CHAT_PREFIX + session_id
    items = await r.lrange(key, -limit, -1)
    msgs = []
    for it in items:
        try:
            msgs.append(json.loads(it))
        except (ValueError, TypeError):
            pass
    return {"items": msgs}


@router.post("/{session_id}/heart")
async def live_heart(
    session_id: str,
    body: HeartIn,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """ارسالِ قلب (❤) — شمارندهٔ Redis را افزایش می‌دهد."""
    s = await _get_live(db, session_id)
    r = await get_redis()
    sid = str(s.id)
    total = await r.incrby(HEARTS_PREFIX + sid, body.count)
    await r.expire(HEARTS_PREFIX + sid, STATE_TTL)
    return {"hearts": int(total)}


@router.post("/{session_id}/stop")
async def stop_live(
    session_id: str,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """پایانِ پخش — فقط میزبان. آمار نهایی را روی رکورد ذخیره می‌کند."""
    s = await _get_live(db, session_id)
    if s.host_id != me.id:
        raise HTTPException(status_code=403, detail="فقط میزبان می‌تواند پخش را پایان دهد")
    r = await get_redis()
    sid = str(s.id)
    if s.status == "live":
        s.status = "ended"
        s.ended_at = _now()
        s.total_hearts = await _hearts(r, sid)
        vc = await _viewer_count(r, sid)
        if vc > (s.peak_viewers or 0):
            s.peak_viewers = vc
        await db.commit()
    # پاک‌سازیِ کلیدهای Redis
    await r.delete(VIEWERS_PREFIX + sid, HEARTS_PREFIX + sid, CHAT_PREFIX + sid)
    return {"ok": True, "peak_viewers": s.peak_viewers or 0, "total_hearts": s.total_hearts or 0}

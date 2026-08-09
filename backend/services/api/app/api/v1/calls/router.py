"""
Dilix — Calls Router (Phase 1: WebRTC 1:1 voice/video)
سیگنالینگِ HTTP + Redis (poll-based) — پشتِ rewriteِ Next کار می‌کند (بدون نیاز به WebSocket).
مدیا کاملاً P2P (WebRTC) است؛ سرور فقط SDP/ICE و حضور را رله می‌کند.

GET  /api/v1/calls/ice-servers   پیکربندی ICE (STUN/TURN)
POST /api/v1/calls/invite        شروع تماس (ارسال offer به مخاطب)
POST /api/v1/calls/signal        answer/ice/reject/cancel/end/busy/caption
GET  /api/v1/calls/poll          دریافت سیگنال‌های صف‌شده + heartbeat حضور
POST /api/v1/calls/call-log      ثبت لاگِ تماس به‌صورتِ پیام در چت
"""
import json
import time
import hmac
import base64
import hashlib
import uuid as _uuid
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.config import settings
from app.core.database import get_db
from app.core.redis import get_redis
from app.models.user import User
from app.models.messages import Message
from app.api.v1.messages.router import _get_or_create_direct_room

router = APIRouter(prefix="/calls", tags=["Calls"])

Q_PREFIX = "calls:q:"        # LIST به‌ازای هر earth_id — صفِ سیگنال
SEEN_PREFIX = "calls:seen:"  # کلیدِ حضور (heartbeat با TTL)
ROSTER_PREFIX = "calls:roster:"  # SET به‌ازای هر call_id — اعضای تماسِ گروهی
Q_TTL = 90
SEEN_TTL = 15
MAX_Q = 60
ROSTER_TTL = 4 * 3600        # سقفِ عمرِ یک تماس؛ کلیدِ یتیم را جمع می‌کند
MAX_PARTICIPANTS = 6         # سقفِ mesh: هر عضو با بقیه اتصالِ جدا دارد

ICE_SERVERS = [
    {"urls": "stun:stun.l.google.com:19302"},
    {"urls": "stun:stun1.l.google.com:19302"},
]

_SIGNAL_TYPES = {
    "answer", "ice", "reject", "cancel", "end", "busy", "caption",
    "reoffer", "reanswer",
    # ── تماسِ گروهی (mesh) ──
    # `offer`      : offerِ یک اتصالِ تازه به عضوی که **از قبل** در تماس است.
    #                از `incoming` جداست چون نباید زنگ بخورد.
    # `peer-join`  : «فلانی وارد شد» — سرور به اعضای قدیمی می‌فرستد تا offer بسازند
    # `peer-left`  : «من رفتم» — گیرنده فقط همان اتصال را می‌بندد، نه کلِ تماس
    # `screen`     : اعلامِ روشن/خاموش‌شدنِ اشتراکِ صفحه (متن: on|off)
    "offer", "peer-join", "peer-left", "screen",
}


class InviteRequest(BaseModel):
    to_earth_id: str
    media: str = Field("audio")          # audio | video
    sdp: str = Field(..., min_length=1)  # JSON.stringify({type,sdp}) از سمتِ کلاینت
    call_id: Optional[str] = None


class SignalRequest(BaseModel):
    call_id: str
    to_earth_id: str
    type: str
    sdp: Optional[str] = None
    candidate: Optional[dict] = None
    text: Optional[str] = Field(None, max_length=1000)  # زیرنویسِ گفتار (caption)
    lang: Optional[str] = Field(None, max_length=8)     # زبانِ گویندهٔ متن (مبدأ)


class CallLogRequest(BaseModel):
    to_earth_id: str
    media: str = Field("audio")
    status: str = Field("answered")  # answered | no_answer | rejected | canceled | missed | failed
    duration_seconds: int = Field(0, ge=0, le=86400)


async def _push(r, to_earth: str, obj: dict) -> None:
    key = Q_PREFIX + to_earth
    await r.lpush(key, json.dumps(obj))
    await r.ltrim(key, 0, MAX_Q - 1)
    await r.expire(key, Q_TTL)


# ── فهرستِ اعضای تماس (mesh) ──────────────────────────────────
# سرور فقط عضویت را نگه می‌دارد؛ مدیا همچنان P2P است و هر عضو با هر عضوِ دیگر
# یک PeerConnection جدا دارد. به همین دلیل سقفِ MAX_PARTICIPANTS وجود دارد:
# با n عضو، هر گوشی n-1 اتصالِ رمزنگاری‌شده بالا می‌بَرد.

async def _roster(r, call_id: str) -> list[str]:
    members = await r.smembers(ROSTER_PREFIX + call_id)
    return sorted(members or [])


async def _roster_add(r, call_id: str, *earth_ids: str) -> None:
    key = ROSTER_PREFIX + call_id
    await r.sadd(key, *earth_ids)
    await r.expire(key, ROSTER_TTL)


async def _roster_remove(r, call_id: str, earth_id: str) -> list[str]:
    """حذفِ عضو و برگرداندنِ باقی‌مانده. با خالی‌شدن، کلید پاک می‌شود."""
    key = ROSTER_PREFIX + call_id
    await r.srem(key, earth_id)
    rest = sorted(await r.smembers(key) or [])
    if not rest:
        await r.delete(key)
    return rest


def _turn_credentials(seed: str):
    """RFC5766 REST — کردنشالِ کوتاه‌عمرِ HMAC برای coturn (use-auth-secret)."""
    expiry = int(time.time()) + settings.TURN_TTL
    username = f"{expiry}:{seed}"
    digest = hmac.new(settings.TURN_SECRET.encode(), username.encode(), hashlib.sha1).digest()
    return username, base64.b64encode(digest).decode()


@router.get("/ice-servers")
async def ice_servers(me: User = Depends(get_current_user)):
    """پیکربندیِ ICE؛ STUNِ عمومی + STUN/TURNِ خودی با کردنشالِ کوتاه‌عمر."""
    servers = list(ICE_SERVERS)
    host = settings.TURN_HOST
    if host and settings.TURN_SECRET:
        servers.append({"urls": f"stun:{host}:3478"})
        username, credential = _turn_credentials(me.earth_id)
        urls = [
            f"turn:{host}:3478?transport=udp",
            f"turn:{host}:3478?transport=tcp",
        ]
        tls_host = settings.TURN_TLS_HOST
        if tls_host:
            urls.append(f"turns:{tls_host}:5349?transport=tcp")
        servers.append({
            "urls": urls,
            "username": username,
            "credential": credential,
        })
    return {"iceServers": servers}


@router.post("/invite")
async def invite(body: InviteRequest, me: User = Depends(get_current_user)):
    """دعوت به تماس.

    دو کاربرد با یک بدنه:
    * `call_id` خالی → تماسِ تازهٔ ۱:۱.
    * `call_id` موجود → افزودنِ نفرِ تازه به تماسِ در جریان. در این حالت سرور
      علاوه بر زنگ‌زدن به دعوت‌شده، به بقیهٔ اعضا `peer-join` می‌دهد تا هرکدام
      یک اتصالِ mesh به او باز کنند. بدونِ این پیام، نفرِ تازه فقط صدای
      دعوت‌کننده را می‌شنید و بقیه او را نمی‌دیدند.
    """
    to = body.to_earth_id.strip().upper()
    if to == me.earth_id:
        raise HTTPException(status_code=400, detail="نمی‌توانید به خودتان زنگ بزنید")
    media = "video" if body.media == "video" else "audio"
    call_id = body.call_id or _uuid.uuid4().hex
    r = await get_redis()

    existing = await _roster(r, call_id) if body.call_id else []
    if existing:
        if me.earth_id not in existing:
            raise HTTPException(status_code=403, detail="شما عضوِ این تماس نیستید")
        if to in existing:
            raise HTTPException(status_code=409, detail="این مخاطب در تماس است")
        if len(existing) >= MAX_PARTICIPANTS:
            raise HTTPException(
                status_code=409,
                detail=f"سقفِ اعضای تماس {MAX_PARTICIPANTS} نفر است",
            )

    online = await r.get(SEEN_PREFIX + to)
    if not online:
        return {"call_id": call_id, "status": "offline", "members": existing}

    await _push(r, to, {
        "type": "incoming", "call_id": call_id,
        "from": me.earth_id,
        "from_name": me.full_name or me.username or me.earth_id,
        "from_avatar": me.avatar_url,
        "media": media, "sdp": body.sdp,
        # دعوت‌شده باید بداند وارد یک تماسِ چندنفره می‌شود تا بعد از پاسخ،
        # منتظرِ offerِ بقیهٔ اعضا بماند.
        "members": [m for m in existing if m != to],
        "ts": time.time(),
    })

    for member in existing:
        if member in (me.earth_id, to):
            continue
        await _push(r, member, {
            "type": "peer-join", "call_id": call_id,
            "from": me.earth_id, "peer": to,
            "peer_name": "", "media": media, "ts": time.time(),
        })

    await _roster_add(r, call_id, me.earth_id, to)
    return {
        "call_id": call_id,
        "status": "ringing",
        "members": sorted(set(existing) | {me.earth_id, to}),
    }


@router.get("/{call_id}/members")
async def call_members(call_id: str, me: User = Depends(get_current_user)):
    """اعضای فعلیِ تماس. برای هم‌گام‌کردنِ UI پس از افتادن و برگشتنِ شبکه."""
    r = await get_redis()
    members = await _roster(r, call_id)
    if members and me.earth_id not in members:
        raise HTTPException(status_code=403, detail="شما عضوِ این تماس نیستید")
    return {"call_id": call_id, "members": members}


@router.post("/signal")
async def signal(body: SignalRequest, me: User = Depends(get_current_user)):
    """رله‌ی سیگنال به صفِ مخاطب + نگه‌داشتنِ فهرستِ اعضا.

    خروج (`end`/`peer-left`/`reject`) باید فرستنده را از فهرست بردارد، وگرنه
    نفرِ بعدی که دعوت می‌شود برای یک عضوِ رفته هم اتصال باز می‌کند و در UI یک
    کاشیِ همیشه‌درحالِ‌اتصال می‌مانَد.
    """
    if body.type not in _SIGNAL_TYPES:
        raise HTTPException(status_code=400, detail="نوعِ سیگنال نامعتبر")
    to = body.to_earth_id.strip().upper()
    r = await get_redis()
    await _push(r, to, {
        "type": body.type, "call_id": body.call_id,
        "from": me.earth_id, "sdp": body.sdp,
        "candidate": body.candidate,
        "text": body.text, "lang": body.lang, "ts": time.time(),
    })
    if body.type in ("end", "peer-left", "reject", "cancel"):
        await _roster_remove(r, body.call_id, me.earth_id)
    return {"ok": True}


@router.get("/poll")
async def poll(me: User = Depends(get_current_user)):
    """دریافت و خالی‌کردنِ صفِ سیگنالِ من + تازه‌کردنِ حضور (heartbeat)."""
    r = await get_redis()
    await r.set(SEEN_PREFIX + me.earth_id, "1", ex=SEEN_TTL)
    key = Q_PREFIX + me.earth_id
    items = await r.lrange(key, 0, -1)
    if items:
        await r.delete(key)
    signals = []
    for it in reversed(items):   # lpush → جدیدترین اول؛ برعکس تا ترتیبِ زمانی شود
        try:
            signals.append(json.loads(it))
        except (ValueError, TypeError):
            pass
    return {"signals": signals}


@router.post("/call-log")
async def call_log(
    body: CallLogRequest,
    db: AsyncSession = Depends(get_db),
    me: User = Depends(get_current_user),
):
    """ثبتِ لاگِ تماس به‌صورتِ یک پیامِ چت (media_type=call) — فقط تماس‌گیرنده ثبت می‌کند."""
    to = body.to_earth_id.strip().upper()
    partner = (await db.execute(select(User).where(User.earth_id == to))).scalar_one_or_none()
    if not partner:
        raise HTTPException(status_code=404, detail="کاربر پیدا نشد")
    room = await _get_or_create_direct_room(db, me.id, partner.id)
    media = "video" if body.media == "video" else "audio"
    meta = json.dumps({"media": media, "status": body.status, "duration": body.duration_seconds})
    msg = Message(room_id=room.id, sender_id=me.id, content="", media_type="call", media_meta=meta)
    db.add(msg)
    await db.commit()
    await db.refresh(msg)
    return {"id": str(msg.id), "room_id": str(room.id), "created_at": msg.created_at}

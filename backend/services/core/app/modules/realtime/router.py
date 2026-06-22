"""روتر Realtime — WebSocket Gateway + Presence API (سند ۵).

WebSocket:
  WS /v1/ws?token=<access_token>   — اتصال realtime اصلی

HTTP (REST):
  GET /v1/realtime/presence/{earth_id}  — وضعیت حضور کاربر
  GET /v1/realtime/online               — لیست کاربران آنلاین (admin only)

پروتکل پیام:
  هر پیام JSON با فیلد "type" است.
  مثال ping/pong:
    کلاینت → {"type": "ping"}
    سرور   → {"type": "pong", "payload": {}, "ts": "..."}
"""
from __future__ import annotations

import json
import logging
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Query, WebSocket, WebSocketDisconnect

from app.core.security import decode_token
from app.modules.auth.deps import get_current_earth_id
from app.modules.realtime.connection_manager import manager
from app.modules.realtime.schemas import PresenceResponse, WsEventType, WsIncoming

logger = logging.getLogger("dilix.realtime")

router = APIRouter(tags=["realtime"])

# پیام‌های signaling که فقط بینِ دو طرف relay می‌شوند (سرور رسانه را نمی‌بیند)
_WEBRTC_SIGNALS = frozenset({
    WsEventType.CALL_OFFER,
    WsEventType.CALL_ANSWER,
    WsEventType.CALL_END,
    WsEventType.ICE_CANDIDATE,
})


async def _relay_signal(
    signal_type: WsEventType, from_earth_id: str, payload: dict
) -> None:
    """انتقالِ پیامِ signaling به طرفِ مقابل (payload باید "to" داشته باشد)."""
    to_earth_id = payload.get("to")
    if not to_earth_id:
        return
    await manager.send_to(
        str(to_earth_id),
        {
            "type": signal_type,
            "payload": {**payload, "from": from_earth_id},
            "ts": datetime.now(timezone.utc).isoformat(),
        },
    )


# ──────────────────────── WebSocket ──────────────────────────

@router.websocket("/v1/ws")
async def websocket_endpoint(
    ws: WebSocket,
    token: str = Query(..., description="JWT access token"),
) -> None:
    """اتصال WebSocket اصلی. احراز هویت از طریق query param token انجام می‌شود."""
    # احراز هویت
    payload = decode_token(token)
    if not payload or payload.get("type") != "access":
        await ws.close(code=4001, reason="توکن نامعتبر")
        return

    earth_id: str = payload["sub"]
    await manager.connect(ws, earth_id)

    try:
        while True:
            raw = await ws.receive_text()
            try:
                data = json.loads(raw)
                msg = WsIncoming(**data)
            except Exception:
                await ws.send_json({"type": WsEventType.ERROR, "detail": "فرمت پیام نامعتبر"})
                continue

            # ── کنترل پیام‌های ورودی ──
            if msg.type == WsEventType.PING:
                await ws.send_json({
                    "type": WsEventType.PONG,
                    "payload": {},
                    "ts": datetime.now(timezone.utc).isoformat(),
                })

            elif msg.type == WsEventType.TYPING_START:
                room_id = msg.payload.get("room_id", "")
                # fan-out به اعضای اتاق (در نسخه‌ی کامل از DB اعضا می‌خواند)
                logger.debug("typing.start room=%s user=%s", room_id, earth_id)

            elif msg.type == WsEventType.TYPING_STOP:
                room_id = msg.payload.get("room_id", "")
                logger.debug("typing.stop room=%s user=%s", room_id, earth_id)

            elif msg.type in _WEBRTC_SIGNALS:
                # WebRTC signaling: فقط relay بینِ دو طرف (سرور رسانه را نمی‌بیند)
                await _relay_signal(msg.type, earth_id, msg.payload)

            else:
                # رویدادهای دیگر در سرویس‌های مربوطه پردازش می‌شوند
                logger.debug("ws event: %s from %s", msg.type, earth_id)

    except WebSocketDisconnect:
        pass
    finally:
        await manager.disconnect(ws, earth_id)


# ──────────────────────── Presence REST ──────────────────────

@router.get("/v1/realtime/presence/{target_earth_id}", response_model=PresenceResponse)
async def get_presence(
    target_earth_id: uuid.UUID,
    _: uuid.UUID = Depends(get_current_earth_id),
) -> PresenceResponse:
    """وضعیت آنلاین/آفلاین و آخرین حضور یک کاربر."""
    eid = str(target_earth_id)
    last = manager.last_seen(eid)
    return PresenceResponse(
        earth_id=eid,
        online=manager.is_online(eid),
        last_seen=last.isoformat() if last else None,
    )


@router.get("/v1/realtime/online", response_model=list[str])
async def online_users(
    _: uuid.UUID = Depends(get_current_earth_id),
) -> list[str]:
    """لیست همه‌ی کاربران آنلاین (برای پنل مدیریت)."""
    return manager.online_users()
